// Smoke test for discussion-phase chat (table + traitors channels). Drives a real
// 6-player game up to RoundTable, holds there (doesn't auto-advance) to exercise
// chat, then advances to Vote and confirms chat is rejected there.
const BASE = "http://localhost:8080/api/v1";
const SEED_PHONES = ["0900000001", "0900000002", "0900000003", "0900000004", "0900000005", "0900000006"];
const N = SEED_PHONES.length;
const problems = [];

async function j(method, path, body, token) {
  const res = await fetch(BASE + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: "Bearer " + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${text}`);
  return data;
}

async function signup(phone) {
  await j("POST", "/auth/otp/request", { phone });
  const t = await j("POST", "/auth/otp/verify", { phone, code: "000000" });
  return { token: t.accessToken, userId: t.user.id, name: t.user.displayName };
}

function log(tag, ...args) {
  console.log(`[${tag}]`, ...args);
}

async function main() {
  const users = [];
  for (const phone of SEED_PHONES) users.push(await signup(phone));
  log("setup", users.map((u) => u.name).join(", "));

  const room = await j("POST", "/rooms", {}, users[0].token);
  for (let i = 1; i < N; i++) await j("POST", "/rooms/join", { code: room.code }, users[i].token);

  const clients = users.map((u) => ({ ...u, ws: null, myRole: null, alive: new Set(), chatSeen: [], errors: [] }));
  const host = clients[0];
  let phase = null;
  let roundTableReached = false;

  function connect(client) {
    const ws = new WebSocket(`ws://localhost:8080/ws/room/${room.id}?token=${client.token}`);
    client.ws = ws;
    ws.addEventListener("open", () => ws.send(JSON.stringify({ v: 1, type: "HELLO", ts: Date.now(), payload: { lastSeq: 0 } })));
    ws.addEventListener("message", (ev) => handle(client, JSON.parse(ev.data)));
  }

  function send(client, type, payload) {
    client.ws.send(JSON.stringify({ v: 1, type, ts: Date.now(), payload: payload || {} }));
  }

  function handle(client, env) {
    if (env.type === "ERROR") {
      client.errors.push(env.payload);
      return;
    }
    if (env.type === "PHASE") {
      phase = env.payload.phase;
      if (phase === "RoundTable") roundTableReached = true;
      if (phase === "Night") driveNight(client);
      if (client === host) driveHost(phase);
      return;
    }
    if (env.type !== "EVENT") return;
    const { type, data } = env.payload;
    if (type === "ROLE_ASSIGNED") client.myRole = data.role;
    if (type === "GAME_STARTED") client.alive = new Set(data.players);
    if (type === "CHAT_MESSAGE") client.chatSeen.push({ from: users.find((u) => u.userId === data.from)?.name, ...data });
  }

  function driveNight(client) {
    if (!client.myRole || !client.myRole.includes("traitor")) return;
    const target = [...client.alive].find((id) => id !== client.userId);
    if (target) setTimeout(() => send(client, "PLAYER_ACTION", { action: "NIGHT_TARGET", data: { target } }), 150);
  }

  const advanced = new Set();
  function driveHost(p) {
    // RoundTable is intentionally NOT auto-advanced — the chat test does that manually.
    const untimed = ["RoleReveal", "MorningReveal", "VoteReview", "Elimination", "WinCheck"];
    if (untimed.includes(p) && !advanced.has(p)) {
      advanced.add(p);
      setTimeout(() => send(host, "PLAYER_ACTION", { action: "ADVANCE_PHASE" }), 100);
    }
  }

  clients.forEach(connect);
  await new Promise((r) => setTimeout(r, 600));
  send(host, "GAME_START", {});

  const deadline1 = Date.now() + 15000;
  while (!roundTableReached && Date.now() < deadline1) await new Promise((r) => setTimeout(r, 150));
  if (!roundTableReached) {
    console.log("FATAL: never reached RoundTable");
    process.exit(3);
  }
  log("phase", "reached RoundTable — running chat checks");
  await new Promise((r) => setTimeout(r, 200)); // let ROLE_ASSIGNED settle everywhere

  const traitor = clients.find((c) => c.myRole && c.myRole.includes("traitor"));
  const faithful = clients.find((c) => c.myRole === "faithful");

  // 1. Table chat: everyone should see it.
  send(faithful, "CHAT_SEND", { channel: "table", text: "anyone acting suspicious?" });
  await new Promise((r) => setTimeout(r, 300));
  for (const c of clients) {
    if (!c.chatSeen.some((m) => m.channel === "table")) problems.push(`${c.name} never saw the table message`);
  }

  // 2. Traitors channel: only traitors should see it.
  const traitors = clients.filter((c) => c.myRole && c.myRole.includes("traitor"));
  const faithfuls = clients.filter((c) => c.myRole === "faithful");
  send(traitor, "CHAT_SEND", { channel: "traitors", text: "let's target the loud one" });
  await new Promise((r) => setTimeout(r, 300));
  for (const c of traitors) {
    if (!c.chatSeen.some((m) => m.channel === "traitors")) problems.push(`traitor ${c.name} never saw the traitors-channel message`);
  }
  for (const c of faithfuls) {
    if (c.chatSeen.some((m) => m.channel === "traitors")) problems.push(`LEAK: faithful ${c.name} saw a traitors-channel message`);
  }

  // 3. A faithful trying the traitors channel should be rejected.
  faithful.errors = [];
  send(faithful, "CHAT_SEND", { channel: "traitors", text: "sneaking in" });
  await new Promise((r) => setTimeout(r, 250));
  if (!faithful.errors.some((e) => e.code === "NOT_TRAITOR")) problems.push("faithful sending to traitors channel was not rejected with NOT_TRAITOR");

  // 4. Advance to Vote, then chat should be rejected for everyone.
  send(host, "PLAYER_ACTION", { action: "ADVANCE_PHASE" });
  const deadline2 = Date.now() + 8000;
  while (phase !== "Vote" && Date.now() < deadline2) await new Promise((r) => setTimeout(r, 150));
  if (phase !== "Vote") problems.push("never reached Vote phase");
  faithful.errors = [];
  send(faithful, "CHAT_SEND", { channel: "table", text: "too late?" });
  await new Promise((r) => setTimeout(r, 250));
  if (!faithful.errors.some((e) => e.code === "WRONG_PHASE")) problems.push("chat during Vote was not rejected with WRONG_PHASE");

  console.log("\n=== RESULT ===");
  console.log("problems:", problems.length ? problems : "NONE");
  clients.forEach((c) => c.ws && c.ws.close());
  process.exit(problems.length ? 1 : 0);
}

main().catch((e) => {
  console.error("FATAL", e);
  process.exit(2);
});
