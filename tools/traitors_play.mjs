// Plays whole solo Traitors games against a running backend — one scripted
// player hosting Cyber Agents, acting the way the app does (GameScreen's
// one-action-at-a-time lock, pickers that take a while, taps right as the
// clock runs out) — and reports every refusal, stall and stale host tap.
//
//   node tools/traitors_play.mjs <base url> <mode slug> <games>
//
// The backend needs the OTP bypass code 000000 (Spring profile `local`).
//   DUMP=<dir>   record every frame, one JSON per line, led by a META line
//                naming the player — what app/test/traitors_replay_test.dart
//                replays through the game screen
//   DROPS=<n>    drop the connection n times a game and come back, as a
//                locked phone does (GameSocket's reconnect, from lastSeq)
//   UNTAGGED=1   send the host's advance without its phase, as app builds
//                before 2026-11 did
//   END_AT=<phase>  the host ends the game for everyone on reaching that
//                phase (e.g. RoundTable); the game must still reach Results
import fs from 'node:fs';

const [, , BASE = 'http://localhost:18080', SLUG = 'final_gambit', GAMES = '1', SCALE = '0.15'] = process.argv;
const WS = BASE.replace(/^http/, 'ws');
const scale = Number(SCALE);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rand = (a, b) => a + Math.random() * (b - a);
const pick = (xs) => xs[Math.floor(Math.random() * xs.length)];

