-- Lights Out GP · Stage 2: XP, levels 1-50 and rewards
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run. Safe to run again.
-- Players never write XP, level or gold themselves: the game calls start_race / finish_race,
-- and the server checks the result and works out the rewards.

-- ---------- levels: the whole progression, editable here or in the Table Editor ----------
create table if not exists public.levels (
  level         integer primary key check (level between 1 and 50),
  xp_total      integer not null check (xp_total >= 0),     -- total XP needed to reach this level
  reward_gold   integer not null default 0 check (reward_gold >= 0),
  reward_title  text,                                         -- driver title shown from this level on
  unlock_kind   text check (unlock_kind in ('track', 'feature', 'car', 'team', 'upgrade')),
  unlock_id     text,
  unlock_label  text
);
alter table public.levels enable row level security;
drop policy if exists "Anyone can read levels" on public.levels;
create policy "Anyone can read levels" on public.levels for select to anon, authenticated using (true);
revoke insert, update, delete on public.levels from anon, authenticated;
grant select on public.levels to anon, authenticated;

insert into public.levels (level, xp_total, reward_gold, reward_title, unlock_kind, unlock_id, unlock_label) values
  (1, 0, 0, 'Rookie', 'track', 'vespera', 'Circuito Vespera'),
  (2, 120, 60, null, null, null, null),
  (3, 266, 70, null, null, null, null),
  (4, 440, 80, null, 'track', 'porto', 'Porto Lume'),
  (5, 644, 270, 'Club Racer', null, null, null),
  (6, 880, 100, null, null, null, null),
  (7, 1150, 110, null, 'track', 'highland', 'Highland Ring'),
  (8, 1456, 120, null, null, null, null),
  (9, 1800, 130, null, null, null, null),
  (10, 2184, 420, 'Contender', 'feature', 'track_select', 'Advanced track selection'),
  (11, 2610, 150, null, null, null, null),
  (12, 3080, 160, null, null, null, null),
  (13, 3596, 170, null, 'track', 'sabbia', 'Sabbia Mirage'),
  (14, 4160, 180, null, null, null, null),
  (15, 4774, 570, 'Podium Hunter', null, null, null),
  (16, 5440, 200, null, null, null, null),
  (17, 6160, 210, null, null, null, null),
  (18, 6936, 220, null, null, null, null),
  (19, 7770, 230, null, null, null, null),
  (20, 8664, 720, 'Front Runner', null, null, null),
  (21, 9620, 250, null, null, null, null),
  (22, 10640, 260, null, null, null, null),
  (23, 11726, 270, null, null, null, null),
  (24, 12880, 280, null, null, null, null),
  (25, 14104, 870, 'Race Winner', null, null, null),
  (26, 15400, 300, null, null, null, null),
  (27, 16770, 310, null, null, null, null),
  (28, 18216, 320, null, null, null, null),
  (29, 19740, 330, null, null, null, null),
  (30, 21344, 1020, 'Veteran', null, null, null),
  (31, 23030, 350, null, null, null, null),
  (32, 24800, 360, null, null, null, null),
  (33, 26656, 370, null, null, null, null),
  (34, 28600, 380, null, null, null, null),
  (35, 30634, 1170, 'Pole Sitter', null, null, null),
  (36, 32760, 400, null, null, null, null),
  (37, 34980, 410, null, null, null, null),
  (38, 37296, 420, null, null, null, null),
  (39, 39710, 430, null, null, null, null),
  (40, 42224, 1320, 'Title Challenger', null, null, null),
  (41, 44840, 450, null, null, null, null),
  (42, 47560, 460, null, null, null, null),
  (43, 50386, 470, null, null, null, null),
  (44, 53320, 480, null, null, null, null),
  (45, 56364, 1470, 'Legend', null, null, null),
  (46, 59520, 500, null, null, null, null),
  (47, 62790, 510, null, null, null, null),
  (48, 66176, 520, null, null, null, null),
  (49, 69680, 530, null, null, null, null),
  (50, 73304, 1620, 'Grid Champion', 'feature', 'championship', 'Online Championship')
on conflict (level) do update set xp_total = excluded.xp_total, reward_gold = excluded.reward_gold, reward_title = excluded.reward_title,
  unlock_kind = excluded.unlock_kind, unlock_id = excluded.unlock_id, unlock_label = excluded.unlock_label;

-- ---------- tracks: used to check race times (min_lap_s = a lap faster than any car can drive) ----------
create table if not exists public.tracks (
  id            text primary key,
  name          text not null,
  min_lap_s     real not null check (min_lap_s > 0),
  unlock_level  integer not null default 1 references public.levels (level),
  sort          integer not null default 0
);
alter table public.tracks enable row level security;
drop policy if exists "Anyone can read tracks" on public.tracks;
create policy "Anyone can read tracks" on public.tracks for select to anon, authenticated using (true);
revoke insert, update, delete on public.tracks from anon, authenticated;
grant select on public.tracks to anon, authenticated;

