// Lights Out GP race server: live Championship races.
// - Verifies each player's Supabase sign-in, checks eligibility (level 50, entered, round open).
// - Groups players into lobbies (2-8 real players; empty slots are AI cars that every game draws locally and that never score).
// - Runs the start clock, relays car positions (ghost cars: no contact between players), and checks every update
//   against the track (no impossible speed or lap time).
// - Decides the classification by its own clock and records official results with the service key.
//
// Env: SUPABASE_URL, SUPABASE_SECRET_KEY (server only!), PORT (8787), TEST_MODE=1 for local testing.
import { WebSocketServer } from 'ws';
import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const PORT = Number(process.env.PORT || 8787);
const TEST = process.env.TEST_MODE === '1';
const GRID = 8;                                   // cars on the grid (players + AI fill)
const MIN_PLAYERS = TEST ? 1 : 2;                 // test mode lets one person race the AI fill
const LOBBY_WAIT_MS = Number(process.env.LOBBY_WAIT_S || (TEST ? 12 : 60)) * 1000; // after the minimum is reached
const START_DELAY_MS = 6000;                      // lobby closes -> lights out (lights sequence runs in the game)
const REJOIN_MS = 30000;                          // disconnected players get this long to come back
const AFTER_LEADER_MS = (TEST ? 60 : 120) * 1000; // race ends this long after the winner finishes
const SNAPSHOT_MS = 100;                          // 10 position updates a second
const TEST_SEASON = 0;
const ROOM_MAX = 14;                              // private rooms: up to 14 drivers in total
const QUALI_MS = Number(process.env.QUALI_S || 180) * 1000; // qualifying session length
const QUALI_TO_RACE_MS = 6000;                    // show the grid, then start the race

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SECRET_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SECRET_KEY. Run with: node --env-file=../.env.local index.js');
  process.exit(1);
}
const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SECRET_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

/* ---------- catalogue ---------- */
let tracks = new Map();
async function loadTracks() {
  const { data, error } = await db.from('tracks').select('id, name, min_lap_s, unlock_level');
  if (error) throw error;
  tracks = new Map(data.map(t => [t.id, t]));
}

// the round a player can race now (or the test round)
async function currentRound() {
  if (TEST) {
    const track = process.env.TEST_TRACK || 'vespera';
    const { data } = await db.from('championship_rounds').select('round, track_id, laps').eq('season_id', TEST_SEASON).eq('track_id', track).maybeSingle();
    return data ? { season: TEST_SEASON, round: data.round, track: data.track_id, laps: Number(process.env.TEST_LAPS || data.laps), test: true } : null;
  }
  const now = new Date().toISOString();
  const { data } = await db.from('championship_rounds').select('season_id, round, track_id, laps').gt('season_id', 0).lte('opens_at', now).gt('closes_at', now).order('opens_at').limit(1).maybeSingle();
  return data ? { season: data.season_id, round: data.round, track: data.track_id, laps: data.laps, test: false } : null;
}
async function nextRound() {
  const { data } = await db.from('championship_rounds').select('round, track_id, opens_at').gt('season_id', 0).gt('opens_at', new Date().toISOString()).order('opens_at').limit(1).maybeSingle();
  return data;
}

/* ---------- connections ---------- */
let connSeq = 0;
const send = (ws, msg) => { if (ws && ws.readyState === 1) ws.send(JSON.stringify(msg)); };

