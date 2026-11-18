-- Lights Out GP · Stage 2 fix: finish_race used variable names that clash with the profiles columns ("gold" is ambiguous).
-- Run once in Supabase: SQL Editor → New query → paste → Run.

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

revoke execute on function public.finish_race(uuid, integer, real, real, boolean, integer) from public, anon;
grant execute on function public.finish_race(uuid, integer, real, real, boolean, integer) to authenticated;
