// Checks a private, unstaked Chess match against a Cyber Agent on a deployed API.
// Uses an explicitly supplied existing QA login; never prints credentials/tokens.
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
const options = Object.fromEntries(Array.from({ length: (process.argv.length - 2) / 2 },
  (_, i) => [process.argv[2 + i * 2], process.argv[3 + i * 2]]));
if (!options['--base'] || !options['--auth-file']) throw new Error('Supply --base and --auth-file');
const base = options['--base'].replace(/\/$/, '');
const credentials = JSON.parse(await readFile(options['--auth-file'], 'utf8'));
async function api(method, path, data, token) {
  const response = await fetch(base + '/api/v1' + path, {
    method, headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  const body = await response.text();
  if (!response.ok && response.status !== 404) throw new Error(`${method} ${path}: ${response.status}`);
  return body ? JSON.parse(body) : null;
}
let socket, room, token, started = false, resigned = false;
function send(type, payload) {
  socket.send(JSON.stringify({ v: 1, type, ts: Date.now(), payload }));
}
try {
  await api('POST', '/auth/otp/request', { email: credentials.email });
  const auth = await api('POST', '/auth/otp/verify', credentials);
  token = auth.accessToken;
  if (auth.user.isGuest) throw new Error('A normal QA account is required');
  const pending = await api('GET', '/rooms/pending/chess', undefined, token);
  if (pending?.status === 'lobby') throw new Error('QA account has an existing Chess lobby; leave it unchanged');
  room = await api('POST', '/rooms', { gameType: 'chess', stake: 0, ranked: false }, token);
  const bot = await api('POST', `/rooms/${room.id}/bots`, { name: 'Release QA Cyber', difficulty: 'easy' }, token);
  // A bot rejected at the account-deletion guard never becomes connected.
  let connected = false;
  for (let attempt = 0; attempt < 20; attempt++) {
    const current = await api('GET', `/rooms/${room.id}`, undefined, token);
    if (current.members.some(m => m.userId === bot.userId && m.connectionStatus === 'connected')) {
      connected = true; break;
    }
    await new Promise(r => setTimeout(r, 250));
  }
  if (!connected) throw new Error('Cyber Agent failed its authenticated room connection');
  socket = new WebSocket(base.replace(/^http/, 'ws') + `/ws/room/${room.id}?token=${encodeURIComponent(token)}`);
  let humanMoves = 0, botMoves = 0, lastActedPly = -1;
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Bot match did not advance within 30 seconds')), 30000);
    const finish = fn => value => { clearTimeout(timeout); fn(value); };
    socket.onopen = () => { send('HELLO', { lastSeq: 0 }); send('READY_SET', { ready: true }); send('GAME_START', {}); started = true; };
    socket.onerror = finish(reject).bind(null, new Error('QA game socket failed'));
    socket.onclose = event => { if (!resigned) finish(reject)(new Error('QA socket closed: ' + event.code)); };
    socket.onmessage = event => {
      const envelope = JSON.parse(event.data);
      if (envelope.type === 'ERROR') return finish(reject)(new Error('Game refused QA action: ' + envelope.payload.code));
      if (envelope.type !== 'SNAPSHOT' || envelope.payload.lobby !== false) return;
      const state = envelope.payload;
      if (state.phase === 'Results') return finish(resolve)();
      const ply = state.moves.length;
      const botWhite = state.white === bot.userId;
      botMoves = botWhite ? Math.ceil(ply / 2) : Math.floor(ply / 2);
      if (botMoves >= 2 && !resigned) {
        resigned = true;
        send('PLAYER_ACTION', { action: 'RESIGN', data: {}, actionId: randomUUID() });
        return;
      }
      const side = state.white === auth.user.id ? 'white' : 'black';
      if (state.turn === side && ply !== lastActedPly && !resigned) {
        const [from, destinations] = Object.entries(state.legalMoves)[0];
        lastActedPly = ply; humanMoves++;
        send('PLAYER_ACTION', { action: 'MOVE', data: { from, to: destinations[0] }, actionId: randomUUID() });
      }
    };
  });
  if (botMoves < 2) throw new Error('Match ended before two bot moves');
  console.log(JSON.stringify({ passed: true, botRoomConnection: true, humanMoves, botMoves,
    matchFinished: true, stake: 0 }, null, 2));
} finally {
  if (socket?.readyState === WebSocket.OPEN && started && !resigned) {
    send('PLAYER_ACTION', { action: 'RESIGN', data: {}, actionId: randomUUID() });
    await new Promise(r => setTimeout(r, 500));
  }
  socket?.close();
  if (room && !started) await api('DELETE', `/rooms/${room.id}`, undefined, token);
}