insert into public.tracks (id, name, min_lap_s, unlock_level, sort) values
  ('vespera',  'Circuito Vespera', 55, 1,  1),
  ('porto',    'Porto Lume',       49, 4,  2),
  ('highland', 'Highland Ring',    43, 7,  3),
  ('sabbia',   'Sabbia Mirage',    46, 13, 4)
on conflict (id) do update set name = excluded.name, min_lap_s = excluded.min_lap_s, unlock_level = excluded.unlock_level, sort = excluded.sort;

-- ---------- races: one row per race a signed-in player starts ----------
create table if not exists public.races (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  mode          text not null check (mode in ('quick', 'career')),
  track_id      text not null references public.tracks (id),
  laps          integer not null,
  cars          integer not null,
  difficulty    text not null,
  weather       text not null,
  started_at    timestamptz not null default now(),
  finished_at   timestamptz,
  position      integer,
  race_time     real,
  best_lap      real,
  fastest_lap   boolean,
  penalties     integer,
  xp_awarded    integer,
  gold_awarded  integer,
  breakdown     jsonb
);
create index if not exists races_user_started on public.races (user_id, started_at desc);
alter table public.races enable row level security;
drop policy if exists "Players read their own races" on public.races;
create policy "Players read their own races" on public.races for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.races from anon;
revoke insert, update, delete on public.races from authenticated;
grant select on public.races to authenticated;

-- ---------- level history ----------
create table if not exists public.level_history (
  user_id     uuid not null references auth.users (id) on delete cascade,
  level       integer not null references public.levels (level),
  reached_at  timestamptz not null default now(),
  xp_total    integer not null,
  primary key (user_id, level)
);
alter table public.level_history enable row level security;
drop policy if exists "Players read their own level history" on public.level_history;
create policy "Players read their own level history" on public.level_history for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.level_history from anon;
revoke insert, update, delete on public.level_history from authenticated;
grant select on public.level_history to authenticated;

-- ---------- wallet log: every gold change (the wallet screen comes in Stage 4) ----------
create table if not exists public.wallet_transactions (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  amount         integer not null,
  balance_after  integer not null check (balance_after >= 0),
  kind           text not null check (kind in ('level_reward', 'race_reward', 'purchase', 'achievement', 'championship', 'adjustment')),
  ref            text,
  note           text,
  created_at     timestamptz not null default now()
);
create index if not exists wallet_user_created on public.wallet_transactions (user_id, created_at desc);
alter table public.wallet_transactions enable row level security;
drop policy if exists "Players read their own wallet" on public.wallet_transactions;
create policy "Players read their own wallet" on public.wallet_transactions for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.wallet_transactions from anon;
revoke insert, update, delete on public.wallet_transactions from authenticated;
grant select on public.wallet_transactions to authenticated;

-- level 1 counts as reached when the profile was created
insert into public.level_history (user_id, level, reached_at, xp_total)
select id, 1, created_at, 0 from public.profiles on conflict do nothing;

create or replace function public.handle_new_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.level_history (user_id, level, reached_at, xp_total) values (new.id, 1, new.created_at, 0) on conflict do nothing;
  return new;
end $$;
revoke execute on function public.handle_new_profile() from public, anon, authenticated;
drop trigger if exists on_profile_created on public.profiles;
create trigger on_profile_created after insert on public.profiles for each row execute function public.handle_new_profile();

-- ---------- helpers ----------
create or replace function public.level_for_xp(p_xp integer)
returns integer language sql stable set search_path = '' as $$
  select coalesce(max(level), 1) from public.levels where xp_total <= p_xp
$$;

