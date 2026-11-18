-- Lights Out GP · Stage 6: Championship (unlocks at level 50) - seasons, schedule, points, standings, leaderboard
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.
-- Live multiplayer races (Stage 7) write championship_results from the race server; players never write them.

-- ---------- points (F1 style, top 10) ----------
create table if not exists public.championship_points (
  position  integer primary key check (position between 1 and 20),
  points    integer not null check (points >= 0)
);
insert into public.championship_points (position, points) values (1,25),(2,18),(3,15),(4,12),(5,10),(6,8),(7,6),(8,4),(9,2),(10,1)
on conflict (position) do update set points = excluded.points;

-- ---------- seasons and their schedule ----------
create table if not exists public.championship_seasons (
  id         integer primary key,
  name       text not null,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null
);
create table if not exists public.championship_rounds (
  season_id  integer not null references public.championship_seasons (id) on delete cascade,
  round      integer not null check (round > 0),
  track_id   text not null references public.tracks (id),
  laps       integer not null default 5 check (laps in (3, 5, 8)),
  opens_at   timestamptz not null,
  closes_at  timestamptz not null,
  primary key (season_id, round)
);

-- Season 1: one round a week on each circuit, starting next Monday (UTC)
insert into public.championship_seasons (id, name, starts_at, ends_at)
select 1, 'Season 1', date_trunc('week', now()) + interval '7 days', date_trunc('week', now()) + interval '63 days'
on conflict (id) do nothing;
insert into public.championship_rounds (season_id, round, track_id, laps, opens_at, closes_at)
select 1, t.sort, t.id, 5, s.starts_at + (t.sort - 1) * interval '7 days', s.starts_at + t.sort * interval '7 days'
from public.tracks t cross join public.championship_seasons s where s.id = 1
on conflict (season_id, round) do nothing;