async function api(path, body, token, method = 'POST') {
  const res = await fetch(`${BASE}/api/v1${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

async function signup() {
  const phone = '+4479' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
  const r = await api('/auth/otp/verify', { phone, code: '000000' });
  return { token: r.accessToken, id: r.user.id };
}

async function playOne(gameNo, presets) {
  const preset = presets.find((p) => p.slug === SLUG);
  const config = structuredClone(preset.config);
  // The shortest clocks the server accepts (ConfigValidator), so a game is minutes, not half an hour.
  const floor = { night: 30, roundTable: 60, vote: 30 };
  for (const k of Object.keys(config.timers)) config.timers[k] = Math.max(floor[k] ?? 20, Math.round(config.timers[k] * scale));
  const me = await signup();
  const room = await api('/rooms', { gameType: 'truearena', gameConfig: config }, me.token);
  const seats = config.table.players;
  for (let i = 1; i < seats; i++) await api(`/rooms/${room.id}/bots`, { name: `Cyber ${i}`, difficulty: pick(['easy', 'medium', 'hard']) }, me.token);

  const log = { game: gameNo, slug: SLUG, room: room.id, errors: [], stalls: [], phases: [], durations: [], frames: 0, result: null };
  const st = { phase: null, round: 0, snap: {}, alive: new Set(), lastChange: Date.now(), sent: null, timers: [], lastSeq: 0, connected: false };
  const dumpTo = process.env.DUMP ? `${process.env.DUMP}/${SLUG}-${gameNo}.jsonl` : null;
  const record = (line) => dumpTo && fs.appendFileSync(dumpTo, line + '\n');
  record(JSON.stringify({ type: 'META', payload: { selfId: me.id, slug: SLUG } }));
  let ws;
  // GameSocket.send: nothing goes out while the socket is down.
  const send = (type, payload = {}) => st.connected && ws.send(JSON.stringify({ v: 1, type, ts: Date.now(), payload }));
  // GameScreen._sendAction: nothing goes out while an earlier action is still unanswered.
  const act = (action, data) => {
    if (st.locked) return;
    st.locked = true;
    st.sent = { action, data, phase: st.phase, round: st.round, at: Date.now() };
    send('PLAYER_ACTION', { action, ...(data ? { data } : {}) });
  };
  let finish;
  const done = new Promise((resolve) => (finish = resolve));
  function connect(hello) {
    ws = new WebSocket(`${WS}/ws/room/${room.id}?token=${encodeURIComponent(me.token)}`);
    ws.onopen = () => {
      st.connected = true;
      record(JSON.stringify({ type: 'CONNECTION', payload: { connected: true } }));
      ws.send(JSON.stringify({ v: 1, type: 'HELLO', ts: Date.now(), payload: { lastSeq: hello } }));
    };
    ws.onclose = () => {
      st.connected = false;
      if (st.dropping) return;
      finish();
    };
    ws.onmessage = (m) => {
      const f = JSON.parse(m.data);
      log.frames++;
      const p = f.payload || {};
      record(m.data);
      if (f.type === 'EVENT' && typeof p.seq === 'number' && p.seq > st.lastSeq) st.lastSeq = p.seq;
      if (f.type === 'ERROR' || f.type === 'SNAPSHOT' || f.type === 'PHASE') st.locked = false;
      if (f.type === 'EVENT' && p.type === 'NIGHT_TARGET_SET' && p.data?.by === me.id) st.locked = false;
      if (f.type === 'ERROR') {
        log.errors.push({ code: p.code, sent: st.sent?.action, sentPhase: st.sent?.phase, nowPhase: st.phase, msAfterSend: st.sent ? Date.now() - st.sent.at : null });
      } else if (f.type === 'SNAPSHOT' && p.lobby !== true && p.phase) {
        st.snap = p;
        if (p.alive) st.alive = new Set(p.alive);
        onPhase(p.phase, p.round ?? st.round);
        if (p.phase === 'Results') setTimeout(finish, 1500);
      } else if (f.type === 'PHASE') {
        onPhase(p.phase, p.round);
        if (p.phase === 'Results') setTimeout(finish, 1500);
      } else if (f.type === 'EVENT' && p.type === 'GAME_OVER') {
        log.result = p.data?.winningSide ?? p.data?.winner ?? JSON.stringify(p.data).slice(0, 80);
      } else if (f.type === 'EVENT' && p.type === 'GAME_ENDED_BY_HOST') {
        log.result = 'ended by host';
      }
    };
  }

  // A phone that locks or loses signal: the socket drops, then GameSocket
  // reconnects and asks for whatever it missed since the last event it saw.
  function drop(afterMs, forMs) {
    setTimeout(() => {
      if (!st.connected) return;
      st.dropping = true;
      log.drops = (log.drops || 0) + 1;
      record(JSON.stringify({ type: 'CONNECTION', payload: { connected: false } }));
      for (const t of st.timers) clearTimeout(t);
      st.timers = [];
      ws.close();
      setTimeout(() => { st.dropping = false; st.locked = false; connect(st.lastSeq); }, forMs);
    }, afterMs);
  }

  function onPhase(phase, round) {
    if (phase === st.phase && round === st.round) return;
    const now = Date.now();
    // Only the host or the clock closes these. One that dies within a second
    // and a half of opening, to a tap sent before it opened, was closed by a
    // tap meant for the screen before it.
    const hostOnly = ['RoleReveal', 'MorningReveal', 'RoundTable', 'Defense', 'VoteReview', 'Elimination', 'WinCheck'];
    if (st.sent?.action === 'ADVANCE_PHASE' && hostOnly.includes(st.phase) && st.sent.at < st.lastChange && now - st.lastChange < 1500)
      log.staleAdvance = [...(log.staleAdvance || []), `tap for ${st.sent.round}:${st.sent.phase} closed ${st.round}:${st.phase} after ${now - st.lastChange}ms`];
    if (st.phase) log.durations.push({ phase: st.phase, round: st.round, ms: now - st.lastChange, byHuman: st.sent && st.sent.action === 'ADVANCE_PHASE' && now - st.sent.at < 1500 });
    st.phase = phase; st.round = round; st.lastChange = now;
    st.phaseSeconds = st.snap.secondsLeft ?? null;
    log.phases.push(`${round}:${phase}`);
    for (const t of st.timers) clearTimeout(t);
    st.timers = [];
    plan(phase, round);
  }

  // A human with a phone: reads, opens pickers, sometimes taps right as the
  // clock runs out. Each step re-checks the screen it would be looking at.
  function later(ms, fn) { st.timers.push(setTimeout(fn, ms)); }
  function lateTap() {
    const secs = st.snap.secondsLeft;
    // Taps "just before the end" by the phone's clock — the server may already have moved on.
    return secs ? Math.max(200, secs * 1000 - rand(-400, 900)) : rand(800, 3000);
  }
  function humanDelay() { return Math.random() < 0.25 ? lateTap() : rand(400, 4000); }
  function picker(ms, fn) { later(ms, () => later(rand(800, 6000), fn)); } // sheet open, then choose

  function plan(phase, round) {
    const s = () => st.snap;
    const others = () => [...st.alive].filter((id) => id !== me.id);
    const amAlive = () => st.alive.has(me.id);
    const traitor = () => s().yourRole === 'traitor' || s().yourRole === 'recruited_traitor';
    const advance = (ms = humanDelay()) => later(ms, () => act('ADVANCE_PHASE', process.env.UNTAGGED ? undefined : { from: phase, round }));
    const chat = (channel) => later(rand(300, 5000), () => send('CHAT_SEND', { channel, text: pick(['hmm', 'not me', 'who was quiet?', 'I trust Cyber 2', 'vote with me']) }));
    // A phase can close before the tap lands (a night the agents finish fast) — then the next one ends it.
    if (process.env.END_AT === phase && !st.ended) {
      return later(rand(300, 1200), () => { st.ended = true; act('END_GAME'); });
    }
    switch (phase) {
      case 'RoleReveal': return advance(rand(500, 3000));
      case 'Night': {
        if (!amAlive()) return;
        if (traitor()) {
          chat('traitors');
          const tw = s();
          if (tw.canRecruit && (tw.recruitTargets || []).length && Math.random() < 0.6)
            picker(rand(300, 2000), () => act('RECRUIT_OFFER', { target: pick(s().recruitTargets) }));
          else if (tw.canBakePie && Math.random() < 0.7)
            picker(rand(300, 2000), () => act('BAKE_PIE', { filling: pick(['shield', 'poison']) }));
          else if (tw.canPlaceSpot && Math.random() < 0.7)
            picker(rand(300, 2000), () => act('PLACE_SPOT', { target: pick(others()) }));
          later(Math.random() < 0.3 ? lateTap() : rand(2500, 9000), () => {
            if (s().recruitingTonight) return;
            const fellows = new Set(s().fellowTraitors || []);
            const targets = others().filter((id) => !fellows.has(id));
            if (targets.length) act('NIGHT_TARGET', { target: pick(targets) });
          });
        }
        if (s().seer?.canLight) later(humanDelay(), () => s().seer?.canLight && act('SEER_LANTERN', { target: pick(others()) }));
        if (s().alibiNeeded) later(humanDelay(), () => s().alibiNeeded && !s().yourAlibi && act('ALIBI', { with: pick(others()) }));
        return;
      }
      case 'MorningReveal':
        if (s().recruitOffer) picker(rand(500, 2500), () => act('RECRUIT_ANSWER', { accept: Math.random() < 0.5 }));
        if (s().blackSpot?.holder === me.id) picker(rand(500, 2500), () => act('PASS_SPOT', { to: pick(others().filter((id) => !(s().blackSpot?.chain || []).includes(id))) }));
        return advance(rand(3000, 9000));
      case 'RoundTable': {
        if (amAlive()) chat('table');
        const t = s();
        if (t.shieldAvailable && amAlive() && Math.random() < 0.6) later(rand(500, 4000), () => act('CLAIM_SHIELD'));
        if (t.pie?.available && amAlive() && Math.random() < 0.6) later(rand(500, 4000), () => act('TAKE_PIE'));
        if (t.recruitOffer) picker(rand(500, 2500), () => act('RECRUIT_ANSWER', { accept: Math.random() < 0.5 }));
        if (t.blackSpot?.holder === me.id) picker(rand(500, 2500), () => act('PASS_SPOT', { to: pick(others().filter((id) => !(s().blackSpot?.chain || []).includes(id))) }));
        if (t.canLastStand && Math.random() < 0.5) picker(rand(500, 3000), () => act('LAST_STAND', { target: pick(others()) }));
        if (t.immunityAvailable && Math.random() < 0.5) picker(rand(500, 3000), () => act('AWARD_IMMUNITY', { target: pick([...st.alive]) }));
        if (t.canCrowdVote) later(rand(500, 5000), () => act('CROWD_VOTE', { target: pick(others()) }));
        return advance(Math.random() < 0.5 ? rand(6000, 15000) : lateTap());
      }
      case 'Vote': case 'Revote': case 'SuddenDeath': {
        if (s().canCrowdVote) later(rand(500, 3000), () => act('CROWD_VOTE', { target: pick(others()) }));
        if (!amAlive() || s().blackSpot?.silenced === me.id) return;
        later(humanDelay(), () => {
          const tied = s().tieCandidates || [];
          const pool = tied.length ? tied.filter((id) => id !== me.id) : others();
          if (pool.length) act('CAST_VOTE', { target: pick(pool) });
        });
        return;
      }
      case 'Defense': return advance();
      case 'VoteReview': {
        if (s().immunityHolder === me.id && !s().immunitySpent && Math.random() < 0.5) later(rand(300, 2000), () => act('USE_IMMUNITY'));
        if (s().rules?.voteReveal && s().rules.voteReveal !== 'all_at_once') {
          for (let i = 0; i < 3; i++) later(rand(800, 1500) * (i + 1), () => act('REVEAL_NEXT'));
          return advance(rand(5000, 8000));
        }
        return advance();
      }
      case 'Elimination':
        if (s().immunityHolder === me.id && !s().immunitySpent && Math.random() < 0.5) later(rand(300, 2000), () => act('USE_IMMUNITY'));
        return advance(rand(1500, 5000));
      case 'WinCheck': return advance(rand(800, 3000));
      case 'GhostJury':
        if (s().ghostJuror) later(humanDelay(), () => !s().yourJuryVote && act('GHOST_VOTE', { target: pick(s().tieCandidates || []) }));
        return;
      case 'HostDecision': return later(rand(1000, 4000), () => act('CHOOSE_TIE', { target: pick(s().tieCandidates || others()) }));
      case 'HostAssignVotes': return advance();
      default: return;
    }
  }

  connect(0);
  while (!st.connected) await sleep(50);
  await sleep(800);
  send('GAME_START');
  if (process.env.DROPS) for (let i = 0; i < Number(process.env.DROPS); i++) drop(rand(15_000, 150_000), rand(2_000, 25_000));
  const watchdog = setInterval(() => {
    const idle = Date.now() - st.lastChange;
    if (idle > 90_000) { log.stalls.push(`${st.round}:${st.phase} idle ${Math.round(idle / 1000)}s`); ws.close(); }
  }, 5000);
  const hardStop = setTimeout(() => ws.close(), 15 * 60_000);
  await done;
  clearInterval(watchdog); clearTimeout(hardStop);
  for (const t of st.timers) clearTimeout(t);
  try { ws.close(); } catch {}
  return log;
}

const presets = await api('/config/presets', undefined, undefined, 'GET');
const n = Number(GAMES);
const results = [];
for (let g = 1; g <= n; g++) {
  const log = await playOne(g, presets);
  results.push(log);
  const codes = log.errors.map((e) => `${e.code}(${e.sent}@${e.sentPhase}->${e.nowPhase})`);
  // A phase the human's advance tap closed within a second of it opening: a skipped screen.
  const skipped = log.durations.filter((d) => d.ms < 1000 && d.byHuman && !['WinCheck'].includes(d.phase)).map((d) => `${d.round}:${d.phase}`);
  log.skipped = skipped;
  console.log(`[${SLUG} #${g}] phases=${log.phases.length} last=${log.phases.at(-1)} drops=${log.drops || 0} errors=${log.errors.length} ${codes.join(' ')} stale=${(log.staleAdvance || []).join(',')} stalls=${log.stalls.join(';')} result=${log.result}`);
}
console.log('SUMMARY ' + JSON.stringify({ slug: SLUG, games: n, finished: results.filter((r) => r.phases.at(-1)?.endsWith('Results')).length, errors: results.flatMap((r) => r.errors.map((e) => `${e.code}:${e.sent}@${e.sentPhase}->${e.nowPhase}`)), skipped: results.flatMap((r) => r.skipped), stalls: results.flatMap((r) => r.stalls) }));
