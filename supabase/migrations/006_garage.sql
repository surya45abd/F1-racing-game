-- Lights Out GP · Stage 5: cars, teams, upgrades (garage)
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.
-- Prices, unlock levels and car stats live in tables below and can be edited in the Table Editor.

-- ---------- catalogue: teams (fictional), cars, upgrade kinds ----------
create table if not exists public.teams (
  id            text primary key,
  name          text not null,
  color         text not null,
  alt           text not null,
  unlock_level  integer not null default 1 references public.levels (level),
  sort          integer not null default 0
);
create table if not exists public.cars (
  id            text primary key,
  name          text not null,
  description   text not null,
  price_gold    integer not null default 0 check (price_gold >= 0),
  unlock_level  integer not null default 1 references public.levels (level),
  -- multipliers on the base car (1.0 = LX-1)
  top_speed     real not null default 1,
  accel         real not null default 1,
  braking       real not null default 1,
  handling      real not null default 1,
  downforce     real not null default 1,
  tyre_wear     real not null default 1,   -- lower is better
  sort          integer not null default 0
);
create table if not exists public.upgrade_kinds (
  id          text primary key,
  name        text not null,
  effect      text not null,
  base_cost   integer not null check (base_cost > 0),
  sort        integer not null default 0
);
-- the player level needed for each upgrade level (1-5)
create table if not exists public.upgrade_tiers (
  tier          integer primary key check (tier between 1 and 5),
  unlock_level  integer not null references public.levels (level)
);

do $$ begin
  -- read-only for players
  execute 'alter table public.teams enable row level security';
  execute 'alter table public.cars enable row level security';
  execute 'alter table public.upgrade_kinds enable row level security';
  execute 'alter table public.upgrade_tiers enable row level security';
end $$;
drop policy if exists "Anyone can read teams" on public.teams;
create policy "Anyone can read teams" on public.teams for select to anon, authenticated using (true);
drop policy if exists "Anyone can read cars" on public.cars;
create policy "Anyone can read cars" on public.cars for select to anon, authenticated using (true);
drop policy if exists "Anyone can read upgrade kinds" on public.upgrade_kinds;
create policy "Anyone can read upgrade kinds" on public.upgrade_kinds for select to anon, authenticated using (true);
drop policy if exists "Anyone can read upgrade tiers" on public.upgrade_tiers;
create policy "Anyone can read upgrade tiers" on public.upgrade_tiers for select to anon, authenticated using (true);
revoke insert, update, delete on public.teams, public.cars, public.upgrade_kinds, public.upgrade_tiers from anon, authenticated;
grant select on public.teams, public.cars, public.upgrade_kinds, public.upgrade_tiers to anon, authenticated;

insert into public.teams (id, name, color, alt, unlock_level, sort) values
  ('tidewater', 'Tidewater',  '#e9ebef', '#0b6e4f', 1,  1),
  ('aurora',    'Aurora',     '#ff3da6', '#2a2e36', 3,  2),
  ('halcyon',   'Halcyon',    '#7a3cff', '#c9ced6', 6,  3),
  ('meridian',  'Meridian',   '#00a88a', '#f2f2f2', 9,  4),
  ('vortex',    'Vortex',     '#ff7a00', '#1b2a4a', 15, 5),
  ('corsa',     'Corsa Nera', '#b3122a', '#121418', 21, 6),
  ('kestrel',   'Kestrel',    '#2f6bff', '#ffd400', 27, 7)
on conflict (id) do update set name = excluded.name, color = excluded.color, alt = excluded.alt, unlock_level = excluded.unlock_level, sort = excluded.sort;

insert into public.cars (id, name, description, price_gold, unlock_level, top_speed, accel, braking, handling, downforce, tyre_wear, sort) values
  ('lx1', 'LX-1 Rookie',    'Balanced starter car. Forgiving and easy to drive.', 0,    1,  1.000, 1.00, 1.00, 1.00, 1.00, 1.00, 1),
  ('lx2', 'LX-2 Sprint',    'Light and punchy: quicker off the line and out of slow corners.', 800,  5,  1.010, 1.05, 1.00, 1.02, 1.00, 1.00, 2),
  ('lx3', 'LX-3 Apex',      'Sharp front end and strong brakes for twisty circuits.', 2000, 12, 1.005, 1.02, 1.05, 1.06, 1.03, 0.97, 3),
  ('lx4', 'LX-4 Velocity',  'Low-drag body built for long straights.', 4000, 20, 1.035, 1.03, 1.02, 1.00, 0.99, 1.00, 4),
  ('lx5', 'LX-5 Prototype', 'The complete package: fast everywhere and kind to its tyres.', 8000, 30, 1.040, 1.05, 1.06, 1.05, 1.04, 0.90, 5)