-- ---------- entries and results ----------
create table if not exists public.championship_entries (
  season_id  integer not null references public.championship_seasons (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  team_id    text not null references public.teams (id),
  joined_at  timestamptz not null default now(),
  primary key (season_id, user_id)
);
create table if not exists public.championship_results (
  season_id    integer not null,
  round        integer not null,
  user_id      uuid not null references auth.users (id) on delete cascade,
  team_id      text not null references public.teams (id),
  position     integer not null check (position > 0),
  points       integer not null default 0,
  fastest_lap  boolean not null default false,
  race_ref     text,
  recorded_at  timestamptz not null default now(),
  primary key (season_id, round, user_id),
  foreign key (season_id, round) references public.championship_rounds (season_id, round) on delete cascade
);

-- read-only catalogue for everyone; entries/results are only exposed through the functions below
alter table public.championship_points  enable row level security;
alter table public.championship_seasons enable row level security;
alter table public.championship_rounds  enable row level security;
alter table public.championship_entries enable row level security;
alter table public.championship_results enable row level security;
drop policy if exists "Anyone can read points" on public.championship_points;
create policy "Anyone can read points" on public.championship_points for select to anon, authenticated using (true);
drop policy if exists "Anyone can read seasons" on public.championship_seasons;
create policy "Anyone can read seasons" on public.championship_seasons for select to anon, authenticated using (true);
drop policy if exists "Anyone can read rounds" on public.championship_rounds;
create policy "Anyone can read rounds" on public.championship_rounds for select to anon, authenticated using (true);
drop policy if exists "Players read their own entry" on public.championship_entries;
create policy "Players read their own entry" on public.championship_entries for select to authenticated using ((select auth.uid()) = user_id);
revoke insert, update, delete on public.championship_points, public.championship_seasons, public.championship_rounds from anon, authenticated;
revoke all on public.championship_entries, public.championship_results from anon;
revoke insert, update, delete on public.championship_entries, public.championship_results from authenticated;
grant select on public.championship_points, public.championship_seasons, public.championship_rounds to anon, authenticated;
grant select on public.championship_entries to authenticated;

-- ---------- functions ----------
-- the current (or next) season with its schedule, points table and the caller's entry
create or replace function public.championship_overview()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_season public.championship_seasons%rowtype;
  v_level integer;
  v_xp integer;
  v_need integer;
begin
  if uid is null then raise exception 'Sign in to see the Championship' using errcode = '28000'; end if;
  select level, xp into v_level, v_xp from public.profiles where id = uid;
  select xp_total into v_need from public.levels where level = 50;
  select * into v_season from public.championship_seasons where ends_at > now() order by starts_at limit 1;
  if not found then select * into v_season from public.championship_seasons order by starts_at desc limit 1; end if;
  return jsonb_build_object(
    'unlock_level', 50, 'level', v_level, 'xp', v_xp, 'xp_needed', v_need, 'unlocked', v_level >= 50,
    'now', now(),
    'season', to_jsonb(v_season),
    'rounds', (select coalesce(jsonb_agg(jsonb_build_object('round', r.round, 'track_id', r.track_id, 'laps', r.laps, 'opens_at', r.opens_at, 'closes_at', r.closes_at,
                 'status', case when now() < r.opens_at then 'upcoming' when now() < r.closes_at then 'open' else 'closed' end) order by r.round), '[]'::jsonb)
               from public.championship_rounds r where r.season_id = v_season.id),
    'points', (select jsonb_agg(jsonb_build_object('position', position, 'points', points) order by position) from public.championship_points),
    'entry', (select to_jsonb(e) - 'user_id' from public.championship_entries e where e.season_id = v_season.id and e.user_id = uid),
    'entrants', (select count(*) from public.championship_entries e where e.season_id = v_season.id)
  );
end $$;

-- join (or switch team) - level 50 only, and only before the season starts
create or replace function public.join_championship(p_team text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_level integer;
  v_season public.championship_seasons%rowtype;
begin
  if uid is null then raise exception 'Sign in to join the Championship' using errcode = '28000'; end if;
  select level into v_level from public.profiles where id = uid;
  if v_level < 50 then raise exception 'The Championship unlocks at level 50'; end if;
  if not exists (select 1 from public.teams where id = p_team) then raise exception 'Unknown team'; end if;
  select * into v_season from public.championship_seasons where ends_at > now() order by starts_at limit 1;
  if not found then raise exception 'There is no Championship season to join right now'; end if;
  if now() >= v_season.starts_at and exists (select 1 from public.championship_entries where season_id = v_season.id and user_id = uid) then
    raise exception 'Teams are locked once the season has started';
  end if;
  insert into public.championship_entries (season_id, user_id, team_id) values (v_season.id, uid, p_team)
  on conflict (season_id, user_id) do update set team_id = excluded.team_id;
  return public.championship_overview();
end $$;

-- driver and team standings for a season (names only; no emails or ids leave the server)
create or replace function public.championship_standings(p_season integer)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'drivers', coalesce((
      select jsonb_agg(d order by d.points desc, d.wins desc, d.name)
      from (
        select p.display_name as name, p.avatar_url as avatar, e.team_id as team,
               coalesce(sum(r.points), 0)::integer as points,
               count(r.round) filter (where r.position = 1)::integer as wins,
               count(r.round)::integer as races,
               (e.user_id = auth.uid()) as me
        from public.championship_entries e
        join public.profiles p on p.id = e.user_id
        left join public.championship_results r on r.season_id = e.season_id and r.user_id = e.user_id
        where e.season_id = p_season
        group by p.display_name, p.avatar_url, e.team_id, e.user_id
      ) d), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(t order by t.points desc, t.team)
      from (
        select tm.id as team, tm.name, coalesce(sum(r.points), 0)::integer as points,
               (select count(*) from public.championship_entries e2 where e2.season_id = p_season and e2.team_id = tm.id)::integer as drivers
        from public.teams tm
        left join public.championship_results r on r.season_id = p_season and r.team_id = tm.id
        group by tm.id, tm.name
      ) t), '[]'::jsonb)
  )
$$;

-- global leaderboard by XP (top 50 + the caller's own rank)
create or replace function public.global_leaderboard()
returns jsonb language sql stable security definer set search_path = '' as $$
  with ranked as (
    select p.id, p.display_name as name, p.avatar_url as avatar, p.level, p.xp, p.challenge,
           (select count(*) from public.races r where r.user_id = p.id and r.finished_at is not null and r.position = 1)::integer as wins,
           rank() over (order by p.xp desc, p.created_at) as rank
    from public.profiles p
  )
  select jsonb_build_object(
    'top', coalesce((select jsonb_agg(jsonb_build_object('rank', rank, 'name', name, 'avatar', avatar, 'level', level, 'xp', xp, 'wins', wins, 'challenge', challenge, 'me', id = auth.uid()) order by rank)
                     from ranked where rank <= 50), '[]'::jsonb),
    'me', (select jsonb_build_object('rank', rank, 'level', level, 'xp', xp, 'wins', wins) from ranked where id = auth.uid()),
    'players', (select count(*) from ranked)
  )
$$;

revoke execute on function public.championship_overview() from public, anon;
revoke execute on function public.join_championship(text) from public, anon;
revoke execute on function public.championship_standings(integer) from public, anon;
revoke execute on function public.global_leaderboard() from public, anon;
grant execute on function public.championship_overview() to authenticated;
grant execute on function public.join_championship(text) to authenticated;
grant execute on function public.championship_standings(integer) to authenticated;
grant execute on function public.global_leaderboard() to authenticated;
