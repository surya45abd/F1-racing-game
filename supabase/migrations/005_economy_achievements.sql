-- Lights Out GP · Stage 4: gold race rewards, achievements, challenge tiers (difficulty progression)
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.

-- ---------- challenge tier: Quick Race wins raise it, poor finishes lower it (0-20) ----------
alter table public.profiles add column if not exists challenge integer not null default 0 check (challenge between 0 and 20);
alter table public.races    add column if not exists challenge integer not null default 0;
alter table public.races    add column if not exists achievements jsonb;

-- ---------- achievements (editable: names, descriptions and gold rewards) ----------
create table if not exists public.achievements (
  id           text primary key,
  name         text not null,
  description  text not null,
  reward_gold  integer not null default 0 check (reward_gold >= 0),
  sort         integer not null default 0
);
alter table public.achievements enable row level security;
drop policy if exists "Anyone can read achievements" on public.achievements;
create policy "Anyone can read achievements" on public.achievements for select to anon, authenticated using (true);
revoke insert, update, delete on public.achievements from anon, authenticated;
grant select on public.achievements to anon, authenticated;

insert into public.achievements (id, name, description, reward_gold, sort) values
  ('first_finish',  'Lights Out',      'Finish your first race',                         50,   1),
  ('first_podium',  'Podium Debut',    'Finish in the top three',                        100,  2),
  ('first_win',     'First Victory',   'Win a race',                                     200,  3),
  ('fastest_lap',   'Purple Sector',   'Set the fastest lap of a race',                  75,   4),
  ('clean_win',     'Clean Sweep',     'Win a race without a single penalty',            250,  5),
  ('races_10',      'Regular',         'Finish 10 races',                                150,  6),
  ('wins_5',        'Serial Winner',   'Win 5 races',                                    300,  7),
  ('long_win',      'Endurance',       'Win an 8-lap race',                              300,  8),
  ('full_grid_win', 'Giant Killer',    'Win against a full 14-car grid',                 400,  9),
  ('wet_win',       'Rain Master',     'Win a race in changeable or wet weather',        400,  10),
  ('champion_win',  'Champion Pace',   'Win on Champion rival pace',                     400,  11),
  ('challenge_5',   'Rising Threat',   'Reach challenge tier 5',                         300,  12),
  ('level_10',      'Contender',       'Reach level 10',                                 300,  13),
  ('races_50',      'Seasoned',        'Finish 50 races',                                500,  14),
  ('challenge_10',  'Top Gun',         'Reach challenge tier 10',                        800,  15),
  ('level_25',      'Veteran',         'Reach level 25',                                 800,  16),
  ('wins_25',       'Dominator',       'Win 25 races',                                   1000, 17),
  ('all_tracks',    'World Tour',      'Finish a race on every circuit',                 1000, 18),
  ('races_200',     'Iron Driver',     'Finish 200 races',                               1500, 19),
  ('level_50',      'Grid Champion',   'Reach level 50',                                 2000, 20)
on conflict (id) do update set name = excluded.name, description = excluded.description, reward_gold = excluded.reward_gold, sort = excluded.sort;

create table if not exists public.player_achievements (
  user_id         uuid not null references auth.users (id) on delete cascade,
  achievement_id  text not null references public.achievements (id) on delete cascade,
  unlocked_at     timestamptz not null default now(),
  primary key (user_id, achievement_id)
);
alter table public.player_achievements enable row level security;
drop policy if exists "Players read their own achievements" on public.player_achievements;
create policy "Players read their own achievements" on public.player_achievements for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.player_achievements from anon;
revoke insert, update, delete on public.player_achievements from authenticated;
grant select on public.player_achievements to authenticated;

