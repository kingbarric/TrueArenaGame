// End-to-end smoke test for the WS game layer: creates 6 accounts, one ad-hoc room,
// connects all 6 over /ws/room/{id}, plays a full Classic Conspiracy game to Results,
// and asserts no client ever receives another player's un-revealed role.
const BASE = "http://localhost:8080/api/v1";
// The 10 seeded players (of 15 total) — Classic Conspiracy caps at 10 players.
const SEED_PHONES = [
  "0900000001", "0900000002", "0900000003", "0900000004", "0900000005",
  "0900000006", "0900000007", "0900000008", "0900000009", "0900000010",
];
const N = SEED_PHONES.length;
const violations = [];

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
  log("setup", `${users.length} seeded accounts signed in: ${users.map((u) => u.name).join(", ")}`);

  const room = await j("POST", "/rooms", {}, users[0].token);
  log("setup", "room", room.code, room.id);
  for (let i = 1; i < N; i++) {
    await j("POST", "/rooms/join", { code: room.code }, users[i].token);
  }
  log("setup", "all joined");

  const clients = users.map((u) => ({
    ...u,
    ws: null,
    myRole: null,
    fellowTraitors: [],
    alive: new Set(),
    votedThisPhase: false,
    seenPublicRoles: {}, // eliminated ids whose role has been publicly shown
  }));

  let finished = false;
  let winningSide = null;
  const host = clients[0];

  function checkNoLeak(client, ge) {
    // Only frames a client actually receives are checked (that's the whole point).
    const d = ge.data || {};
    if (d.role && d.id) {
      // A role attached to a specific id is only legit if that id's role was
      // publicly revealed (PLAYER_ELIMINATED roleShown=true / FULL_REVEAL at end).
      if (ge.type === "PLAYER_ELIMINATED" && d.roleShown === true) return;
      if (ge.type === "FULL_REVEAL") return; // full reveal only happens at game end, for everyone
      violations.push(`${client.name} saw a bare role for ${d.id} via ${ge.type}: ${JSON.stringify(d)}`);
    }
    if (ge.type === "FULL_REVEAL" && !finished) {
      violations.push(`${client.name} received FULL_REVEAL before the game finished`);
    }
  }

  function connect(client) {
    const url = `ws://localhost:8080/ws/room/${room.id}?token=${client.token}`;
    const ws = new WebSocket(url);
    client.ws = ws;
    ws.addEventListener("open", () => {
      ws.send(JSON.stringify({ v: 1, type: "HELLO", ts: Date.now(), payload: { lastSeq: 0 } }));
    });
    ws.addEventListener("message", (ev) => {
      const env = JSON.parse(ev.data);
      if (process.env.DEBUG) log("recv", client.name, JSON.stringify(env).slice(0, 300));
      handle(client, env);
    });
    ws.addEventListener("error", (e) => log("ws-error", client.name, e.message || e));
    ws.addEventListener("close", (e) => log("ws-close", client.name, e.code, e.reason));
  }

  function send(client, type, payload) {
    if (process.env.DEBUG) log("send", client.name, type, JSON.stringify(payload));
    client.ws.send(JSON.stringify({ v: 1, type, ts: Date.now(), payload: payload || {} }));
  }

  function handle(client, env) {
    if (env.type === "ERROR") {
      log("ERROR", client.name, env.payload);
      return;
    }
    if (env.type === "SNAPSHOT") {
      if (env.payload.lobby === false && env.payload.yourRole) {
        client.myRole = env.payload.yourRole;
        client.fellowTraitors = env.payload.fellowTraitors || [];
        client.alive = new Set(env.payload.alive || []);
      }
      return;
    }
    if (env.type === "PHASE") {
      onPhase(client, env.payload.phase, env.payload.round);
      return;
    }
    if (env.type !== "EVENT") return;
    const d = env.payload;
    const ge = { type: d.type, data: d.data || {} };
    checkNoLeak(client, ge);

    switch (ge.type) {
      case "ROLE_ASSIGNED":
        client.myRole = ge.data.role;
        break;
      case "FELLOW_TRAITORS":
        client.fellowTraitors = ge.data.ids || [];
        break;
      case "GAME_STARTED":
        client.alive = new Set(ge.data.players || []);
        break;
      case "PLAYER_ELIMINATED":
        client.alive.delete(ge.data.id);
        break;
      case "GAME_OVER":
        finished = true;
        winningSide = ge.data.winningSide;
        break;
    }
  }

  function pickTarget(client) {
    const others = [...client.alive].filter((id) => id !== client.userId);
    const notFellow = others.filter((id) => !client.fellowTraitors.includes(id));
    return (notFellow[0] || others[0]);
  }

  const advancedForPhase = new Set();
  function onPhase(client, phase, round) {
    if (client === host) {
      const key = phase + ":" + round;
      const untimedHostAdvance = ["RoleReveal", "MorningReveal", "RoundTable", "VoteReview", "Elimination", "WinCheck"];
      if (untimedHostAdvance.includes(phase) && !advancedForPhase.has(key + ":" + phase)) {
        advancedForPhase.add(key + ":" + phase);
        setTimeout(() => send(host, "PLAYER_ACTION", { action: "ADVANCE_PHASE" }), 120);
      }
      if (phase === "Results") finished = true;
    }
    if (phase === "Night" && client.myRole && client.myRole.includes("traitor")) {
      const target = pickTarget(client);
      if (target) setTimeout(() => send(client, "PLAYER_ACTION", { action: "NIGHT_TARGET", data: { target } }), 150);
    }
    if (phase === "Vote") {
      const target = pickTarget(client);
      if (target) setTimeout(() => send(client, "PLAYER_ACTION", { action: "CAST_VOTE", data: { target } }), 200 + Math.random() * 300);
    }
  }

  clients.forEach(connect);
  await new Promise((r) => setTimeout(r, 800)); // let all sockets HELLO + settle in lobby

  log("game", "host starting the game");
  send(host, "GAME_START", {});

  const deadline = Date.now() + 30000;
  while (!finished && Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 250));
  }

  console.log("\n=== RESULT ===");
  console.log("finished:", finished, "winningSide:", winningSide);
  console.log("violations:", violations.length ? violations : "NONE");
  clients.forEach((c) => c.ws && c.ws.close());
  process.exit(violations.length ? 1 : finished ? 0 : 2);
}

main().catch((e) => {
  console.error("FATAL", e);
  process.exit(3);
});