async function hello(conn, msg) {
  const { data: u, error } = await db.auth.getUser(msg.token);
  if (error || !u || !u.user) return send(conn.ws, { t: 'error', code: 'auth', msg: 'Your sign-in could not be verified. Sign in again.' });
  const userId = u.user.id;
  const { data: prof } = await db.from('profiles').select('display_name, avatar_url, level, selected_team').eq('id', userId).single();
  const round = await currentRound();
  let eligible = true, reason = '', entryTeam = prof.selected_team;
  if (!round) {
    eligible = false;
    const nx = await nextRound();
    reason = nx ? 'No round is open right now. Round ' + nx.round + ' opens ' + new Date(nx.opens_at).toUTCString().slice(0, 16) + '.' : 'No round is open right now.';
  } else if (!round.test) {
    if (prof.level < 50) { eligible = false; reason = 'The Championship unlocks at level 50.'; }
    const { data: entry } = await db.from('championship_entries').select('team_id').eq('season_id', round.season).eq('user_id', userId).maybeSingle();
    if (eligible && !entry) { eligible = false; reason = 'Enter the season first (Championship → Overview).'; }
    if (entry) entryTeam = entry.team_id;
    const { data: done } = await db.from('championship_results').select('position').eq('season_id', round.season).eq('round', round.round).eq('user_id', userId).maybeSingle();
    if (eligible && done) { eligible = false; reason = 'You already raced this round (P' + done.position + '). The next round opens next week.'; }
  }
  // test mode: the same account may join twice (two tabs) as separate drivers
  const dup = [...conns.values()].filter(c => c !== conn && c.userId === userId).length;
  if (dup && !TEST) { // a second tab replaces the first one
    for (const c of conns.values()) if (c !== conn && c.userId === userId) { send(c.ws, { t: 'error', code: 'replaced', msg: 'You connected from another window.' }); c.ws.close(); }
  }
  Object.assign(conn, { userId, key: TEST ? userId + '#' + conn.id : userId, name: prof.display_name || 'Driver', baseName: prof.display_name || 'Driver',
    avatar: prof.avatar_url, team: entryTeam, ownTeam: prof.selected_team, level: prof.level, round, eligible });
  send(conn.ws, { t: 'welcome', you: { key: conn.key, name: conn.name, team: conn.team }, round: round && { ...round, trackName: tracks.get(round.track)?.name }, eligible, reason, test: TEST, serverNow: Date.now() });
  // rejoin a running race after a dropped connection
  for (const race of races.values()) {
    const p = race.players.get(conn.key);
    if (p && !race.done && !p.dnf) { p.conn = conn; p.connected = true; p.disconnectedAt = 0; conn.race = race; send(conn.ws, raceStartMsg(race, p, true)); log('rejoin', conn.name, race.id.slice(0, 8)); }
  }
}

/* ---------- lobbies ---------- */
const lobbies = new Map(); // `${season}:${round}` -> lobby
function lobbyFor(round) {
  const key = round.season + ':' + round.round;
  let l = lobbies.get(key);
  if (!l) { l = { key, round, players: new Map(), timer: null, startsAt: 0 }; lobbies.set(key, l); }
  return l;
}
function lobbyMsg(l) {
  return { t: 'lobby', players: [...l.players.values()].map(c => ({ name: c.name, team: c.team, avatar: c.avatar })), min: MIN_PLAYERS, max: GRID,
    startsIn: l.startsAt ? Math.max(0, l.startsAt - Date.now()) : null, serverNow: Date.now() };
}
function broadcastLobby(l) { for (const c of l.players.values()) send(c.ws, lobbyMsg(l)); }
function joinQueue(conn) {
  if (!conn.eligible || !conn.round) return send(conn.ws, { t: 'error', code: 'ineligible', msg: 'You cannot race this round right now.' });
  if (conn.race && !conn.race.done) return;
  const l = lobbyFor(conn.round);
  // test mode: one account can hold several seats; number them so the drivers can be told apart
  const same = [...l.players.values()].filter(c => c.userId === conn.userId && c !== conn).length;
  conn.name = conn.baseName + (same ? ' #' + (same + 1) : '');
  l.players.set(conn.key, conn); conn.lobby = l;
  if (l.players.size >= GRID) startRace(l);
  else if (l.players.size >= MIN_PLAYERS && !l.timer) { l.startsAt = Date.now() + LOBBY_WAIT_MS; l.timer = setTimeout(() => startRace(l), LOBBY_WAIT_MS); }
  broadcastLobby(l);
  log('queue', conn.name, '->', l.key, l.players.size + ' in lobby');
}
function leaveQueue(conn) {
  const l = conn.lobby; if (!l) return;
  l.players.delete(conn.key); conn.lobby = null;
  if (l.players.size < MIN_PLAYERS && l.timer) { clearTimeout(l.timer); l.timer = null; l.startsAt = 0; }
  broadcastLobby(l);
}

