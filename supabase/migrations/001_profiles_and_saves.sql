-- Lights Out GP · Stage 1: player profiles and cloud saves
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.

-- ---------- profiles ----------
-- One row per signed-in player. Level, XP and gold are written only by the server
-- (later stages add server functions that validate race results), never by the game directly.
create table if not exists public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default 'Driver' check (char_length(display_name) between 1 and 40),
  avatar_url    text,
  level         integer not null default 1 check (level between 1 and 50),
  xp            integer not null default 0 check (xp >= 0),
  gold          integer not null default 0 check (gold >= 0),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  last_seen_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Players read their own profile" on public.profiles;
create policy "Players read their own profile" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);

drop policy if exists "Players update their own profile" on public.profiles;
create policy "Players update their own profile" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- players may only change their name and last-seen time; level / xp / gold stay server-only
revoke insert, update, delete on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, last_seen_at) on public.profiles to authenticated;

-- ---------- player_saves ----------
-- The game's own saved data (settings, records, local career) so a player continues on any device.
create table if not exists public.player_saves (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  data               jsonb not null default '{}'::jsonb,
  client_updated_at  timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint player_saves_size check (pg_column_size(data) < 262144)
);

alter table public.player_saves enable row level security;

drop policy if exists "Players read their own save" on public.player_saves;
create policy "Players read their own save" on public.player_saves
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists "Players create their own save" on public.player_saves;
create policy "Players create their own save" on public.player_saves
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists "Players update their own save" on public.player_saves;
create policy "Players update their own save" on public.player_saves
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

revoke all on public.player_saves from anon;
grant select, insert, update on public.player_saves to authenticated;

-- ---------- timestamps ----------
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists player_saves_touch on public.player_saves;
create trigger player_saves_touch before update on public.player_saves
  for each row execute function public.touch_updated_at();

-- ---------- create a profile when someone signs up ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    left(coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''),
                  nullif(new.raw_user_meta_data ->> 'name', ''),
                  split_part(new.email, '@', 1),
                  'Driver'), 40),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end $$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- profiles for anyone who signed up before this script ran
insert into public.profiles (id, display_name, avatar_url)
select u.id,
       left(coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''), split_part(u.email, '@', 1), 'Driver'), 40),
       u.raw_user_meta_data ->> 'avatar_url'
from auth.users u
on conflict (id) do nothing;
