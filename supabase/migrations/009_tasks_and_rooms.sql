-- Lights Out GP · levels by tasks + private multiplayer rooms
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.
-- Levels now go up when all 3 tasks of the current level are done (XP is still earned, but no longer decides the level).

-- ---------- tasks: 3 per level (levels 1-49), editable in the Table Editor ----------
-- params (all optional): count, pos (finish at or above), track, laps (at least), cars (at least),
--                        diff ('pro' = Pro or Champion, 'champion'), wet (not dry), clean (no penalties), fastest (fastest lap)
create table if not exists public.level_tasks (
  level        integer not null references public.levels (level),
  slot         integer not null check (slot between 1 and 3),
  params       jsonb not null,
  description  text not null,
  primary key (level, slot)
);
alter table public.level_tasks enable row level security;
drop policy if exists "Anyone can read level tasks" on public.level_tasks;
create policy "Anyone can read level tasks" on public.level_tasks for select to anon, authenticated using (true);
revoke insert, update, delete on public.level_tasks from anon, authenticated;
grant select on public.level_tasks to anon, authenticated;

insert into public.level_tasks (level, slot, params, description) values
  (1, 1, '{"track":"vespera","count":1}'::jsonb, 'Finish a race at Circuito Vespera'),
  (1, 2, '{"clean":true,"count":1}'::jsonb, 'Finish a race with no penalties'),
  (1, 3, '{"count":2}'::jsonb, 'Finish 2 races'),
  (2, 1, '{"track":"vespera","pos":5,"count":1}'::jsonb, 'Finish in the top 5 at Circuito Vespera'),
  (2, 2, '{"laps":5,"count":1}'::jsonb, 'Finish a race of 5+ laps'),
  (2, 3, '{"diff":"pro","pos":5,"count":1}'::jsonb, 'Finish in the top 5 on Pro pace or harder'),
  (3, 1, '{"track":"vespera","pos":5,"count":1}'::jsonb, 'Finish in the top 5 at Circuito Vespera'),
  (3, 2, '{"cars":8,"pos":5,"count":1}'::jsonb, 'Finish in the top 5 with 8+ cars on the grid'),
  (3, 3, '{"count":3}'::jsonb, 'Finish 3 races'),
  (4, 1, '{"track":"porto","count":1}'::jsonb, 'Finish a race at Porto Lume'),
  (4, 2, '{"clean":true,"count":1}'::jsonb, 'Finish a race with no penalties'),
  (4, 3, '{"count":3}'::jsonb, 'Finish 3 races'),
  (5, 1, '{"track":"porto","pos":5,"count":1}'::jsonb, 'Finish in the top 5 at Porto Lume'),
  (5, 2, '{"clean":true,"count":1}'::jsonb, 'Finish a race with no penalties'),
  (5, 3, '{"count":2}'::jsonb, 'Finish 2 races'),
  (6, 1, '{"track":"vespera","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Circuito Vespera'),
  (6, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (6, 3, '{"diff":"pro","pos":3,"count":1}'::jsonb, 'Finish in the top 3 on Pro pace or harder'),
  (7, 1, '{"track":"highland","count":1}'::jsonb, 'Finish a race at Highland Ring'),
  (7, 2, '{"laps":5,"pos":5,"count":1}'::jsonb, 'Finish in the top 5 in a race of 5+ laps'),
  (7, 3, '{"count":4}'::jsonb, 'Finish 4 races'),
  (8, 1, '{"track":"highland","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Highland Ring'),
  (8, 2, '{"cars":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with 8+ cars on the grid'),
  (8, 3, '{"count":4}'::jsonb, 'Finish 4 races'),
  (9, 1, '{"track":"vespera","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Circuito Vespera'),
  (9, 2, '{"clean":true,"count":1}'::jsonb, 'Finish a race with no penalties'),
  (9, 3, '{"count":3,"pos":5}'::jsonb, 'Finish in the top 5 in 3 races'),
  (10, 1, '{"track":"porto","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Porto Lume'),
  (10, 2, '{"clean":true,"pos":5,"count":1}'::jsonb, 'Finish in the top 5 with no penalties'),
  (10, 3, '{"diff":"pro","pos":3,"count":1}'::jsonb, 'Finish in the top 3 on Pro pace or harder'),
  (11, 1, '{"track":"highland","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Highland Ring'),
  (11, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (11, 3, '{"count":4}'::jsonb, 'Finish 4 races'),
  (12, 1, '{"track":"vespera","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Circuito Vespera'),
  (12, 2, '{"laps":5,"pos":5,"count":1}'::jsonb, 'Finish in the top 5 in a race of 5+ laps'),
  (12, 3, '{"wet":true,"pos":5,"count":1}'::jsonb, 'Finish in the top 5 in changeable or wet weather'),
  (13, 1, '{"track":"sabbia","count":1}'::jsonb, 'Finish a race at Sabbia Mirage'),
  (13, 2, '{"cars":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with 8+ cars on the grid'),
  (13, 3, '{"count":3,"pos":5}'::jsonb, 'Finish in the top 5 in 3 races'),
  (14, 1, '{"track":"highland","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Highland Ring'),
  (14, 2, '{"clean":true,"count":1}'::jsonb, 'Finish a race with no penalties'),
  (14, 3, '{"diff":"pro","pos":3,"count":1}'::jsonb, 'Finish in the top 3 on Pro pace or harder'),
  (15, 1, '{"track":"sabbia","pos":3,"count":1}'::jsonb, 'Finish in the top 3 at Sabbia Mirage'),
  (15, 2, '{"clean":true,"pos":5,"count":1}'::jsonb, 'Finish in the top 5 with no penalties'),
  (15, 3, '{"count":4}'::jsonb, 'Finish 4 races'),
  (16, 1, '{"track":"vespera","pos":1,"count":1}'::jsonb, 'Win a race at Circuito Vespera'),
  (16, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (16, 3, '{"wet":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in changeable or wet weather'),
  (17, 1, '{"track":"porto","pos":1,"count":1}'::jsonb, 'Win a race at Porto Lume'),
  (17, 2, '{"laps":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in a race of 8+ laps'),
  (17, 3, '{"count":4,"pos":3}'::jsonb, 'Finish in the top 3 in 4 races'),
  (18, 1, '{"track":"riva","count":1}'::jsonb, 'Finish a race at Monte Riva'),
  (18, 2, '{"cars":14,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with 14+ cars on the grid'),
  (18, 3, '{"diff":"champion","pos":3,"count":1}'::jsonb, 'Finish in the top 3 on Champion pace'),
  (19, 1, '{"track":"riva","pos":1,"count":1}'::jsonb, 'Win a race at Monte Riva'),
  (19, 2, '{"clean":true,"fastest":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with no penalties and set the fastest lap'),
  (19, 3, '{"count":5,"pos":5}'::jsonb, 'Finish in the top 5 in 5 races'),
  (20, 1, '{"track":"vespera","pos":1,"count":1}'::jsonb, 'Win a race at Circuito Vespera'),
  (20, 2, '{"clean":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with no penalties'),
  (20, 3, '{"wet":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in changeable or wet weather'),
  (21, 1, '{"track":"porto","pos":1,"count":1}'::jsonb, 'Win a race at Porto Lume'),
  (21, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (21, 3, '{"count":4,"pos":3}'::jsonb, 'Finish in the top 3 in 4 races'),
  (22, 1, '{"track":"highland","pos":1,"count":1}'::jsonb, 'Win a race at Highland Ring'),
  (22, 2, '{"laps":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in a race of 8+ laps'),
  (22, 3, '{"diff":"champion","pos":3,"count":1}'::jsonb, 'Finish in the top 3 on Champion pace'),
  (23, 1, '{"track":"sabbia","pos":1,"count":1}'::jsonb, 'Win a race at Sabbia Mirage'),
  (23, 2, '{"cars":14,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with 14+ cars on the grid'),
  (23, 3, '{"count":5,"pos":5}'::jsonb, 'Finish in the top 5 in 5 races'),
  (24, 1, '{"track":"velocita","count":1}'::jsonb, 'Finish a race at Autodromo Velocità'),
  (24, 2, '{"clean":true,"fastest":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with no penalties and set the fastest lap'),
  (24, 3, '{"wet":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in changeable or wet weather'),
  (25, 1, '{"track":"porto","pos":1,"count":1}'::jsonb, 'Win a race at Porto Lume'),
  (25, 2, '{"clean":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with no penalties'),
  (25, 3, '{"count":4,"pos":3}'::jsonb, 'Finish in the top 3 in 4 races'),
  (26, 1, '{"track":"highland","pos":1,"count":1}'::jsonb, 'Win a race at Highland Ring'),
  (26, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (26, 3, '{"diff":"champion","pos":3,"count":1}'::jsonb, 'Finish in the top 3 on Champion pace'),
  (27, 1, '{"track":"sabbia","pos":1,"count":1}'::jsonb, 'Win a race at Sabbia Mirage'),
  (27, 2, '{"laps":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in a race of 8+ laps'),
  (27, 3, '{"count":5,"pos":5}'::jsonb, 'Finish in the top 5 in 5 races'),
  (28, 1, '{"track":"riva","pos":1,"count":1}'::jsonb, 'Win a race at Monte Riva'),
  (28, 2, '{"cars":14,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with 14+ cars on the grid'),
  (28, 3, '{"wet":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in changeable or wet weather'),
  (29, 1, '{"track":"velocita","pos":1,"count":1}'::jsonb, 'Win a race at Autodromo Velocità'),
  (29, 2, '{"clean":true,"fastest":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with no penalties and set the fastest lap'),
  (29, 3, '{"count":4,"pos":3}'::jsonb, 'Finish in the top 3 in 4 races'),
  (30, 1, '{"track":"vespera","pos":1,"count":1}'::jsonb, 'Win a race at Circuito Vespera'),
  (30, 2, '{"clean":true,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 with no penalties'),
  (30, 3, '{"diff":"champion","pos":3,"count":1}'::jsonb, 'Finish in the top 3 on Champion pace'),
  (31, 1, '{"track":"bosco","count":1}'::jsonb, 'Finish a race at Bosco Verde Ring'),
  (31, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (31, 3, '{"count":6,"pos":3}'::jsonb, 'Finish in the top 3 in 6 races'),
  (32, 1, '{"track":"riva","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Monte Riva on Pro pace or harder'),
  (32, 2, '{"laps":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in a race of 8+ laps'),
  (32, 3, '{"wet":true,"pos":1,"count":1}'::jsonb, 'Win a race in changeable or wet weather'),
  (33, 1, '{"track":"velocita","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Autodromo Velocità on Pro pace or harder'),
  (33, 2, '{"cars":14,"pos":1,"count":1}'::jsonb, 'Win a race with 14+ cars on the grid'),
  (33, 3, '{"count":5,"pos":3}'::jsonb, 'Finish in the top 3 in 5 races'),
  (34, 1, '{"track":"bosco","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Bosco Verde Ring on Pro pace or harder'),
  (34, 2, '{"clean":true,"fastest":true,"pos":1,"count":1}'::jsonb, 'Win a race with no penalties and set the fastest lap'),
  (34, 3, '{"diff":"champion","pos":1,"count":1}'::jsonb, 'Win a race on Champion pace'),
  (35, 1, '{"track":"vespera","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Circuito Vespera on Pro pace or harder'),
  (35, 2, '{"clean":true,"pos":1,"count":1}'::jsonb, 'Win a race with no penalties'),
  (35, 3, '{"count":6,"pos":3}'::jsonb, 'Finish in the top 3 in 6 races'),
  (36, 1, '{"track":"porto","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Porto Lume on Pro pace or harder'),
  (36, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (36, 3, '{"wet":true,"pos":1,"count":1}'::jsonb, 'Win a race in changeable or wet weather'),
  (37, 1, '{"track":"highland","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Highland Ring on Pro pace or harder'),
  (37, 2, '{"laps":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in a race of 8+ laps'),
  (37, 3, '{"count":5,"pos":3}'::jsonb, 'Finish in the top 3 in 5 races'),
  (38, 1, '{"track":"neon","count":1}'::jsonb, 'Finish a race at Neon Bay'),
  (38, 2, '{"cars":14,"pos":1,"count":1}'::jsonb, 'Win a race with 14+ cars on the grid'),
  (38, 3, '{"diff":"champion","pos":1,"count":1}'::jsonb, 'Win a race on Champion pace'),
  (39, 1, '{"track":"neon","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Neon Bay on Pro pace or harder'),
  (39, 2, '{"clean":true,"fastest":true,"pos":1,"count":1}'::jsonb, 'Win a race with no penalties and set the fastest lap'),
  (39, 3, '{"count":6,"pos":3}'::jsonb, 'Finish in the top 3 in 6 races'),
  (40, 1, '{"track":"vespera","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Circuito Vespera on Pro pace or harder'),
  (40, 2, '{"clean":true,"pos":1,"count":1}'::jsonb, 'Win a race with no penalties'),
  (40, 3, '{"wet":true,"pos":1,"count":1}'::jsonb, 'Win a race in changeable or wet weather'),
  (41, 1, '{"track":"porto","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Porto Lume on Pro pace or harder'),
  (41, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (41, 3, '{"count":5,"pos":3}'::jsonb, 'Finish in the top 3 in 5 races'),
  (42, 1, '{"track":"highland","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Highland Ring on Pro pace or harder'),
  (42, 2, '{"laps":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in a race of 8+ laps'),
  (42, 3, '{"diff":"champion","pos":1,"count":1}'::jsonb, 'Win a race on Champion pace'),
  (43, 1, '{"track":"sabbia","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Sabbia Mirage on Pro pace or harder'),
  (43, 2, '{"cars":14,"pos":1,"count":1}'::jsonb, 'Win a race with 14+ cars on the grid'),
  (43, 3, '{"count":6,"pos":3}'::jsonb, 'Finish in the top 3 in 6 races'),
  (44, 1, '{"track":"riva","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Monte Riva on Pro pace or harder'),
  (44, 2, '{"clean":true,"fastest":true,"pos":1,"count":1}'::jsonb, 'Win a race with no penalties and set the fastest lap'),
  (44, 3, '{"wet":true,"pos":1,"count":1}'::jsonb, 'Win a race in changeable or wet weather'),
  (45, 1, '{"track":"velocita","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Autodromo Velocità on Pro pace or harder'),
  (45, 2, '{"clean":true,"pos":1,"count":1}'::jsonb, 'Win a race with no penalties'),
  (45, 3, '{"count":5,"pos":3}'::jsonb, 'Finish in the top 3 in 5 races'),
  (46, 1, '{"track":"bosco","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Bosco Verde Ring on Pro pace or harder'),
  (46, 2, '{"fastest":true,"count":1}'::jsonb, 'Finish a race and set the fastest lap'),
  (46, 3, '{"diff":"champion","pos":1,"count":1}'::jsonb, 'Win a race on Champion pace'),
  (47, 1, '{"track":"neon","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Neon Bay on Pro pace or harder'),
  (47, 2, '{"laps":8,"pos":3,"count":1}'::jsonb, 'Finish in the top 3 in a race of 8+ laps'),
  (47, 3, '{"count":6,"pos":3}'::jsonb, 'Finish in the top 3 in 6 races'),
  (48, 1, '{"track":"vespera","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Circuito Vespera on Pro pace or harder'),
  (48, 2, '{"cars":14,"pos":1,"count":1}'::jsonb, 'Win a race with 14+ cars on the grid'),
  (48, 3, '{"wet":true,"pos":1,"count":1}'::jsonb, 'Win a race in changeable or wet weather'),
  (49, 1, '{"track":"porto","pos":1,"diff":"pro","count":1}'::jsonb, 'Win a race at Porto Lume on Pro pace or harder'),
  (49, 2, '{"clean":true,"fastest":true,"pos":1,"count":1}'::jsonb, 'Win a race with no penalties and set the fastest lap'),
  (49, 3, '{"count":5,"pos":3}'::jsonb, 'Finish in the top 3 in 5 races')
on conflict (level, slot) do update set params = excluded.params, description = excluded.description;

-- progress on the tasks of the level a player is on
create table if not exists public.player_tasks (
  user_id    uuid not null references auth.users (id) on delete cascade,
  level      integer not null,
  slot       integer not null,
  progress   integer not null default 0,
  done_at    timestamptz,
  primary key (user_id, level, slot),
  foreign key (level, slot) references public.level_tasks (level, slot) on delete cascade
);
alter table public.player_tasks enable row level security;
drop policy if exists "Players read their own tasks" on public.player_tasks;
create policy "Players read their own tasks" on public.player_tasks for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.player_tasks from anon;
revoke insert, update, delete on public.player_tasks from authenticated;
grant select on public.player_tasks to authenticated;

-- does a verified race satisfy a task's conditions?
create or replace function public.task_matches(p jsonb, r public.races, p_position integer, p_penalties integer, p_fastest boolean)
returns boolean language sql immutable set search_path = '' as $$
  select (p ->> 'track' is null or r.track_id = p ->> 'track')
     and (p ->> 'pos' is null or p_position <= (p ->> 'pos')::integer)
     and (p ->> 'laps' is null or r.laps >= (p ->> 'laps')::integer)
     and (p ->> 'cars' is null or r.cars >= (p ->> 'cars')::integer)
     and (p ->> 'diff' is null or (p ->> 'diff' = 'pro' and r.difficulty in ('pro', 'champion')) or (p ->> 'diff' = 'champion' and r.difficulty = 'champion'))
     and (coalesce((p ->> 'wet')::boolean, false) = false or r.weather <> 'dry')
     and (coalesce((p ->> 'clean')::boolean, false) = false or p_penalties = 0)
     and (coalesce((p ->> 'fastest')::boolean, false) = false or coalesce(p_fastest, false))
$$;

-- ---------- finish_race: same checks and rewards as before; the level now comes from tasks ----------
create or replace function public.finish_race(p_race uuid, p_position integer, p_race_time real, p_best_lap real, p_fastest_lap boolean, p_penalties integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  r public.races%rowtype;
  t public.tracks%rowtype;
  prof public.profiles%rowtype;
  lv public.levels%rowtype;
  tk record;
  ach record;
  v_elapsed real;
  v_mult real;
  v_field real;
  v_chal_mult real;
  v_pos_xp integer;
  v_pos_gold integer;
  v_parts jsonb := '[]'::jsonb;
  v_gold_parts jsonb := '[]'::jsonb;
  v_xp integer;
  v_race_gold integer;
  v_balance integer;
  v_level_gold integer := 0;
  v_ach_gold integer := 0;
  v_rewards jsonb := '[]'::jsonb;
  v_tasks jsonb := '[]'::jsonb;
  v_done integer := 0;
  v_total integer := 0;
  v_progress integer;
  v_count integer;
  v_was_done boolean;
  v_lvl_after integer;
  v_chal_after integer;
  v_races integer;
  v_wins integer;
  v_podiums integer;
  v_track_count integer;
  v_tracks_done integer;
  v_win boolean;
  v_earned text[] := array[]::text[];
  v_new_ach jsonb := '[]'::jsonb;
begin
  if uid is null then raise exception 'Sign in to earn XP' using errcode = '28000'; end if;
  select * into r from public.races where id = p_race and user_id = uid for update;
  if not found then raise exception 'Race not found'; end if;
  if r.finished_at is not null then raise exception 'This race result was already saved'; end if;
  select * into t from public.tracks where id = r.track_id;
  v_elapsed := extract(epoch from (now() - r.started_at));

  if p_position is null or p_position < 1 or p_position > r.cars then raise exception 'Invalid finishing position'; end if;
  if p_penalties is null or p_penalties < 0 or p_penalties > 600 then raise exception 'Invalid penalties'; end if;
  if p_race_time is null or p_race_time < r.laps * t.min_lap_s or p_race_time - p_penalties > v_elapsed + 10 then
    raise exception 'Race time could not be verified';
  end if;
  if v_elapsed < r.laps * t.min_lap_s then raise exception 'Race finished too quickly to be verified'; end if;
  if p_best_lap is null or p_best_lap < t.min_lap_s or p_best_lap > p_race_time then raise exception 'Lap time could not be verified'; end if;
  v_win := p_position = 1;

  v_mult      := case r.difficulty when 'rookie' then 0.8 when 'champion' then 1.25 else 1.0 end;
  v_field     := 0.4 + 0.6 * (r.cars - 1) / 13.0;
  v_chal_mult := 1 + 0.05 * r.challenge;

  -- XP (still earned, shown on the leaderboard)
  v_parts := v_parts || jsonb_build_object('label', 'Race completed', 'xp', round((40 + 20 * r.laps) * v_mult * v_chal_mult));
  v_pos_xp := case when p_position = 1 then 150 when p_position = 2 then 100 when p_position = 3 then 70
                   when p_position <= greatest(3, r.cars / 2) then 30 else 0 end;
  if v_pos_xp > 0 then
    v_parts := v_parts || jsonb_build_object('label', case p_position when 1 then 'Victory' when 2 then 'Second place' when 3 then 'Third place' else 'Top half finish' end,
      'xp', round(v_pos_xp * v_field * v_mult * v_chal_mult));
  end if;
  if coalesce(p_fastest_lap, false) then v_parts := v_parts || jsonb_build_object('label', 'Objective: fastest lap', 'xp', round(30 * v_mult * v_chal_mult)); end if;
  if p_penalties = 0 then v_parts := v_parts || jsonb_build_object('label', 'Objective: clean race', 'xp', round(20 * v_mult * v_chal_mult)); end if;
  select coalesce(sum((e ->> 'xp')::integer), 0) into v_xp from jsonb_array_elements(v_parts) e;

  -- gold for the race
  v_pos_gold := case when p_position = 1 then 60 when p_position = 2 then 40 when p_position = 3 then 25
                     when p_position <= greatest(3, r.cars / 2) then 10 else 0 end;
  v_race_gold := round((20 + 5 * r.laps + v_pos_gold * v_field) * v_mult * v_chal_mult);

  select * into prof from public.profiles where id = uid for update;
  v_balance := prof.gold + v_race_gold;
  insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
  values (uid, v_race_gold, v_balance, 'race_reward', 'race:' || r.id, 'P' || p_position || ' · ' || t.name || ' · ' || r.laps || ' laps');
  v_gold_parts := v_gold_parts || jsonb_build_object('label', case when v_win then 'Race win' when p_position <= 3 then 'Podium finish' else 'Race finished' end, 'gold', v_race_gold);

  -- tasks of the current level
  v_lvl_after := prof.level;
  for tk in select lt.* from public.level_tasks lt where lt.level = prof.level order by lt.slot loop
    v_total := v_total + 1;
    v_count := coalesce((tk.params ->> 'count')::integer, 1);
    insert into public.player_tasks (user_id, level, slot) values (uid, tk.level, tk.slot) on conflict do nothing;
    select progress, done_at is not null into v_progress, v_was_done from public.player_tasks where user_id = uid and level = tk.level and slot = tk.slot for update;
    if not v_was_done and public.task_matches(tk.params, r, p_position, p_penalties, p_fastest_lap) then
      v_progress := least(v_count, v_progress + 1);
      update public.player_tasks set progress = v_progress, done_at = case when v_progress >= v_count then now() else null end
      where user_id = uid and level = tk.level and slot = tk.slot;
      v_tasks := v_tasks || jsonb_build_object('slot', tk.slot, 'description', tk.description, 'progress', v_progress, 'count', v_count, 'done', v_progress >= v_count, 'advanced', true);
    else
      v_tasks := v_tasks || jsonb_build_object('slot', tk.slot, 'description', tk.description, 'progress', v_progress, 'count', v_count, 'done', v_was_done, 'advanced', false);
    end if;
    if v_was_done or v_progress >= v_count then v_done := v_done + 1; end if;
  end loop;

  -- all tasks done: up one level, with that level's rewards
  if v_total > 0 and v_done = v_total and prof.level < 50 then
    v_lvl_after := prof.level + 1;
    select * into lv from public.levels where level = v_lvl_after;
    insert into public.level_history (user_id, level, xp_total) values (uid, lv.level, prof.xp + v_xp) on conflict do nothing;
    if lv.reward_gold > 0 then
      v_level_gold := lv.reward_gold;
      v_balance := v_balance + lv.reward_gold;
      insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
      values (uid, lv.reward_gold, v_balance, 'level_reward', 'level:' || lv.level, 'Reached level ' || lv.level);
      v_gold_parts := v_gold_parts || jsonb_build_object('label', 'Level reward', 'gold', v_level_gold);
    end if;
    v_rewards := v_rewards || jsonb_build_object('level', lv.level, 'gold', lv.reward_gold, 'title', lv.reward_title,
      'unlock_kind', lv.unlock_kind, 'unlock_id', lv.unlock_id, 'unlock_label', lv.unlock_label);
  end if;

  -- challenge tier (Quick Race only)
  v_chal_after := prof.challenge;
  if r.mode = 'quick' then
    if v_win then v_chal_after := least(20, prof.challenge + 1);
    elsif p_position > greatest(3, r.cars / 2) then v_chal_after := greatest(0, prof.challenge - 1);
    end if;
  end if;

  update public.races set finished_at = now(), position = p_position, race_time = p_race_time, best_lap = p_best_lap,
    fastest_lap = coalesce(p_fastest_lap, false), penalties = p_penalties, xp_awarded = v_xp, breakdown = v_parts
  where id = p_race;

  -- achievements
  select count(*), count(*) filter (where position = 1), count(*) filter (where position <= 3), count(distinct track_id)
    into v_races, v_wins, v_podiums, v_tracks_done
    from public.races where user_id = uid and finished_at is not null;
  select count(*) into v_track_count from public.tracks;
  if v_races >= 1 then v_earned := v_earned || 'first_finish'::text; end if;
  if v_podiums >= 1 then v_earned := v_earned || 'first_podium'::text; end if;
  if v_wins >= 1 then v_earned := v_earned || 'first_win'::text; end if;
  if coalesce(p_fastest_lap, false) then v_earned := v_earned || 'fastest_lap'::text; end if;
  if v_win and p_penalties = 0 then v_earned := v_earned || 'clean_win'::text; end if;
  if v_races >= 10 then v_earned := v_earned || 'races_10'::text; end if;
  if v_wins >= 5 then v_earned := v_earned || 'wins_5'::text; end if;
  if v_win and r.laps >= 8 then v_earned := v_earned || 'long_win'::text; end if;
  if v_win and r.cars >= 14 then v_earned := v_earned || 'full_grid_win'::text; end if;
  if v_win and r.weather <> 'dry' then v_earned := v_earned || 'wet_win'::text; end if;
  if v_win and r.difficulty = 'champion' then v_earned := v_earned || 'champion_win'::text; end if;
  if v_chal_after >= 5 then v_earned := v_earned || 'challenge_5'::text; end if;
  if v_lvl_after >= 10 then v_earned := v_earned || 'level_10'::text; end if;
  if v_races >= 50 then v_earned := v_earned || 'races_50'::text; end if;
  if v_chal_after >= 10 then v_earned := v_earned || 'challenge_10'::text; end if;
  if v_lvl_after >= 25 then v_earned := v_earned || 'level_25'::text; end if;
  if v_wins >= 25 then v_earned := v_earned || 'wins_25'::text; end if;
  if v_tracks_done >= v_track_count then v_earned := v_earned || 'all_tracks'::text; end if;
  if v_races >= 200 then v_earned := v_earned || 'races_200'::text; end if;
  if v_lvl_after >= 50 then v_earned := v_earned || 'level_50'::text; end if;
  for ach in select a.* from public.achievements a
             where a.id = any(v_earned)
               and not exists (select 1 from public.player_achievements pa where pa.user_id = uid and pa.achievement_id = a.id)
             order by a.sort loop
    insert into public.player_achievements (user_id, achievement_id) values (uid, ach.id);
    if ach.reward_gold > 0 then
      v_ach_gold := v_ach_gold + ach.reward_gold;
      v_balance := v_balance + ach.reward_gold;
      insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
      values (uid, ach.reward_gold, v_balance, 'achievement', 'achievement:' || ach.id, 'Achievement: ' || ach.name);
    end if;
    v_new_ach := v_new_ach || jsonb_build_object('id', ach.id, 'name', ach.name, 'description', ach.description, 'gold', ach.reward_gold);
  end loop;
  if v_ach_gold > 0 then v_gold_parts := v_gold_parts || jsonb_build_object('label', 'Achievements', 'gold', v_ach_gold); end if;

  update public.profiles set xp = prof.xp + v_xp, level = v_lvl_after, gold = v_balance, challenge = v_chal_after where id = uid;
  update public.races set gold_awarded = v_balance - prof.gold, achievements = v_new_ach where id = p_race;

  return jsonb_build_object('xp', v_xp, 'breakdown', v_parts, 'xp_total', prof.xp + v_xp, 'level_before', prof.level, 'level_after', v_lvl_after,
    'gold', v_balance - prof.gold, 'gold_breakdown', v_gold_parts, 'gold_total', v_balance, 'rewards', v_rewards,
    'tasks', v_tasks, 'tasks_done', v_done, 'tasks_total', v_total,
    'challenge_before', prof.challenge, 'challenge_after', v_chal_after, 'challenge_mult', v_chal_mult, 'achievements', v_new_ach);
end $$;

revoke execute on function public.finish_race(uuid, integer, real, real, boolean, integer) from public, anon;
grant execute on function public.finish_race(uuid, integer, real, real, boolean, integer) to authenticated;
revoke execute on function public.task_matches(jsonb, public.races, integer, integer, boolean) from public, anon, authenticated;

-- ---------- private rooms: a log of each room race (written by the race server only) ----------
create table if not exists public.room_races (
  id              uuid primary key,
  code            text not null,
  host_user       uuid references auth.users (id) on delete set null,
  track_id        text not null references public.tracks (id),
  laps            integer not null,
  players         integer not null,
  ai_cars         integer not null default 0,
  grid            jsonb not null,
  classification  jsonb not null,
  started_at      timestamptz not null,
  finished_at     timestamptz not null default now()
);
alter table public.room_races enable row level security;
revoke all on public.room_races from anon, authenticated;