-- ---------- start_race: also records the challenge tier the race is run at ----------
create or replace function public.start_race(p_mode text, p_track text, p_laps integer, p_cars integer, p_difficulty text, p_weather text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_level integer;
  v_challenge integer;
  v_unlock integer;
  rid uuid;
begin
  if uid is null then raise exception 'Sign in to earn XP' using errcode = '28000'; end if;
  if p_mode not in ('quick', 'career') then raise exception 'Unknown race mode'; end if;
  select unlock_level into v_unlock from public.tracks where id = p_track;
  if not found then raise exception 'Unknown track'; end if;
  if p_laps not in (3, 5, 8) then raise exception 'Unsupported race distance'; end if;
  if p_cars not between 2 and 14 then raise exception 'Unsupported number of cars'; end if;
  if p_difficulty not in ('rookie', 'pro', 'champion') then raise exception 'Unknown difficulty'; end if;
  if p_weather not in ('dry', 'changeable', 'wet') then raise exception 'Unknown weather'; end if;
  select level, challenge into v_level, v_challenge from public.profiles where id = uid;
  if p_mode = 'quick' then
    if v_unlock > v_level then raise exception 'This track unlocks at level %', v_unlock; end if;
    if p_weather <> 'dry' and v_level < 10 then raise exception 'Weather choice unlocks at level 10'; end if;
  end if;
  delete from public.races where user_id = uid and finished_at is null;
  insert into public.races (user_id, mode, track_id, laps, cars, difficulty, weather, challenge)
  values (uid, p_mode, p_track, p_laps, p_cars, p_difficulty, p_weather, case when p_mode = 'quick' then v_challenge else 0 end)
  returning id into rid;
  return rid;
end $$;

-- ---------- finish_race: checks the result; awards XP, gold, level rewards and achievements ----------
create or replace function public.finish_race(p_race uuid, p_position integer, p_race_time real, p_best_lap real, p_fastest_lap boolean, p_penalties integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  r public.races%rowtype;
  t public.tracks%rowtype;
  prof public.profiles%rowtype;
  lv record;
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
  v_new_xp integer;
  v_lvl_after integer;
  v_balance integer;
  v_level_gold integer := 0;
  v_ach_gold integer := 0;
  v_rewards jsonb := '[]'::jsonb;
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

  -- plausibility checks against the server clock and the track's fastest possible lap
  if p_position is null or p_position < 1 or p_position > r.cars then raise exception 'Invalid finishing position'; end if;
  if p_penalties is null or p_penalties < 0 or p_penalties > 600 then raise exception 'Invalid penalties'; end if;
  if p_race_time is null or p_race_time < r.laps * t.min_lap_s or p_race_time - p_penalties > v_elapsed + 10 then
    raise exception 'Race time could not be verified';
  end if;
  if v_elapsed < r.laps * t.min_lap_s then raise exception 'Race finished too quickly to be verified'; end if;
  if p_best_lap is null or p_best_lap < t.min_lap_s or p_best_lap > p_race_time then raise exception 'Lap time could not be verified'; end if;
  v_win := p_position = 1;

  -- multipliers: rival pace, field size, challenge tier (+5% per tier)
  v_mult      := case r.difficulty when 'rookie' then 0.8 when 'champion' then 1.25 else 1.0 end;
  v_field     := 0.4 + 0.6 * (r.cars - 1) / 13.0;
  v_chal_mult := 1 + 0.05 * r.challenge;

  -- XP: finishing + result + objectives
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

  -- gold for the race: taking part + result
  v_pos_gold := case when p_position = 1 then 60 when p_position = 2 then 40 when p_position = 3 then 25
                     when p_position <= greatest(3, r.cars / 2) then 10 else 0 end;
  v_race_gold := round((20 + 5 * r.laps + v_pos_gold * v_field) * v_mult * v_chal_mult);

  select * into prof from public.profiles where id = uid for update;
  v_balance := prof.gold;

  v_balance := v_balance + v_race_gold;
  insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
  values (uid, v_race_gold, v_balance, 'race_reward', 'race:' || r.id, 'P' || p_position || ' · ' || t.name || ' · ' || r.laps || ' laps');
  v_gold_parts := v_gold_parts || jsonb_build_object('label', case when v_win then 'Race win' when p_position <= 3 then 'Podium finish' else 'Race finished' end, 'gold', v_race_gold);

  -- levels
  v_new_xp := prof.xp + v_xp;
  v_lvl_after := public.level_for_xp(v_new_xp);
  for lv in select * from public.levels where level > prof.level and level <= v_lvl_after order by level loop
    insert into public.level_history (user_id, level, xp_total) values (uid, lv.level, v_new_xp) on conflict do nothing;
    if lv.reward_gold > 0 then
      v_level_gold := v_level_gold + lv.reward_gold;
      v_balance := v_balance + lv.reward_gold;
      insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
      values (uid, lv.reward_gold, v_balance, 'level_reward', 'level:' || lv.level, 'Reached level ' || lv.level);
    end if;
    v_rewards := v_rewards || jsonb_build_object('level', lv.level, 'gold', lv.reward_gold, 'title', lv.reward_title,
      'unlock_kind', lv.unlock_kind, 'unlock_id', lv.unlock_id, 'unlock_label', lv.unlock_label);
  end loop;
  if v_level_gold > 0 then v_gold_parts := v_gold_parts || jsonb_build_object('label', 'Level rewards', 'gold', v_level_gold); end if;

  -- challenge tier (Quick Race only): a win raises it, a bottom-half finish lowers it
  v_chal_after := prof.challenge;
  if r.mode = 'quick' then
    if v_win then v_chal_after := least(20, prof.challenge + 1);
    elsif p_position > greatest(3, r.cars / 2) then v_chal_after := greatest(0, prof.challenge - 1);
    end if;
  end if;

  update public.races set finished_at = now(), position = p_position, race_time = p_race_time, best_lap = p_best_lap,
    fastest_lap = coalesce(p_fastest_lap, false), penalties = p_penalties, xp_awarded = v_xp, breakdown = v_parts
  where id = p_race;

  -- achievements, from the player's verified race history
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

  update public.profiles set xp = v_new_xp, level = v_lvl_after, gold = v_balance, challenge = v_chal_after where id = uid;
  update public.races set gold_awarded = v_balance - prof.gold, achievements = v_new_ach where id = p_race;

  return jsonb_build_object('xp', v_xp, 'breakdown', v_parts, 'xp_total', v_new_xp, 'level_before', prof.level, 'level_after', v_lvl_after,
    'gold', v_balance - prof.gold, 'gold_breakdown', v_gold_parts, 'gold_total', v_balance, 'rewards', v_rewards,
    'challenge_before', prof.challenge, 'challenge_after', v_chal_after, 'challenge_mult', v_chal_mult, 'achievements', v_new_ach);
end $$;

revoke execute on function public.start_race(text, text, integer, integer, text, text) from public, anon;
revoke execute on function public.finish_race(uuid, integer, real, real, boolean, integer) from public, anon;
grant execute on function public.start_race(text, text, integer, integer, text, text) to authenticated;
grant execute on function public.finish_race(uuid, integer, real, real, boolean, integer) to authenticated;
