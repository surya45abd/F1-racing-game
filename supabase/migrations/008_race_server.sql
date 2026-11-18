-- Lights Out GP · Stage 7: live Championship races (race server)
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.
-- Only the race server (secret key = service_role) may record Championship results.

-- ---------- hidden test season: local test races write here, never into real standings ----------
-- It ended long ago, so the game never shows it as the current season.
insert into public.championship_seasons (id, name, starts_at, ends_at)
values (0, 'Test season (race server tests)', '2000-01-01', '2000-01-02')
on conflict (id) do nothing;
insert into public.championship_rounds (season_id, round, track_id, laps, opens_at, closes_at)
select 0, t.sort, t.id, 3, '2000-01-01', '2000-01-02' from public.tracks t
on conflict (season_id, round) do nothing;

-- ---------- one row per live race (who raced, how it ended) ----------
create table if not exists public.championship_races (
  id           uuid primary key,
  season_id    integer not null,
  round        integer not null,
  track_id     text not null references public.tracks (id),
  laps         integer not null,
  started_at   timestamptz not null,
  finished_at  timestamptz not null default now(),
  players      integer not null,
  ai_cars      integer not null default 0,
  classification jsonb not null
);
alter table public.championship_races enable row level security;
revoke all on public.championship_races from anon, authenticated;

-- ---------- record one player's result: points from the table, gold to the wallet ----------
create or replace function public.record_championship_result(
  p_race uuid, p_season integer, p_round integer, p_user uuid, p_team text, p_position integer, p_fastest boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_points integer;
  v_gold integer := 0;
  v_balance integer;
begin
  select coalesce((select points from public.championship_points where position = p_position), 0) into v_points;
  insert into public.championship_results (season_id, round, user_id, team_id, position, points, fastest_lap, race_ref)
  values (p_season, p_round, p_user, p_team, p_position, v_points, coalesce(p_fastest, false), p_race::text)
  on conflict (season_id, round, user_id) do nothing;
  if not found then
    return jsonb_build_object('recorded', false, 'reason', 'This round already has a result for this player');
  end if;
  -- gold for real seasons only (the test season pays nothing)
  if p_season > 0 then
    v_gold := 50 + v_points * 20;
    update public.profiles set gold = gold + v_gold where id = p_user returning gold into v_balance;
    insert into public.wallet_transactions (user_id, amount, balance_after, kind, ref, note)
    values (p_user, v_gold, v_balance, 'championship', 'champ:' || p_season || ':' || p_round,
            'Championship round ' || p_round || ' · P' || p_position || ' · ' || v_points || ' pts');
  end if;
  return jsonb_build_object('recorded', true, 'points', v_points, 'gold', v_gold);
end $$;

create or replace function public.record_championship_race(
  p_race uuid, p_season integer, p_round integer, p_track text, p_laps integer, p_started timestamptz, p_players integer, p_ai integer, p_classification jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into public.championship_races (id, season_id, round, track_id, laps, started_at, players, ai_cars, classification)
  values (p_race, p_season, p_round, p_track, p_laps, p_started, p_players, p_ai, p_classification)
  on conflict (id) do nothing
$$;

revoke execute on function public.record_championship_result(uuid, integer, integer, uuid, text, integer, boolean) from public, anon, authenticated;
revoke execute on function public.record_championship_race(uuid, integer, integer, text, integer, timestamptz, integer, integer, jsonb) from public, anon, authenticated;
grant execute on function public.record_championship_result(uuid, integer, integer, uuid, text, integer, boolean) to service_role;
grant execute on function public.record_championship_race(uuid, integer, integer, text, integer, timestamptz, integer, integer, jsonb) to service_role;