/* ---------- races ---------- */
const races = new Map();
function raceStartMsg(race, me, rejoin) {
  return { t: 'start', kind: race.kind, raceId: race.id, track: race.track, laps: race.laps, startAt: race.startAt, endsAt: race.endsAt || null, serverNow: Date.now(), you: me.key, rejoin: !!rejoin,
    grid: [...race.players.values()].map(p => ({ key: p.key, name: p.name, team: p.team, slot: p.slot })), ai: race.ai, test: race.test, room: race.room ? race.room.code : null };
}
// kind: 'champ' (Championship lobby), 'quali' (room qualifying), 'room' (room race); conns are in grid order
function createRace({ kind, conns, track, laps, ai, season = null, round = null, test = false, room = null }) {
  const t = tracks.get(track);
  const race = { id: randomUUID(), kind, season, round, track, laps, minLap: t.min_lap_s, test, room,
    startAt: Date.now() + START_DELAY_MS, endsAt: null, players: new Map(), ai, leaderAt: 0, done: false };
  if (kind === 'quali') race.endsAt = race.startAt + QUALI_MS;
  conns.forEach((c, i) => {
    race.players.set(c.key, { key: c.key, userId: c.userId, name: c.name, team: c.team, slot: i, conn: c, connected: true, disconnectedAt: 0,
      f: 0, lastF: 0, lastT: 0, lapStart: 0, lap: 0, best: null, finishMs: null, penalty: 0, dnf: false, why: '', strikes: 0, x: 0, y: 0, a: 0, v: 0, pit: false });
    c.lobby = null; c.race = race;
  });
  races.set(race.id, race);
  for (const p of race.players.values()) send(p.conn.ws, raceStartMsg(race, p));
  race.timer = setInterval(() => tickRace(race), SNAPSHOT_MS);
  if (kind !== 'quali') race.hardStop = setTimeout(() => endRace(race, 'time limit'), START_DELAY_MS + race.laps * race.minLap * 4000);
  log(kind, race.id.slice(0, 8), track, kind === 'quali' ? QUALI_MS / 1000 + ' s session' : laps + ' laps', race.players.size + ' players +', ai, 'AI');
  return race;
}
function startRace(l) {
  if (l.timer) { clearTimeout(l.timer); l.timer = null; }
  const conns = [...l.players.values()].filter(c => c.ws.readyState === 1);
  lobbies.delete(l.key);
  if (conns.length < MIN_PLAYERS) { for (const c of conns) { c.lobby = null; joinQueue(c); } return; }
  // Championship lobbies: random grid order
  createRace({ kind: 'champ', conns: conns.sort(() => Math.random() - 0.5), track: l.round.track, laps: l.round.laps, ai: Math.max(0, GRID - conns.length),
    season: l.round.season, round: l.round.round, test: l.round.test });
}

