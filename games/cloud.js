/* Lights Out GP · cloud: Google sign-in, player profile and cloud saves (Supabase).
   Loaded before the game script. Exposes window.LOGP_CLOUD; the game works without it (offline, or script blocked). */
(() => {
  'use strict';
  // The publishable key is meant to be public; row-level security in the database protects player data.
  const CONFIG = {
    url: 'https://kuompdrogzkazycrohcr.supabase.co',
    key: 'sb_publishable_FOUpdNMCOvxepQW8dcxdEg_bPMW9ika',
    appRedirect: 'lightsoutgp://auth',
  };
  // game data only: never the sign-in session (logp-auth…), the sync bookkeeping or the bulky time-trial ghosts
  const SYNC_KEYS = k => k.startsWith('logp-') && !k.startsWith('logp-auth') && !k.startsWith('logp-ghost') && k !== 'logp-sync-meta';
  const META_KEY = 'logp-sync-meta';
  const RNW = window.ReactNativeWebView;

  const ls = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} },
    del(k) { try { localStorage.removeItem(k); } catch (e) {} },
    keys() { try { return Object.keys(localStorage); } catch (e) { return []; } },
  };
  const meta = () => { try { return JSON.parse(ls.get(META_KEY)) || {}; } catch (e) { return {}; } };
  const setMeta = m => ls.set(META_KEY, JSON.stringify(m));

  const state = { status: 'loading', user: null, profile: null, error: '', sync: 'idle', syncedAt: null };
  const listeners = new Set();
  const emit = () => listeners.forEach(fn => { try { fn(state); } catch (e) { console.error(e); } });
  const set = patch => { Object.assign(state, patch); emit(); };

  const lib = window.supabase;
  if (!lib || !lib.createClient) {
    set({ status: 'unavailable', error: 'Online features could not load. Check your connection.' });
    window.LOGP_CLOUD = { state, onChange: fn => { listeners.add(fn); fn(state); }, signIn() {}, signOut() {}, dirty() {}, retry() { location.reload(); } };
    return;
  }
  const sb = lib.createClient(CONFIG.url, CONFIG.key, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: !RNW, flowType: RNW ? 'implicit' : 'pkce', storageKey: 'logp-auth' },
  });

  /* ---------- saves ---------- */
  function localSave() {
    const data = {};
    for (const k of ls.keys()) if (SYNC_KEYS(k)) data[k] = ls.get(k);
    return data;
  }
  function applySave(data) {
    for (const k of ls.keys()) if (SYNC_KEYS(k) && !(k in data)) ls.del(k);
    for (const k in data) if (SYNC_KEYS(k) && typeof data[k] === 'string') ls.set(k, data[k]);
  }
  const sameSave = (a, b) => { const ka = Object.keys(a).sort(), kb = Object.keys(b).sort(); return ka.join() === kb.join() && ka.every(k => a[k] === b[k]); };

  let pushTimer = 0, pushing = false, pendingPush = false;
  async function push() {
    if (!state.user) return;
    if (pushing) { pendingPush = true; return; }
    pushing = true; set({ sync: 'saving' });
    const at = new Date().toISOString();
    const { error } = await sb.from('player_saves').upsert({ user_id: state.user.id, data: localSave(), client_updated_at: at });
    pushing = false;
    if (error) { set({ sync: 'error', error: friendly(error) }); schedule(30000); return; }
    setMeta({ user: state.user.id, at }); set({ sync: 'saved', syncedAt: Date.now(), error: '' });
    if (pendingPush) { pendingPush = false; schedule(500); }
  }
  function schedule(ms) { clearTimeout(pushTimer); pushTimer = setTimeout(push, ms); }

  // first sync after sign-in: newest save wins; a different player's local data is never uploaded to this account
  async function firstSync(user) {
    const m = meta();
    const { data: row, error } = await sb.from('player_saves').select('data, client_updated_at').eq('user_id', user.id).maybeSingle();
    if (error) throw error;
    const local = localSave();
    const localIsOther = m.user && m.user !== user.id;
    if (row && (localIsOther || !m.user || new Date(row.client_updated_at) > new Date(m.at || 0))) {
      setMeta({ user: user.id, at: row.client_updated_at });
      if (!sameSave(local, row.data || {})) { applySave(row.data || {}); return 'applied'; }
      return 'ok';
    }
    // first sign-in of a new account on a device that holds another player's progress: start this account fresh
    if (!row && localIsOther) { applySave({}); setMeta({ user: user.id, at: new Date(0).toISOString() }); await push(); return 'applied'; }
    await push();
    return 'ok';
  }

  /* ---------- profile ---------- */
  async function loadProfile(user) {
    for (let i = 0; i < 4; i++) {
      let { data, error } = await sb.from('profiles').select('id, display_name, avatar_url, level, xp, gold, challenge, created_at').eq('id', user.id).maybeSingle();
      // before the Stage 4 script runs there is no challenge column yet: load the profile without it
      if (error && /challenge|42703/.test((error.message || '') + (error.code || ''))) ({ data, error } = await sb.from('profiles').select('id, display_name, avatar_url, level, xp, gold, created_at').eq('id', user.id).maybeSingle());
      if (error) throw error;
      if (data) return data;
      await new Promise(r => setTimeout(r, 600)); // the sign-up trigger may still be running
    }
    throw new Error('Your player profile was not created. Run the Stage 1 database script in Supabase.');
  }

  function friendly(err) {
    const msg = (err && (err.message || err.error_description || String(err))) || 'Something went wrong';
    if (/Could not find the function|PGRST202/i.test(msg + (err.code || ''))) return 'This feature is not set up on the server yet. Run the latest script in Supabase.';
    if (/relation .* does not exist|schema cache|PGRST205|42P01/i.test(msg + (err.code || ''))) return 'The game database is not fully set up yet. Run the latest script in Supabase.';
    if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) return 'You are offline. Progress is kept on this device and will sync later.';
    return msg;
  }

  let started = null;
  async function onSession(session) {
    const user = session && session.user;
    if (!user) { set({ status: 'signed-out', user: null, profile: null, sync: 'idle' }); return; }
    if (started === user.id) return;
    started = user.id;
    set({ status: 'loading', user });
    try {
      const profile = await loadProfile(user);
      set({ profile });
      levels().then(l => set({ levels: l })).catch(() => {});
      refreshTasks();
      tracks().then(t => set({ tracks: t })).catch(() => {});
      garage().catch(() => {});
      const r = await firstSync(user);
      sb.from('profiles').update({ last_seen_at: new Date().toISOString() }).eq('id', user.id).then(() => {});
      set({ status: 'signed-in', sync: 'saved', syncedAt: Date.now(), error: '' });
      if (r === 'applied') { if (window.LOGP_APPLY_SAVE) window.LOGP_APPLY_SAVE(); else location.reload(); }
    } catch (e) {
      started = null;
      set({ status: 'error', error: friendly(e) });
    }
  }

  /* ---------- sign in / out ---------- */
  async function googleEnabled() {
    const r = await fetch(CONFIG.url + '/auth/v1/settings', { headers: { apikey: CONFIG.key } });
    if (!r.ok) throw new Error('Could not reach the sign-in service.');
    const s = await r.json();
    return !!(s.external && s.external.google);
  }
  async function signIn() {
    set({ status: 'signing-in', error: '' });
    try {
      if (!(await googleEnabled())) throw new Error('Google sign-in is not switched on in Supabase yet (Authentication → Sign In / Providers → Google).');
      if (RNW) {
        // Google blocks sign-in inside embedded web views, so the app opens the system browser and hands the session back
        const url = CONFIG.url + '/auth/v1/authorize?provider=google&redirect_to=' + encodeURIComponent(CONFIG.appRedirect);
        RNW.postMessage(JSON.stringify({ t: 'signin', url, redirect: CONFIG.appRedirect }));
        return;
      }
      const redirectTo = location.origin + location.pathname;
      const { error } = await sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo, queryParams: { prompt: 'select_account' } } });
      if (error) throw error;
    } catch (e) { set({ status: 'signed-out', error: friendly(e) }); }
  }
  // called by the phone app after the system browser returns
  window.__logpSession = async (access_token, refresh_token) => {
    const { error } = await sb.auth.setSession({ access_token, refresh_token });
    if (error) set({ status: 'signed-out', error: friendly(error) });
  };
  window.__logpSignInFailed = msg => set({ status: 'signed-out', error: msg || 'Sign-in was cancelled.' });

  async function signOut() {
    clearTimeout(pushTimer);
    if (state.user) await push();
    await sb.auth.signOut();
    started = null;
    set({ status: 'signed-out', user: null, profile: null, sync: 'idle' });
  }

  // a failed Google sign-in comes back as ?error=…&error_description=… (or in the #hash): show it, then tidy the address bar
  const back = new URLSearchParams(location.search + '&' + location.hash.replace(/^#/, ''));
  const backErr = back.get('error_description') || back.get('error');
  if (backErr) {
    set({ status: 'signed-out', error: 'Google sign-in failed: ' + backErr.replace(/\+/g, ' ') });
    try { history.replaceState(null, '', location.pathname); } catch (e) {}
  }

  sb.auth.onAuthStateChange((event, session) => { setTimeout(() => onSession(session), 0); });
  sb.auth.getSession().then(({ data }) => onSession(data.session)).catch(e => set({ status: 'error', error: friendly(e) }));
  addEventListener('online', () => { if (state.sync === 'error') push(); });

  /* ---------- progression (Stage 2): the server checks every race and awards XP / level rewards ---------- */
  let levelsCache = null;
  async function levels() {
    if (levelsCache) return levelsCache;
    const { data, error } = await sb.from('levels').select('*').order('level');
    if (error) throw new Error(friendly(error));
    levelsCache = data;
    return data;
  }
  async function startRace(cfg) {
    if (state.status !== 'signed-in') return null;
    const { data, error } = await sb.rpc('start_race', {
      p_mode: cfg.mode, p_track: cfg.track, p_laps: cfg.laps, p_cars: cfg.cars, p_difficulty: cfg.difficulty, p_weather: cfg.weather,
    });
    if (error) throw new Error(friendly(error));
    return data;
  }
  async function finishRace(raceId, res) {
    const { data, error } = await sb.rpc('finish_race', {
      p_race: raceId, p_position: res.position, p_race_time: res.raceTime, p_best_lap: res.bestLap,
      p_fastest_lap: !!res.fastestLap, p_penalties: Math.round(res.penalties || 0),
    });
    if (error) throw new Error(friendly(error));
    if (state.profile) set({ profile: Object.assign({}, state.profile, { xp: data.xp_total, level: data.level_after, gold: data.gold_total, challenge: data.challenge_after == null ? state.profile.challenge : data.challenge_after }) });
    if (state.garage) set({ garage: Object.assign({}, state.garage, { gold: data.gold_total, level: data.level_after }) });
    refreshTasks();
    return data;
  }
  // unlock levels are configured on the server (public.tracks), so they can change without an app update
  let tracksCache = null;
  async function tracks() {
    if (tracksCache) return tracksCache;
    const { data, error } = await sb.from('tracks').select('id, unlock_level, difficulty').order('sort');
    if (error) throw new Error(friendly(error));
    tracksCache = data;
    return data;
  }
  // per-track races, wins and best lap from the player's verified races
  async function trackStats() {
    if (!state.user) return {};
    const { data, error } = await sb.from('races').select('track_id, position, best_lap').eq('user_id', state.user.id).not('finished_at', 'is', null).limit(1000);
    if (error) throw new Error(friendly(error));
    const out = {};
    for (const r of data) {
      const s = out[r.track_id] || (out[r.track_id] = { races: 0, wins: 0, best: null });
      s.races++; if (r.position === 1) s.wins++;
      if (r.best_lap && (s.best == null || r.best_lap < s.best)) s.best = r.best_lap;
    }
    return out;
  }
  // wallet: balance lives on the profile; every change is logged in wallet_transactions
  async function wallet(limit) {
    if (!state.user) return [];
    const { data, error } = await sb.from('wallet_transactions').select('amount, balance_after, kind, note, created_at').eq('user_id', state.user.id)
      .order('created_at', { ascending: false }).order('id', { ascending: false }).limit(limit || 100);
    if (error) throw new Error(friendly(error));
    return data;
  }
  async function achievements() {
    const [all, mine] = await Promise.all([
      sb.from('achievements').select('id, name, description, reward_gold, sort').order('sort'),
      state.user ? sb.from('player_achievements').select('achievement_id, unlocked_at').eq('user_id', state.user.id) : Promise.resolve({ data: [] }),
    ]);
    if (all.error) throw new Error(friendly(all.error));
    if (mine.error) throw new Error(friendly(mine.error));
    const got = Object.fromEntries(mine.data.map(m => [m.achievement_id, m.unlocked_at]));
    return all.data.map(a => Object.assign({}, a, { unlocked_at: got[a.id] || null }));
  }
  // garage (Stage 5): the server owns cars, upgrades and gold; every call returns the whole garage
  async function rpcGarage(fn, args) {
    const { data, error } = await sb.rpc(fn, args || {});
    if (error) throw new Error(friendly(error));
    set({ garage: data, profile: state.profile ? Object.assign({}, state.profile, { gold: data.gold, level: data.level }) : state.profile });
    return data;
  }
  const garage = () => rpcGarage('get_garage');
  const buyCar = car => rpcGarage('buy_car', { p_car: car });
  const buyUpgrade = (car, kind) => rpcGarage('buy_upgrade', { p_car: car, p_kind: kind });
  const selectLoadout = (car, team) => rpcGarage('select_loadout', { p_car: car, p_team: team });
  // championship (Stage 6): overview, joining, standings, global leaderboard
  async function rpc(fn, args) { const { data, error } = await sb.rpc(fn, args || {}); if (error) throw new Error(friendly(error)); return data; }
  const championship = () => rpc('championship_overview');
  const joinChampionship = team => rpc('join_championship', { p_team: team });
  const standings = season => rpc('championship_standings', { p_season: season });
  const leaderboard = () => rpc('global_leaderboard');
  // the race server checks this token to know who is connecting
  async function accessToken() { const { data } = await sb.auth.getSession(); return data.session ? data.session.access_token : null; }
  // levels by tasks: the 3 tasks of a level and the player's progress on them
  async function tasks(level) {
    const lvl = level || (state.profile && state.profile.level);
    if (!state.user || !lvl) return [];
    const [a, b] = await Promise.all([
      sb.from('level_tasks').select('slot, params, description').eq('level', lvl).order('slot'),
      sb.from('player_tasks').select('slot, progress, done_at').eq('user_id', state.user.id).eq('level', lvl),
    ]);
    if (a.error) throw new Error(friendly(a.error));
    const mine = Object.fromEntries(((b.data) || []).map(x => [x.slot, x]));
    return a.data.map(t => ({ level: lvl, slot: t.slot, description: t.description, count: (t.params && t.params.count) || 1,
      progress: (mine[t.slot] || {}).progress || 0, done: !!(mine[t.slot] || {}).done_at }));
  }
  let allTasksCache = null;
  async function allTasks() {
    if (allTasksCache) return allTasksCache;
    const { data, error } = await sb.from('level_tasks').select('level, slot, description').order('level').order('slot');
    if (error) throw new Error(friendly(error));
    return (allTasksCache = data);
  }
  const refreshTasks = () => tasks().then(t => set({ tasks: t })).catch(() => set({ tasks: null }));
  async function progressHistory() {
    if (!state.user) return { levels: [], races: [] };
    const [h, r] = await Promise.all([
      sb.from('level_history').select('level, reached_at, xp_total').eq('user_id', state.user.id).order('level', { ascending: false }),
      sb.from('races').select('track_id, laps, cars, difficulty, position, xp_awarded, gold_awarded, finished_at').eq('user_id', state.user.id)
        .not('finished_at', 'is', null).order('finished_at', { ascending: false }).limit(10),
    ]);
    if (h.error) throw new Error(friendly(h.error));
    if (r.error) throw new Error(friendly(r.error));
    return { levels: h.data, races: r.data };
  }

  window.LOGP_CLOUD = {
    state,
    onChange(fn) { listeners.add(fn); fn(state); return () => listeners.delete(fn); },
    signIn, signOut, levels, tracks, trackStats, startRace, finishRace, progressHistory, wallet, achievements, garage, buyCar, buyUpgrade, selectLoadout, championship, joinChampionship, standings, leaderboard, accessToken, tasks, allTasks, refreshTasks,
    dirty() { if (state.status === 'signed-in') schedule(2500); },
    retry() { started = null; sb.auth.getSession().then(({ data }) => onSession(data.session)); },
    async refreshProfile() { if (state.user) { try { set({ profile: await loadProfile(state.user) }); } catch (e) { set({ error: friendly(e) }); } } },
  };
})();
