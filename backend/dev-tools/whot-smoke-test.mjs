// Local-only multiplayer smoke: real REST + WebSockets, no SMS requests.
// Run: WHOT_BASE=http://localhost:8081 node backend/dev-tools/whot-smoke-test.mjs
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const base = process.env.WHOT_BASE || 'http://localhost:8081';
assert(['localhost', '127.0.0.1'].includes(new URL(base).hostname), 'Use a local development server');
const clients = [];
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function waitFor(test, label, ms = 7000) {
  const end = Date.now() + ms;
  while (!test()) { if (Date.now() > end) throw new Error(`Timed out: ${label}`); await sleep(20); }
}
async function api(path, body, token) {
  const res = await fetch(`${base}/api/v1${path}`, { method: 'POST', headers: {'content-type': 'application/json', ...(token ? {authorization: `Bearer ${token}`} : {})}, body: JSON.stringify(body) });
  assert(res.ok, `${path}: ${res.status} ${res.ok ? '' : await res.text()}`);
  return res.json();
}
function send(c, type, payload = {}) { c.ws.send(JSON.stringify({v: 1, type, ts: Date.now(), payload})); }
async function connect(c, roomId, spectator = false) {
  c.ws = new WebSocket(`${base.replace('http', 'ws')}/ws/room/${roomId}?token=${c.accessToken}${spectator ? '&spectate=true' : ''}`);
  c.frames = []; c.version = 0; c.snapshot = null; c.spectator = spectator;
  c.ws.addEventListener('message', e => {
    const f = JSON.parse(e.data); c.frames.push(f);
    if (f.type === 'SNAPSHOT') { c.snapshot = f.payload; c.version++; }
  });
  await new Promise((resolve, reject) => { c.ws.addEventListener('open', resolve, {once: true}); c.ws.addEventListener('error', reject, {once: true}); });
  send(c, 'HELLO', {lastSeq: 0});
  if (!spectator) await waitFor(() => c.snapshot, 'initial snapshot');
}
async function action(c, action, data = {}, expectedError) {
  const version = c.version, offset = c.frames.length;
  send(c, 'PLAYER_ACTION', {action, data, actionId: randomUUID()});
  await waitFor(() => c.version > version || c.frames.slice(offset).some(f => f.type === 'ERROR'), action);
  const errors = c.frames.slice(offset).filter(f => f.type === 'ERROR');
  if (expectedError) assert.equal(errors[0]?.payload.code, expectedError);
  else assert.deepEqual(errors, [], `${action} refused`);
  await sleep(35); // let the event log append finish before the next lock acquisition
}
function legal(card, s) {
  const [shape, n] = card.split('-');
  if (s.pendingPick) return n === '2' && s.rules.pickTwo && s.rules.pickTwoStacking;
  return shape === 'whot' || shape === s.activeShape || n === s.topCard.split('-')[1];
}
async function main() {
  // Reserved development identities. Bypass verification is enabled only by local profile.
  for (const phone of ['0900088801', '0900088802', '0900088803']) {
    clients.push(await api('/auth/otp/verify', {phone, code: '000000'}));
  }
  const [a, b, spectator] = clients;
  const room = await api('/rooms', {gameType: 'whot', gameConfig: {turnSeconds: 10, startingHand: 5}}, a.accessToken);
  await api('/rooms/join', {code: room.code}, b.accessToken);
  await connect(a, room.id); await connect(b, room.id); await connect(spectator, room.id, true);
  send(a, 'READY_SET', {ready: true}); send(b, 'READY_SET', {ready: true});
  await sleep(80);
  send(a, 'GAME_START');
  await waitFor(() => a.snapshot?.phase === 'Deal' && b.snapshot?.phase === 'Deal', 'game start');
  assert.equal(a.snapshot.suggestedHand, 5);
  const dealer = [a,b].find(c => c.user.id === a.snapshot.dealer);
  const other = dealer === a ? b : a;
  await action(other, 'DEAL', {}, 'NOT_THE_DEALER');
  await action(dealer, 'SHUFFLE');
  await action(dealer, 'DEAL', {rounds: 5});
  assert.equal(a.snapshot.yourHand.length, 5); assert.equal(b.snapshot.yourHand.length, 5);
  await action(dealer, 'START');
  const firstRound = a.snapshot.round;
  await waitFor(() => a.snapshot.round > firstRound, 'first automatic timeout', 13000);
  const secondRound = a.snapshot.round;
  await waitFor(() => a.snapshot.round > secondRound, 'second automatic timeout', 13000);
  assert(a.snapshot.secondsLeft >= 8, 'next turn gets a fresh clock');
  console.log('PASS: create, join, ready, dealer restrictions, deal and consecutive turn timeouts');
  // Reconnect a player and restore only their own hand.
  const savedHand = [...b.snapshot.yourHand];
  b.ws.close(); await sleep(150); await connect(b, room.id);
  assert.deepEqual(b.snapshot.yourHand, savedHand);
  console.log('PASS: reconnect restores private hand');
  let turns = 0;
  while (a.snapshot.phase !== 'Results' && turns++ < 1500) {
    const current = [a,b].find(c => c.user.id === a.snapshot.turnPlayer);
    await waitFor(() => current.snapshot.round === a.snapshot.round, 'synchronized turn');
    const s = current.snapshot;
    const card = s.yourHand.find(c => legal(c, s));
    if (!card) await action(current, 'DRAW');
    else {
      const shapes = ['circle','triangle','cross','square','star'];
      shapes.sort((x,y) => s.yourHand.filter(c => c.startsWith(y)).length - s.yourHand.filter(c => c.startsWith(x)).length);
      await action(current, 'PLAY', {card, ...(card.startsWith('whot') ? {shape: shapes[0]} : {})});
    }
  }
  await waitFor(() => a.snapshot.phase === 'Results' && b.snapshot.phase === 'Results', 'results');
  assert.equal(a.snapshot.winner, b.snapshot.winner);
  assert.equal(a.snapshot.handSizes[a.snapshot.winner], 0);
  const win = a.snapshot.winner;
  const v = a.version; send(a, 'HELLO', {lastSeq: 0}); await waitFor(() => a.version > v, 'results snapshot');
  assert.equal(a.snapshot.winner, win);
  for (const c of clients) for (const f of c.frames) {
    if (f.type === 'SNAPSHOT') {
      assert(!('hands' in f.payload), 'no all-hands field');
      if (c.spectator) assert.equal((f.payload.yourHand || []).length, 0);
      else if (f.payload.yourHand) assert.equal(f.payload.yourHand.length, f.payload.handSizes[c.user.id]);
    }
    if (c.spectator && f.type === 'EVENT') assert(!['YOUR_HAND','YOUR_DRAW'].includes(f.payload.type), 'no private events to spectators');
  }
  console.log(`PASS: full ${turns}-move match, shared winner, results resync and spectator privacy`);
}
try { await main(); } catch(e) { console.error(e); process.exitCode = 1; }
finally { clients.forEach(c => c.ws?.close()); }