on conflict (id) do update set name = excluded.name, description = excluded.description, price_gold = excluded.price_gold, unlock_level = excluded.unlock_level,
  top_speed = excluded.top_speed, accel = excluded.accel, braking = excluded.braking, handling = excluded.handling, downforce = excluded.downforce, tyre_wear = excluded.tyre_wear, sort = excluded.sort;

insert into public.upgrade_kinds (id, name, effect, base_cost, sort) values
  ('engine',       'Engine',            '+2% acceleration and +0.8% top speed per level', 150, 1),
  ('acceleration', 'Acceleration',      '+4% acceleration per level',                     120, 2),
  ('top_speed',    'Top speed',         '+1.5% top speed per level',                      140, 3),
  ('braking',      'Braking',           '+5% braking power per level',                    100, 4),
  ('handling',     'Handling',          '+3% steering response per level',               120, 5),
  ('tyres',        'Tyre performance',  '-8% tyre wear per level',                        100, 6),
  ('aero',         'Aerodynamics',      '+2% cornering grip per level',                   130, 7)
on conflict (id) do update set name = excluded.name, effect = excluded.effect, base_cost = excluded.base_cost, sort = excluded.sort;

insert into public.upgrade_tiers (tier, unlock_level) values (1, 2), (2, 8), (3, 16), (4, 23), (5, 33)
on conflict (tier) do update set unlock_level = excluded.unlock_level;

-- show the new unlocks on the progression screen
update public.levels set unlock_kind = 'upgrade', unlock_id = 'tier1', unlock_label = 'Car upgrades (level 1)' where level = 2;
update public.levels set unlock_kind = 'team',    unlock_id = 'aurora',   unlock_label = 'Team Aurora' where level = 3;
update public.levels set unlock_kind = 'car',     unlock_id = 'lx2',      unlock_label = 'LX-2 Sprint' where level = 5;
update public.levels set unlock_kind = 'team',    unlock_id = 'halcyon',  unlock_label = 'Team Halcyon' where level = 6;
update public.levels set unlock_kind = 'upgrade', unlock_id = 'tier2', unlock_label = 'Car upgrades (level 2)' where level = 8;
update public.levels set unlock_kind = 'team',    unlock_id = 'meridian', unlock_label = 'Team Meridian' where level = 9;
update public.levels set unlock_kind = 'car',     unlock_id = 'lx3',      unlock_label = 'LX-3 Apex' where level = 12;
update public.levels set unlock_kind = 'team',    unlock_id = 'vortex',   unlock_label = 'Team Vortex' where level = 15;
update public.levels set unlock_kind = 'upgrade', unlock_id = 'tier3', unlock_label = 'Car upgrades (level 3)' where level = 16;
update public.levels set unlock_kind = 'car',     unlock_id = 'lx4',      unlock_label = 'LX-4 Velocity' where level = 20;
update public.levels set unlock_kind = 'team',    unlock_id = 'corsa',    unlock_label = 'Team Corsa Nera' where level = 21;
update public.levels set unlock_kind = 'upgrade', unlock_id = 'tier4', unlock_label = 'Car upgrades (level 4)' where level = 23;
update public.levels set unlock_kind = 'team',    unlock_id = 'kestrel',  unlock_label = 'Team Kestrel' where level = 27;
update public.levels set unlock_kind = 'car',     unlock_id = 'lx5',      unlock_label = 'LX-5 Prototype' where level = 30;
update public.levels set unlock_kind = 'upgrade', unlock_id = 'tier5', unlock_label = 'Car upgrades (level 5)' where level = 33;

