-- Lights Out GP · Stage 3: 8 circuits, track unlocks by level, Quick Race limits
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.
-- Unlock levels live in public.tracks.unlock_level and can be changed from the Table Editor at any time.

-- ---------- circuits (min_lap_s = faster than any car can lap; used to reject impossible results) ----------
alter table public.tracks add column if not exists difficulty integer not null default 2 check (difficulty between 1 and 5);

insert into public.tracks (id, name, min_lap_s, unlock_level, sort, difficulty) values
  ('vespera',  'Circuito Vespera',   53, 1,  1, 2),
  ('porto',    'Porto Lume',         48, 4,  2, 3),
  ('highland', 'Highland Ring',      42, 7,  3, 2),
  ('sabbia',   'Sabbia Mirage',      45, 13, 4, 3),
  ('riva',     'Monte Riva',         47, 18, 5, 5),
  ('velocita', 'Autodromo Velocità', 46, 24, 6, 2),
  ('bosco',    'Bosco Verde Ring',   52, 31, 7, 4),
  ('neon',     'Neon Bay',           57, 38, 8, 4)
on conflict (id) do update set name = excluded.name, min_lap_s = excluded.min_lap_s, unlock_level = excluded.unlock_level,
  sort = excluded.sort, difficulty = excluded.difficulty;

-- ---------- matching rewards on the level table ----------
update public.levels set unlock_kind = 'feature', unlock_id = 'track_select', unlock_label = 'Race conditions: weather, tyres and track stats' where level = 10;
update public.levels set unlock_kind = 'track', unlock_id = 'riva',     unlock_label = 'Monte Riva'         where level = 18;
update public.levels set unlock_kind = 'track', unlock_id = 'velocita', unlock_label = 'Autodromo Velocità' where level = 24;
update public.levels set unlock_kind = 'track', unlock_id = 'bosco',    unlock_label = 'Bosco Verde Ring'   where level = 31;
update public.levels set unlock_kind = 'track', unlock_id = 'neon',     unlock_label = 'Neon Bay'           where level = 38;

-- ---------- start_race: Quick Race must respect unlocks ----------
create or replace function public.start_race(p_mode text, p_track text, p_laps integer, p_cars integer, p_difficulty text, p_weather text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_level integer;
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
  select level into v_level from public.profiles where id = uid;
  if p_mode = 'quick' then
    if v_unlock > v_level then raise exception 'This track unlocks at level %', v_unlock; end if;
    if p_weather <> 'dry' and v_level < 10 then raise exception 'Weather choice unlocks at level 10'; end if;
  end if;
  -- one race at a time: starting a new race abandons the previous unfinished one
  delete from public.races where user_id = uid and finished_at is null;
  insert into public.races (user_id, mode, track_id, laps, cars, difficulty, weather)
  values (uid, p_mode, p_track, p_laps, p_cars, p_difficulty, p_weather)
  returning id into rid;
  return rid;
end $$;

revoke execute on function public.start_race(text, text, integer, integer, text, text) from public, anon;
grant execute on function public.start_race(text, text, integer, integer, text, text) to authenticated;