// plausibility: the fastest any car can lap is min_lap_s; a car may be up to 2.5x the average lap pace for a moment (straights, slipstream)
function onState(conn, m) {
  const race = conn.race; if (!race || race.done) return;
  const p = race.players.get(conn.key); if (!p || p.dnf || p.finishMs != null) return;
  const now = Date.now(); if (now < race.startAt) return;
  const f = Number(m.f);
  if (!Number.isFinite(f)) return;
  const dt = (now - (p.lastT || race.startAt)) / 1000;
  const df = f - p.f;
  if (df > (2.5 / race.minLap) * dt + 0.03) {
    p.strikes++;
    log('strike', p.name, 'f', f, 'from', p.f, 'in', dt.toFixed(2) + 's');
    if (p.strikes >= 3) return disqualify(race, p, 'Impossible speed');
    return; // ignore this update
  }
  if (df > -0.05) { p.f = Math.max(p.f, f); p.lastT = now; }
  Object.assign(p, { x: +m.x || 0, y: +m.y || 0, a: +m.a || 0, v: +m.v || 0, pit: !!m.pit, penalty: Math.max(p.penalty, Math.min(600, Math.round(+m.pen || 0))) });
  const lap = Math.floor(p.f);
  if (lap > p.lap) { // completed a lap: check its time against the track minimum
    const lapMs = now - (p.lapStart || race.startAt);
    // qualifying: every lap counts, the first one from the standing start too (the grid sits behind the line)
    if (lapMs < race.minLap * 1000 * (p.lap === 0 ? 0.9 : 1)) return disqualify(race, p, 'Impossible lap time');
    if (race.kind === 'quali' && now > race.endsAt + 1000) { p.lap = lap; return; } // lap finished after the flag
    if (p.lap > 0 || lapMs) p.best = p.best == null ? lapMs : Math.min(p.best, lapMs);
    p.lap = lap; p.lapStart = now;
  }
  if (race.kind === 'quali') return;
  if (p.f >= race.laps) {
    p.finishMs = now - race.startAt + p.penalty * 1000;
    if (!race.leaderAt) { race.leaderAt = now; race.afterLeader = setTimeout(() => endRace(race, 'leader finished'), AFTER_LEADER_MS); }
    log('finish', p.name, (p.finishMs / 1000).toFixed(1) + 's');
    if ([...race.players.values()].every(q => q.dnf || q.finishMs != null)) endRace(race, 'all finished');
  }
}
function disqualify(race, p, why) {
  p.dnf = true; p.why = why; p.strikes = 0;
  send(p.conn && p.conn.ws, { t: 'dsq', why });
  log('dsq', p.name, why);
  if (race.kind !== 'quali' && [...race.players.values()].every(q => q.dnf || q.finishMs != null)) endRace(race, 'all done');
}
function tickRace(race) {
  const now = Date.now();
  for (const p of race.players.values()) {
    if (!p.connected && !p.dnf && p.finishMs == null && now - p.disconnectedAt > REJOIN_MS) { p.dnf = true; p.why = 'Disconnected'; log('dnf', p.name, 'disconnected'); }
  }
  if (race.kind === 'quali') { if (now >= race.endsAt) return endQuali(race); }
  else if ([...race.players.values()].every(q => q.dnf || q.finishMs != null)) return endRace(race, 'all done');
  const cars = [...race.players.values()].map(p => ({ k: p.key, f: +p.f.toFixed(4), x: Math.round(p.x), y: Math.round(p.y), a: +p.a.toFixed(3), v: Math.round(p.v),
    pit: p.pit, fin: p.finishMs != null, dnf: p.dnf, on: p.connected, pen: p.penalty, b: p.best }));
  const msg = { t: 'p', cars, serverNow: now };
  for (const p of race.players.values()) if (p.connected) send(p.conn.ws, msg);
}
function classify(race) {
  const ps = [...race.players.values()];
  const fin = ps.filter(p => p.finishMs != null && !p.dnf).sort((a, b) => a.finishMs - b.finishMs);
  const run = ps.filter(p => p.finishMs == null && !p.dnf).sort((a, b) => b.f - a.f);  // still running at the end: classified by distance
  const out = ps.filter(p => p.dnf);
  let fastest = null; for (const p of [...fin, ...run]) if (p.best != null && (!fastest || p.best < fastest.best)) fastest = p;
  return [...fin, ...run].map((p, i) => ({ p, pos: i + 1, fastest: p === fastest })).concat(out.map(p => ({ p, pos: null, fastest: false })));
}
async function endRace(race, why) {
  if (race.done) return;
  race.done = true;
  clearInterval(race.timer); clearTimeout(race.hardStop); clearTimeout(race.afterLeader);
  const cls = classify(race);
  const results = [];
  const recorded = new Set();
  for (const { p, pos, fastest } of cls) {
    let rec = { recorded: false, points: 0, gold: 0 };
    if (race.kind === 'champ' && pos && !recorded.has(p.userId)) { // in test mode one account may hold several seats: record it once
      recorded.add(p.userId);
      const { data, error } = await db.rpc('record_championship_result', { p_race: race.id, p_season: race.season, p_round: race.round, p_user: p.userId, p_team: p.team, p_position: pos, p_fastest: fastest });
      if (error) log('record error', error.message); else rec = data;
    }
    results.push({ key: p.key, name: p.name, team: p.team, pos, dnf: p.dnf, why: p.why, timeMs: p.finishMs, laps: Math.min(race.laps, Math.floor(p.f)), best: p.best, fastest, points: rec.points || 0, gold: rec.gold || 0, recorded: !!rec.recorded });
  }
  if (race.kind === 'champ') {
    const { error } = await db.rpc('record_championship_race', { p_race: race.id, p_season: race.season, p_round: race.round, p_track: race.track, p_laps: race.laps,
      p_started: new Date(race.startAt).toISOString(), p_players: race.players.size, p_ai: race.ai, p_classification: results });
    if (error) log('race record error', error.message);
  } else if (race.kind === 'room') {
    const { error } = await db.from('room_races').insert({ id: race.id, code: race.room.code, host_user: race.room.hostUser, track_id: race.track, laps: race.laps,
      players: race.players.size, ai_cars: race.ai, grid: race.grid, classification: results, started_at: new Date(race.startAt).toISOString() });
    if (error) log('room record error', error.message);
  }
  for (const p of race.players.values()) { send(p.conn && p.conn.ws, { t: 'result', kind: race.kind, raceId: race.id, why, results, test: race.test, room: race.room ? race.room.code : null }); if (p.conn) p.conn.race = null; }
  races.delete(race.id);
  if (race.room) roomAfterRace(race.room);
  log('end', race.id.slice(0, 8), why, results.map(r => (r.pos || 'DNF') + ' ' + r.name).join(', '));
}