-- ---------- start_race: the game calls this when the start lights begin ----------
create or replace function public.start_race(p_mode text, p_track text, p_laps integer, p_cars integer, p_difficulty text, p_weather text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  rid uuid;
begin
  if uid is null then raise exception 'Sign in to earn XP' using errcode = '28000'; end if;
  if p_mode not in ('quick', 'career') then raise exception 'Unknown race mode'; end if;
  if not exists (select 1 from public.tracks where id = p_track) then raise exception 'Unknown track'; end if;
  if p_laps not in (3, 5, 8) then raise exception 'Unsupported race distance'; end if;
  if p_cars not between 2 and 14 then raise exception 'Unsupported number of cars'; end if;
  if p_difficulty not in ('rookie', 'pro', 'champion') then raise exception 'Unknown difficulty'; end if;
  if p_weather not in ('dry', 'changeable', 'wet') then raise exception 'Unknown weather'; end if;
  -- one race at a time: starting a new race abandons the previous unfinished one
  delete from public.races where user_id = uid and finished_at is null;
  insert into public.races (user_id, mode, track_id, laps, cars, difficulty, weather)
  values (uid, p_mode, p_track, p_laps, p_cars, p_difficulty, p_weather)
  returning id into rid;
  return rid;
end $$;

-- ---------- finish_race: checks the result, awards XP and level rewards ----------
create or replace function public.finish_race(p_race uuid, p_position integer, p_race_time real, p_best_lap real, p_fastest_lap boolean, p_penalties integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  r public.races%rowtype;
  t public.tracks%rowtype;
  prof public.profiles%rowtype;
  lv record;
  elapsed real;
  mult real;
  field real;
  base_xp integer;
  pos_xp integer := 0;
  parts jsonb := '[]'::jsonb;
  v_xp integer;
  new_xp integer;
  lvl_after integer;
  v_gold integer := 0;
  rewards jsonb := '[]'::jsonb;
begin
  if uid is null then raise exception 'Sign in to earn XP' using errcode = '28000'; end if;
  select * into r from public.races where id = p_race and user_id = uid for update;
  if not found then raise exception 'Race not found'; end if;
  if r.finished_at is not null then raise exception 'This race result was already saved'; end if;
  select * into t from public.tracks where id = r.track_id;
  elapsed := extract(epoch from (now() - r.started_at));

  -- plausibility checks against the server clock and the track's fastest possible lap
  if p_position is null or p_position < 1 or p_position > r.cars then raise exception 'Invalid finishing position'; end if;
  if p_penalties is null or p_penalties < 0 or p_penalties > 600 then raise exception 'Invalid penalties'; end if;
  if p_race_time is null or p_race_time < r.laps * t.min_lap_s or p_race_time - p_penalties > elapsed + 10 then
    raise exception 'Race time could not be verified';
  end if;
  if elapsed < r.laps * t.min_lap_s then raise exception 'Race finished too quickly to be verified'; end if;
  if p_best_lap is null or p_best_lap < t.min_lap_s or p_best_lap > p_race_time then raise exception 'Lap time could not be verified'; end if;

  -- XP: finishing + result + objectives, scaled by difficulty; a bigger field is worth more
  mult  := case r.difficulty when 'rookie' then 0.8 when 'champion' then 1.25 else 1.0 end;
  field := 0.4 + 0.6 * (r.cars - 1) / 13.0;
  base_xp := 40 + 20 * r.laps;
  parts := parts || jsonb_build_object('label', 'Race completed', 'xp', round(base_xp * mult));
  pos_xp := case when p_position = 1 then 150 when p_position = 2 then 100 when p_position = 3 then 70
                 when p_position <= greatest(3, r.cars / 2) then 30 else 0 end;
  pos_xp := round(pos_xp * field);
  if pos_xp > 0 then
    parts := parts || jsonb_build_object('label', case p_position when 1 then 'Victory' when 2 then 'Second place' when 3 then 'Third place' else 'Top half finish' end, 'xp', round(pos_xp * mult));
  end if;
  if coalesce(p_fastest_lap, false) then parts := parts || jsonb_build_object('label', 'Objective: fastest lap', 'xp', round(30 * mult)); end if;
  if p_penalties = 0 then parts := parts || jsonb_build_object('label', 'Objective: clean race', 'xp', round(20 * mult)); end if;
  select coalesce(sum((e ->> 'xp')::integer), 0) into v_xp from jsonb_array_elements(parts) e;

  select * into prof from public.profiles where id = uid for update;
  new_xp := prof.xp + v_xp;
  lvl_after := public.level_for_xp(new_xp);
  for lv in select * from public.levels where level > prof.level and level <= lvl_after order by level loop
    insert into public.level_history (user_id, level, xp_total) values (uid, lv.level, new_xp) on conflict do nothing;
    if lv.reward_gold > 0 then
      v_gold := v_gold + lv.reward_gold;
      insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
      values (uid, lv.reward_gold, prof.gold + v_gold, 'level_reward', 'level:' || lv.level, 'Reached level ' || lv.level);
    end if;
    rewards := rewards || jsonb_build_object('level', lv.level, 'gold', lv.reward_gold, 'title', lv.reward_title,
      'unlock_kind', lv.unlock_kind, 'unlock_id', lv.unlock_id, 'unlock_label', lv.unlock_label);
  end loop;

  update public.profiles set xp = new_xp, level = lvl_after, gold = prof.gold + v_gold where id = uid;
  update public.races set finished_at = now(), position = p_position, race_time = p_race_time, best_lap = p_best_lap,
    fastest_lap = coalesce(p_fastest_lap, false), penalties = p_penalties, xp_awarded = v_xp, gold_awarded = v_gold, breakdown = parts
  where id = p_race;

  return jsonb_build_object('xp', v_xp, 'breakdown', parts, 'xp_total', new_xp, 'level_before', prof.level, 'level_after', lvl_after,
    'gold', v_gold, 'gold_total', prof.gold + v_gold, 'rewards', rewards);
end $$;

revoke execute on function public.start_race(text, text, integer, integer, text, text) from public, anon;
revoke execute on function public.finish_race(uuid, integer, real, real, boolean, integer) from public, anon;
grant execute on function public.start_race(text, text, integer, integer, text, text) to authenticated;
grant execute on function public.finish_race(uuid, integer, real, real, boolean, integer) to authenticated;