-- ---------- what each player owns ----------
create table if not exists public.player_cars (
  user_id       uuid not null references auth.users (id) on delete cascade,
  car_id        text not null references public.cars (id),
  engine        integer not null default 0 check (engine between 0 and 5),
  acceleration  integer not null default 0 check (acceleration between 0 and 5),
  top_speed     integer not null default 0 check (top_speed between 0 and 5),
  braking       integer not null default 0 check (braking between 0 and 5),
  handling      integer not null default 0 check (handling between 0 and 5),
  tyres         integer not null default 0 check (tyres between 0 and 5),
  aero          integer not null default 0 check (aero between 0 and 5),
  bought_at     timestamptz not null default now(),
  primary key (user_id, car_id)
);
alter table public.player_cars enable row level security;
drop policy if exists "Players read their own cars" on public.player_cars;
create policy "Players read their own cars" on public.player_cars for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.player_cars from anon;
revoke insert, update, delete on public.player_cars from authenticated;
grant select on public.player_cars to authenticated;

alter table public.profiles add column if not exists selected_car  text not null default 'lx1' references public.cars (id);
alter table public.profiles add column if not exists selected_team text not null default 'tidewater' references public.teams (id);
alter table public.races    add column if not exists loadout jsonb;

-- everyone owns the starter car
insert into public.player_cars (user_id, car_id) select id, 'lx1' from public.profiles on conflict do nothing;
create or replace function public.handle_new_profile_car()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.player_cars (user_id, car_id) values (new.id, 'lx1') on conflict do nothing;
  return new;
end $$;
revoke execute on function public.handle_new_profile_car() from public, anon, authenticated;
drop trigger if exists on_profile_created_car on public.profiles;
create trigger on_profile_created_car after insert on public.profiles for each row execute function public.handle_new_profile_car();

-- upgrades and better cars make laps faster: lower the "impossible lap" limits so honest fast laps still verify
update public.tracks set min_lap_s = v.m from (values ('vespera', 48), ('porto', 43), ('highland', 38), ('sabbia', 41),
  ('riva', 42), ('velocita', 41), ('bosco', 47), ('neon', 51)) as v(id, m) where tracks.id = v.id;

-- ---------- garage functions ----------
create or replace function public.upgrade_cost(p_kind text, p_next integer)
returns integer language sql stable set search_path = '' as $$
  select (round(k.base_cost * power(p_next, 1.6) / 10.0) * 10)::integer from public.upgrade_kinds k where k.id = p_kind
$$;

-- everything the garage screen needs in one call
create or replace function public.get_garage()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  prof public.profiles%rowtype;
begin
  if uid is null then raise exception 'Sign in to use the garage' using errcode = '28000'; end if;
  insert into public.player_cars (user_id, car_id) values (uid, 'lx1') on conflict do nothing;
  select * into prof from public.profiles where id = uid;
  return jsonb_build_object(
    'gold', prof.gold, 'level', prof.level, 'selected_car', prof.selected_car, 'selected_team', prof.selected_team,
    'cars', (select jsonb_agg(to_jsonb(c) order by c.sort) from public.cars c),
    'teams', (select jsonb_agg(to_jsonb(t) order by t.sort) from public.teams t),
    'kinds', (select jsonb_agg(to_jsonb(k) order by k.sort) from public.upgrade_kinds k),
    'tiers', (select jsonb_agg(to_jsonb(u) order by u.tier) from public.upgrade_tiers u),
    'owned', (select coalesce(jsonb_object_agg(pc.car_id, to_jsonb(pc) - 'user_id' - 'car_id'), '{}'::jsonb) from public.player_cars pc where pc.user_id = uid)
  );
end $$;