/* ---------- private rooms: a code to share, up to 14 drivers, qualifying sets the grid ---------- */
const rooms = new Map();
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O or 1/I
function newCode() { for (;;) { let c = ''; for (let i = 0; i < 6; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)]; if (!rooms.has(c)) return c; } }
function roomMsg(room, conn) {
  const t = tracks.get(room.track);
  return { t: 'room', code: room.code, you: conn.key, host: room.host, state: room.state, track: room.track, trackName: t && t.name, laps: room.laps, ai: room.ai,
    max: ROOM_MAX, qualiS: QUALI_MS / 1000, players: [...room.players.values()].map(c => ({ key: c.key, name: c.name, team: c.team, host: c.key === room.host })) };
}
function broadcastRoom(room) { for (const c of room.players.values()) send(c.ws, roomMsg(room, c)); }
function roomSettings(room, conn, m) {
  if (m.track != null) {
    const t = tracks.get(m.track);
    if (!t) throw new Error('Unknown track');
    if (!TEST && t.unlock_level > (conn.level || 1)) throw new Error('That track unlocks at level ' + t.unlock_level + ' for the host');
    room.track = m.track;
  }
  if (m.laps != null) { if (![3, 5, 8].includes(+m.laps)) throw new Error('Unsupported race distance'); room.laps = +m.laps; }
  if (m.ai != null) room.ai = Math.max(0, Math.min(ROOM_MAX - 1, Math.round(+m.ai) || 0));
}
function nameInRoom(room, conn) {
  const same = [...room.players.values()].filter(c => c.userId === conn.userId && c !== conn).length;
  conn.name = conn.baseName + (same ? ' #' + (same + 1) : '');
  conn.team = conn.ownTeam || conn.team;
}
function roomCreate(conn, m) {
  if (conn.race && !conn.race.done) throw new Error('Finish your current race first');
  roomLeave(conn);
  const room = { code: newCode(), host: conn.key, hostUser: conn.userId, players: new Map(), state: 'waiting', track: 'vespera', laps: 3, ai: 4 };
  roomSettings(room, conn, m);
  rooms.set(room.code, room);
  nameInRoom(room, conn); room.players.set(conn.key, conn); conn.room = room;
  log('room', room.code, 'created by', conn.name);
  broadcastRoom(room);
}
function roomJoin(conn, m) {
  const code = String(m.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const room = rooms.get(code);
  if (!room) throw new Error('No room with code ' + (code || '—') + '. Check the code and try again.');
  if (room.state !== 'waiting') throw new Error('That room is racing right now. Try again when the race is over.');
  if (room.players.size >= ROOM_MAX) throw new Error('That room is full (14 drivers).');
  if (conn.race && !conn.race.done) throw new Error('Finish your current race first');
  if (conn.room !== room) roomLeave(conn);
  nameInRoom(room, conn); room.players.set(conn.key, conn); conn.room = room;
  room.ai = Math.min(room.ai, ROOM_MAX - room.players.size);
  log('room', room.code, 'joined by', conn.name, room.players.size + ' drivers');
  broadcastRoom(room);
}
function roomLeave(conn) {
  const room = conn.room; if (!room) return;
  room.players.delete(conn.key); conn.room = null;
  send(conn.ws, { t: 'room', code: null });
  if (!room.players.size) { rooms.delete(room.code); log('room', room.code, 'closed'); return; }
  if (room.host === conn.key) { const next = room.players.values().next().value; room.host = next.key; room.hostUser = next.userId; }
  broadcastRoom(room);
}
function roomStart(conn) {
  const room = conn.room;
  if (!room) throw new Error('You are not in a room');
  if (room.host !== conn.key) throw new Error('Only the host can start');
  if (room.state !== 'waiting') return;
  const drivers = [...room.players.values()].filter(c => c.ws.readyState === 1);
  room.ai = Math.min(room.ai, ROOM_MAX - drivers.length);
  room.state = 'quali';
  broadcastRoom(room);
  room.race = createRace({ kind: 'quali', conns: drivers, track: room.track, laps: 99, ai: 0, test: TEST, room });
}
// qualifying over: fastest lap first, drivers without a lap at the back (ordered by distance driven)
function endQuali(race) {
  if (race.done) return;
  race.done = true; clearInterval(race.timer);
  const room = race.room, ps = [...race.players.values()];
  const order = ps.filter(p => p.best != null && !p.dnf).sort((a, b) => a.best - b.best)
    .concat(ps.filter(p => p.best == null && !p.dnf).sort((a, b) => b.f - a.f)).concat(ps.filter(p => p.dnf));
  const grid = order.map((p, i) => ({ pos: i + 1, key: p.key, name: p.name, team: p.team, best: p.best, dnf: p.dnf }));
  for (const p of ps) { send(p.conn && p.conn.ws, { t: 'quali-result', grid, raceStartsIn: QUALI_TO_RACE_MS }); if (p.conn) p.conn.race = null; }
  races.delete(race.id);
  log('quali', race.id.slice(0, 8), 'grid', grid.map(g => g.pos + '. ' + g.name + ' ' + (g.best ? (g.best / 1000).toFixed(3) : 'no time')).join(', '));
  setTimeout(() => {
    const conns = order.map(p => room.players.get(p.key)).filter(c => c && c.ws.readyState === 1 && c.room === room);
    if (!conns.length) { room.state = 'waiting'; return broadcastRoom(room); }
    room.state = 'race';
    const r = createRace({ kind: 'room', conns, track: room.track, laps: room.laps, ai: Math.min(room.ai, ROOM_MAX - conns.length), test: TEST, room });
    r.grid = grid; room.race = r;
  }, QUALI_TO_RACE_MS);
}
function roomAfterRace(room) {
  room.race = null; room.state = 'waiting';
  for (const c of [...room.players.values()]) if (c.ws.readyState !== 1) { room.players.delete(c.key); c.room = null; }
  if (!room.players.size) { rooms.delete(room.code); return; }
  if (!room.players.has(room.host)) { const next = room.players.values().next().value; room.host = next.key; room.hostUser = next.userId; }
  broadcastRoom(room);
}

/* ---------- server ---------- */
const conns = new Map();
await loadTracks();
// one port for everything: the game page over HTTP, live races over WebSocket (Render and similar hosts give a single port)
const GAME_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../games');
const FILES = { '/': ['lights-out-gp.html', 'text/html; charset=utf-8'], '/lights-out-gp.html': ['lights-out-gp.html', 'text/html; charset=utf-8'], '/cloud.js': ['cloud.js', 'text/javascript; charset=utf-8'] };
const http = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/healthz') { res.writeHead(200, { 'content-type': 'application/json' }); return res.end(JSON.stringify({ ok: true, races: races.size, rooms: rooms.size, players: conns.size })); }
  const f = FILES[url.pathname];
  if (!f || req.method !== 'GET') { res.writeHead(404, { 'content-type': 'text/plain' }); return res.end('Not found'); }
  try {
    const body = await readFile(path.join(GAME_DIR, f[0]));
    res.writeHead(200, { 'content-type': f[1], 'cache-control': 'no-cache', 'x-content-type-options': 'nosniff' });
    res.end(body);
  } catch (e) { res.writeHead(500, { 'content-type': 'text/plain' }); res.end('Game files missing'); }
});
const wss = new WebSocketServer({ server: http, maxPayload: 16 * 1024 });
http.listen(PORT);
wss.on('connection', (ws, req) => {
  const conn = { id: ++connSeq, ws, userId: null };
  conns.set(conn.id, conn);
  ws.on('message', async raw => {
    let m; try { m = JSON.parse(raw); } catch { return; }
    try {
      if (m.t === 'ping') return send(ws, { t: 'pong', c: m.c, s: Date.now() });
      if (m.t === 'hello') return await hello(conn, m);
      if (!conn.userId) return send(ws, { t: 'error', code: 'auth', msg: 'Say hello first.' });
      if (m.t === 'queue') return joinQueue(conn);
      if (m.t === 'leave') return leaveQueue(conn);
      if (m.t === 's') return onState(conn, m);
      if (m.t === 'room-create') return roomCreate(conn, m);
      if (m.t === 'room-join') return roomJoin(conn, m);
      if (m.t === 'room-leave') return roomLeave(conn);
      if (m.t === 'room-set') { const r = conn.room; if (!r || r.host !== conn.key || r.state !== 'waiting') throw new Error('Only the host can change the room'); roomSettings(r, conn, m); return broadcastRoom(r); }
      if (m.t === 'room-start') return roomStart(conn);
    } catch (e) {
      if (m && String(m.t).startsWith('room-')) return send(ws, { t: 'error', code: 'room', msg: e.message });
      log('error', e.message); send(ws, { t: 'error', code: 'server', msg: 'The race server hit a problem.' });
    }
  });
  ws.on('close', () => {
    conns.delete(conn.id);
    if (conn.lobby) leaveQueue(conn);
    if (conn.room && conn.room.state === 'waiting') roomLeave(conn);
    const race = conn.race;
    if (race && !race.done) { const p = race.players.get(conn.key); if (p && p.conn === conn) { p.connected = false; p.disconnectedAt = Date.now(); log('dropped', conn.name); } }
  });
});
log('Lights Out GP on http://0.0.0.0:' + PORT + ' (game page + live races)' + (TEST ? ' · TEST MODE (test season, 1 player minimum, ' + LOBBY_WAIT_MS / 1000 + ' s lobby)' : ''));