create or replace function public.buy_car(p_car text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  prof public.profiles%rowtype;
  c public.cars%rowtype;
begin
  if uid is null then raise exception 'Sign in to use the garage' using errcode = '28000'; end if;
  select * into c from public.cars where id = p_car;
  if not found then raise exception 'Unknown car'; end if;
  select * into prof from public.profiles where id = uid for update;
  if exists (select 1 from public.player_cars where user_id = uid and car_id = p_car) then raise exception 'You already own this car'; end if;
  if prof.level < c.unlock_level then raise exception '% unlocks at level %', c.name, c.unlock_level; end if;
  if prof.gold < c.price_gold then raise exception 'Not enough gold: % needs % gold', c.name, c.price_gold; end if;
  insert into public.player_cars (user_id, car_id) values (uid, p_car);
  update public.profiles set gold = prof.gold - c.price_gold, selected_car = p_car where id = uid;
  if c.price_gold > 0 then
    insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
    values (uid, -c.price_gold, prof.gold - c.price_gold, 'purchase', 'car:' || p_car, 'Bought ' || c.name);
  end if;
  return public.get_garage();
end $$;

create or replace function public.buy_upgrade(p_car text, p_kind text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  prof public.profiles%rowtype;
  v_cur integer;
  v_next integer;
  v_cost integer;
  v_need integer;
  v_kind_name text;
  v_car_name text;
begin
  if uid is null then raise exception 'Sign in to use the garage' using errcode = '28000'; end if;
  select name into v_kind_name from public.upgrade_kinds where id = p_kind;
  if not found then raise exception 'Unknown upgrade'; end if;
  select name into v_car_name from public.cars where id = p_car;
  select * into prof from public.profiles where id = uid for update;
  execute format('select %I from public.player_cars where user_id = $1 and car_id = $2 for update', p_kind) into v_cur using uid, p_car;
  if v_cur is null then raise exception 'You do not own this car'; end if;
  if v_cur >= 5 then raise exception '% is already fully upgraded', v_kind_name; end if;
  v_next := v_cur + 1;
  select unlock_level into v_need from public.upgrade_tiers where tier = v_next;
  if prof.level < v_need then raise exception 'Upgrade level % unlocks at player level %', v_next, v_need; end if;
  v_cost := public.upgrade_cost(p_kind, v_next);
  if prof.gold < v_cost then raise exception 'Not enough gold: this upgrade costs %', v_cost; end if;
  execute format('update public.player_cars set %I = $1 where user_id = $2 and car_id = $3', p_kind) using v_next, uid, p_car;
  update public.profiles set gold = prof.gold - v_cost where id = uid;
  insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
  values (uid, -v_cost, prof.gold - v_cost, 'purchase', 'upgrade:' || p_car || ':' || p_kind || ':' || v_next, v_car_name || ': ' || v_kind_name || ' level ' || v_next);
  return public.get_garage();
end $$;

create or replace function public.select_loadout(p_car text, p_team text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  v_level integer;
  v_need integer;
begin
  if uid is null then raise exception 'Sign in to use the garage' using errcode = '28000'; end if;
  select level into v_level from public.profiles where id = uid;
  if not exists (select 1 from public.player_cars where user_id = uid and car_id = p_car) then raise exception 'You do not own this car'; end if;
  select unlock_level into v_need from public.teams where id = p_team;
  if not found then raise exception 'Unknown team'; end if;
  if v_level < v_need then raise exception 'This team unlocks at level %', v_need; end if;
  update public.profiles set selected_car = p_car, selected_team = p_team where id = uid;
  return public.get_garage();
end $$;

-- ---------- start_race: snapshot the car the race is driven in ----------
create or replace function public.start_race(p_mode text, p_track text, p_laps integer, p_cars integer, p_difficulty text, p_weather text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  prof public.profiles%rowtype;
  v_unlock integer;
  v_loadout jsonb;
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
  select * into prof from public.profiles where id = uid;
  if p_mode = 'quick' then
    if v_unlock > prof.level then raise exception 'This track unlocks at level %', v_unlock; end if;
    if p_weather <> 'dry' and prof.level < 10 then raise exception 'Weather choice unlocks at level 10'; end if;
  end if;
  select jsonb_build_object('car', pc.car_id, 'team', prof.selected_team) || (to_jsonb(pc) - 'user_id' - 'car_id' - 'bought_at')
    into v_loadout from public.player_cars pc where pc.user_id = uid and pc.car_id = prof.selected_car;
  delete from public.races where user_id = uid and finished_at is null;
  insert into public.races (user_id, mode, track_id, laps, cars, difficulty, weather, challenge, loadout)
  values (uid, p_mode, p_track, p_laps, p_cars, p_difficulty, p_weather, case when p_mode = 'quick' then prof.challenge else 0 end, v_loadout)
  returning id into rid;
  return rid;
end $$;

revoke execute on function public.get_garage() from public, anon;
revoke execute on function public.buy_car(text) from public, anon;
revoke execute on function public.buy_upgrade(text, text) from public, anon;
revoke execute on function public.select_loadout(text, text) from public, anon;
revoke execute on function public.start_race(text, text, integer, integer, text, text) from public, anon;
grant execute on function public.get_garage() to authenticated;
grant execute on function public.buy_car(text) to authenticated;
grant execute on function public.buy_upgrade(text, text) to authenticated;
grant execute on function public.select_loadout(text, text) to authenticated;
grant execute on function public.start_race(text, text, integer, integer, text, text) to authenticated;
