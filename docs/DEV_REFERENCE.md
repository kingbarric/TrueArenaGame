# Dev Reference

Living scratch-reference for things that come up repeatedly during local development:
seeded test data, dev-only bypasses, local ports, reusable design tokens, and notable
build decisions worth remembering before touching the same area again. This is **not**
the architecture doc (`ARCHITECTURE.md`) or the schema doc (`DATABASE.md`) — it's the
"where did I put that / why did I do it that way" doc. Update it whenever you create
something reusable or make a decision you'd otherwise forget by next session.

---

## 1. Local dev stack

Docker Compose (`infra/docker-compose.yml`) maps host ports away from anything already
running natively on this machine:

| Service  | Container port | Host port | Notes |
|----------|----------------|-----------|-------|
| Postgres | 5432           | **5433**  | native Postgres already had 5432 |
| Redis    | 6379           | **6380**  | an existing `redis_cache` container already had 6379 |
| Backend  | 8080           | 8080      | run as a plain jar, not in Compose |

Bring up the data layer:
```bash
cd infra && docker compose up -d
```

Run the backend jar against it (defaults in `application.yml` point at port 5432/6379,
so these env vars are **required** locally):
```bash
cd backend
./mvnw -q -B -ntp -DskipTests clean install   # rebuild after code changes
R2DBC_URL="r2dbc:postgresql://localhost:5433/truearena" \
JDBC_URL="jdbc:postgresql://localhost:5433/truearena" \
REDIS_PORT=6380 \
SPRING_PROFILES_ACTIVE=local \
java -jar ta-app/target/truearena-backend.jar
```
- Swagger UI: `http://localhost:8080/swagger-ui.html`
- Health: `http://localhost:8080/actuator/health`
- `SPRING_PROFILES_ACTIVE=local` enables the OTP dev bypass (§2) and `/api/v1/dev/**`.

Run the Flutter app on the booted iOS simulator:
```bash
cd app
flutter run -d <simulator-udid>   # `xcrun simctl list devices | grep Booted` to find it
```
If a build fails with `No space left on device`, check `df -h /` first — Docker image/
build-cache (`docker builder prune -f`, `docker image prune -f`) and
`~/Library/Developer/Xcode/DerivedData` are the usual multi-GB offenders on this machine.

---

## 2. Auth: phone or email, dev OTP bypass

Registration accepts **either** phone **or** email — exactly one is required per
request, both verified with the same 6-digit OTP flow. Email codes are sent
through Brevo when `BREVO_API_KEY` is set, from `verify@playhuud.com`.
Without that key, the `local` profile logs the code to the backend console;
other profiles return an error instead of pretending an email was sent.
SMS remains a local stub. In the `local` profile, **`000000` always verifies
for any phone or email**.

The Brevo domain ownership code is a DNS TXT record for `playhuud.com`, not
an API key. Brevo also requires DKIM and DMARC records for domain
authentication. Keep `BREVO_API_KEY` in the backend environment or deployment
secrets, never in a tracked file. The production Compose service passes it
through when present.

```bash
curl -X POST localhost:8080/api/v1/auth/otp/request -H 'content-type: application/json' \
  -d '{"phone":"0900000001"}'                                    # or {"email":"..."}
curl -X POST localhost:8080/api/v1/auth/otp/verify -H 'content-type: application/json' \
  -d '{"phone":"0900000001","code":"000000"}'
```
As of 2026-09-13, **`OtpVerify` takes no `displayName`/`username`** — signup is
identifier-then-code only, full stop. The backend auto-generates both (a
`Player <last4>`-style display name, a random `adjective_noun1234` username) on the
verify call that actually creates the account, which is the only one where the
response's `newAccount` is `true`. The Flutter app uses that flag to show
`UsernameSetupScreen` once, right after a fresh signup, to offer picking a real
username in place of the random one — `PATCH /api/v1/me` (409 if taken) is what
that screen (and any later "change username" UI) actually calls. `PATCH /me` also
takes `avatarEmoji`, which lands in the (previously unused) `avatar_url` column —
see §5. `GET /api/v1/me/stats` returns the lifetime rollup (`games_played`, `wins`,
`traitor_games`, `traitor_wins`), folded automatically by
`GameOrchestrator.updateStats` whenever a game finishes.

---

## 2a. Auth: Google Sign-In

Unlike phone/email, there's no dev bypass for this one — it calls Google for real.
The Google Web OAuth client ID is configured as the default in both the app and
backend. `GOOGLE_WEB_CLIENT_ID` (Flutter build time) and `GOOGLE_CLIENT_ID`
(backend runtime) can override it for another Google project. The client
secret is not used by this ID-token flow.

1. **Google Cloud Console** → a project → *APIs & Services* → *OAuth consent screen*
   (External is fine for testing) → *Credentials* → *Create Credentials* →
   *OAuth client ID*, three times:
   - **Web application** — no redirect URIs needed for this flow. This client ID is
     the one that matters most: it goes in *both* places below as the "audience".
   - **iOS** — bundle ID `app.truearena.truearena` (see `ios/Runner.xcodeproj`).
   - **Android** — package name `app.truearena.truearena`, plus the **debug
     keystore's SHA-1** (`keytool -list -v -keystore ~/.android/debug.keystore
     -alias androiddebugkey -storepass android -keypass android`) and, separately,
     your release keystore's SHA-1 once you have one.
2. **Backend**: `GOOGLE_CLIENT_ID` defaults to the Web client ID from step 1.
   If you override it, use the same ID in the Flutter build.
3. **App**: `GOOGLE_WEB_CLIENT_ID` defaults to that same Web client ID and is
   passed as `serverClientId`. It makes the ID token's `aud` match what the
   backend checks. To override it, build with
   `--dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>`.
4. **iOS only**: `ios/Runner/Info.plist` already has the URL scheme for the
   configured iOS OAuth client. If that client changes, update the scheme and
   `kGoogleIosClientId` together.
5. **Android**: no manifest changes needed beyond having registered the SHA-1 in
   step 1 — `google_sign_in` reads the package name from the existing manifest.
   The Android client ID itself isn't referenced anywhere in code (Android is
   matched server-side by package name + SHA-1, unlike iOS) — it just needs to
   exist in Cloud Console. Created: `26187322342-qmmsvj1ctfthu31bks1iqno5ulnpn8n5.apps.googleusercontent.com`.

**Configured clients**: iOS client ID is in `google_config.dart` and its reversed
URL scheme is in `ios/Runner/Info.plist`. Android has a registered client with
the package name and debug SHA-1. The Web client ID
`26187322342-o2squi475tmt3ubs8k9rh2d2b7pfivgf.apps.googleusercontent.com` is the default in Flutter, the backend, and the production Compose
configuration. Release Android builds need their signing SHA-1 registered too.

On first sign-in, a verified Google email can reuse an existing account with
that email. A signed-in guest with an unclaimed email is upgraded in place,
preserving its games and stats. Later sign-ins use Google's stable `sub` claim;
the email can change without creating a second account. An account already
linked to another Google subject returns a conflict.

`GoogleAuthService` verifies the ID token by calling Google's own
`GET /tokeninfo?id_token=...` (checks `aud` matches, `email_verified == true`) rather
than a local JWKS/crypto check — documented as a deliberate v1 simplification
(fine at this volume; a local JWKS check is the move if this needs to scale).

**iOS build note**: `google_sign_in_ios` doesn't support Swift Package Manager yet,
and Xcode's own SPM resolver can fail here with `Couldn't get the list of tags` even
though plain `git` works fine (network sandboxing quirk, not a real dependency
problem) — worked around with a `dependency_overrides: google_sign_in_ios: 5.7.1`
pin in `pubspec.yaml`, which forces Flutter back onto the CocoaPods path. If a
future `google_sign_in` upgrade removes the need for this, drop the override rather
than leaving it stale.

The Google OAuth round trip was exercised against the local backend and iOS
simulator with the configured clients on 2026-09-27.

## 2b. Auth: Sign in with Apple

The iOS app offers the native Apple sign-in sheet. The app first obtains a
five-minute, one-use challenge from `POST /auth/apple/challenge`, passes it as
Apple's nonce, and sends Apple's ID token to `POST /auth/apple`. The backend
checks Apple's signature, issuer, audience (`app.truearena.truearena`), expiry,
and nonce before issuing the app's normal session tokens. It links subsequent
logins by Apple's stable subject, so the user can hide or change their email.

Before a live sign-in, enable **Sign in with Apple** for the App ID with bundle
identifier `app.truearena.truearena` in Apple Developer → Certificates,
Identifiers & Profiles → Identifiers. Refresh the Xcode signing profile after
enabling it. `Runner.entitlements` already declares the capability for all
three build configurations. The backend audience defaults to the bundle ID;
set `APPLE_CLIENT_ID` only if the bundle ID changes.

The Apple button is shown on iOS only. Android keeps Google, email, and guest
sign-in. Android Apple login would require a separate web Services ID and
callback flow and is not configured here. Phone/SMS has been removed from the
app's sign-in screens for now. The backend phone OTP endpoints remain available
for future use. Email OTP still needs a delivery provider for production;
the current sender logs codes in development.

The Apple token validation and iOS simulator build are tested locally. A live
Apple account login still requires the Developer capability and a signed app.

---

## 3. Seeded test accounts

15 real accounts created in the local database for testing multi-player games — phones
`0900000001`–`0900000015`, all verified with the dev bypass code `000000`. IDs are
stable **until the Postgres volume is wiped** (`docker volume rm truearena-dev_pgdata`
or similar) — re-seed with the script below if that happens.

| Name  | Phone        | User ID (as of 2026-09-12) |
|-------|--------------|------------------------------------|
| Mara  | 0900000001   | 8ca0a002-a40e-4d08-b2bf-bc68fa575e9c |
| Ronan | 0900000002   | 4da21d98-2874-494b-a417-ef9b0260b74e |
| Priya | 0900000003   | 82ab61d2-2b33-49d2-a2d1-4c76fdbad4e1 |
| Dex   | 0900000004   | 8415120e-e690-4a5b-9cf7-3c869d18eae1 |
| Ana   | 0900000005   | b9131e69-8887-4dc6-a3c8-0dce9b3f7b11 |
| Otis  | 0900000006   | 63ce87dc-c5bb-42ce-9d6b-ba04af3eb364 |
| Kwan  | 0900000007   | 798f20e3-e46f-44b3-acf8-dfc6ac25e7b3 |
| Lena  | 0900000008   | 54d9d0a1-cfbc-4153-b3f2-54db80bba8db |
| Sam   | 0900000009   | d2b3613a-e17a-448e-be11-fc6c72087daa |
| Nia   | 0900000010   | 31dbd1ca-8dbb-4ffa-9e82-ff16b0ddb96b |
| Theo  | 0900000011   | 7799aad6-1ced-4b73-9256-30d9c977c5f5 |
| Ivy   | 0900000012   | 70cdc671-1808-47c7-9e0e-6936ce70ba98 |
| Cass  | 0900000013   | 5c78dab0-0877-426d-8ab3-573091a05a33 |
| Remy  | 0900000014   | ca6654f2-b559-4812-a24e-09115d95aa41 |
| Faye  | 0900000015   | d35913dc-e755-489a-b66d-59406cd71884 |

Classic Conspiracy (the default mode the WS layer currently hardcodes — see §6) caps at
**10 players**, so the first 10 of these (Mara–Nia) are the ones used for full-game
smoke tests; Theo–Faye are spare accounts for testing beyond that cap once mode
selection is wired up.

Re-seed script (recreates any that don't already exist — `otp/verify` is idempotent
against an existing phone, `displayName` is just ignored on repeat calls):
```bash
python3 - <<'EOF'
import json, urllib.request

names = ["Mara","Ronan","Priya","Dex","Ana","Otis","Kwan","Lena","Sam","Nia",
         "Theo","Ivy","Cass","Remy","Faye"]
base = "http://localhost:8080/api/v1/auth/otp"

def post(path, body):
    req = urllib.request.Request(base + path, data=json.dumps(body).encode(),
                                  headers={"content-type": "application/json"}, method="POST")
    with urllib.request.urlopen(req) as r:
        data = r.read()
        return json.loads(data) if data else None

for i, name in enumerate(names, start=1):
    phone = f"0900000{i:03d}"
    post("/request", {"phone": phone})
    res = post("/verify", {"phone": phone, "code": "000000", "displayName": name})
    print(name, phone, res["user"]["id"])
EOF
```

---

## 4. WebSocket smoke test

`backend/dev-tools/ws-smoke-test.mjs` — a Node.js script (needs Node's native
`WebSocket` global, i.e. Node ≥ 22) that drives a **real** multi-player game end-to-end
over `/ws/room/{roomId}`: signs in N seeded accounts, creates a room, connects all of
them, starts the game, bot-plays night targets and votes through to `GAME_OVER`, and
asserts no client ever receives another player's un-revealed role. This is the
transport-layer counterpart to the engine's own `SecretDataGuaranteeTest` — use it
whenever `GameOrchestrator`, `RoomLock`, or `RoomEventLog` change.

```bash
cd backend/dev-tools
node ws-smoke-test.mjs          # normal run
DEBUG=1 node ws-smoke-test.mjs  # logs every frame sent/received
```
Requires the backend running locally first (§1). Edit `SEED_PHONES` at the top of the
file to change which/how many of the seeded accounts (§3) play.

`backend/dev-tools/chat-smoke-test.mjs` — the same idea, scoped to discussion chat
(§4a below): drives a real game to `RoundTable` and holds it there (doesn't
auto-advance), sends on both channels, and asserts table messages reach everyone,
`traitors`-channel messages reach only traitors (zero leaks to faithful), a faithful
sending to `traitors` gets `NOT_TRAITOR`, and chat during `Vote` gets `WRONG_PHASE`.

---

## 4a. Discussion chat (`CHAT_SEND` / `CHAT_MESSAGE`)

Built 2026-09-13, reusing the transport rather than adding a new one: `CHAT_SEND`
(client→server, added to `MessageType`) carries `{channel: "table"|"traitors", text}`;
`GameOrchestrator.handleChat` validates (phase must be `RoundTable`, `traitors`
requires the sender's role — from the same `rt.roleByUser()` map the WS layer already
maintains for `GameEvent` role-scoping — to actually be traitor-ish) and pushes a
`ChatMessage` (`ta-room`) onto the room's existing `rt.bus`. `GameOrchestrator.toEnvelope`
gets one more branch: a `traitors`-channel message is filtered out for any viewer whose
role doesn't match, via the *exact same* `roleGroupMatches` helper the secret-data
guarantee already uses for engine events — chat rides the one tested visibility path
rather than a second one. Delivered to clients as an ordinary `EVENT` frame,
`type: "CHAT_MESSAGE"`, `data: {channel, from, text, ts}`.

**Deliberately ephemeral (v1 simplification):** unlike `GameEvent`s, a `ChatMessage`
is never appended to `RoomEventLog`/Postgres. It only exists on the live `bus` — a
client that reconnects mid-discussion gets the game snapshot back, not the chat
transcript, and the Flutter side (`GameScreen._tableChat`/`_traitorChat`) clears its
own lists the moment the phase leaves `RoundTable`. If persisted chat history is ever
wanted, it needs its own Redis list (or table) — don't retrofit it into `RoomEventLog`,
whose `seq` numbering is load-bearing for the engine's own replay-after-`lastSeq` logic.

Frontend: the chat panel lives inside `GameScreen._roundTable` only (`_chatPanel`) — a
collapsible bar at the bottom of the RoundTable phase screen, tab-switching between
"Table" and "Traitors" (the Traitors tab only rendered at all if `isTraitor` — the
backend enforces it either way, this just avoids showing a faithful player an option
that would 403). No chat UI exists for any other phase; there is none to build for
Vote, since the backend already refuses `CHAT_SEND` outside `RoundTable`.

## 5. Frontend reusable tokens (`app/lib/theme/neon_theme.dart`, `app/lib/widgets/neon.dart`)

**Fonts**: Baloo 2 (display/headings — rounded, playful) + Archivo (body). Both via
`google_fonts`.

**Corner radii** (`NeonRadius`):
- `pill` (999) — buttons, chips, segmented controls, small badges. Everything tappable
  and small is a stadium shape.
- `blob(mirror: bool)` — the asymmetric rounded-corner shape every `NeonCard` uses
  instead of a plain rectangle (two opposite corners rounder than the other two).
  Alternate `mirror: true`/`false` across a grid/list so cards don't all lean the same
  way — see `mode_select_screen.dart`'s `_card(p, mirror: i.isOdd)`.
- `card` (22) / `control` (16) / `chip` (14) — plain circular-radius fallbacks, mostly
  superseded by `blob`/`pill` now.

**Button styles** (`NeonStyle`, in `NeonButton`) — solid fills, no gradients:
- `go` → solid **magenta** (`n.magenta`) — the main call-to-action color across the app
  (sign in, save, start). Chosen deliberately over the earlier acid-green default.
- `cyan` → solid cyan — secondary actions.
- `danger` → solid pure **red** (`n.danger`) — destructive actions only, kept distinct
  from `go`'s magenta.
- `ghost` → outline only, cyan.

**Interaction**: every tappable shape runs through `Bouncy` (`widgets/neon.dart`) —
press-scale + hover-scale + pointer cursor. Used by `NeonCard`, `NeonChip`,
`NeonSegmented`, the stepper buttons, and the settings preset-icon tiles. `NeonButton`
has its own hand-rolled version of the same idea (adds glow-intensity changes on
press/hover). Reach for `Bouncy` first for any new tappable widget rather than a bare
`GestureDetector`/`InkWell`.

**Avatar presets** (`kAvatarPresets`, 15 total, in `widgets/neon.dart`):
```
🦊 🐺 🎭 🕵️ 🦁 🐸 🦄 🐙 🦉 🐲   (mascots)
👺 👽 🥷 😈                      (traitor-flavored)
😇                               (faithful-flavored)
```
Rendered via `Avatar(name, emoji: ..., imagePath: ...)` — `imagePath` (an uploaded
photo, via `image_picker`) wins over `emoji`, which wins over the initials fallback.
Both are still local-first prefs on `AppState` (`avatarEmoji`/`avatarImagePath` via
`SharedPreferences`, for instant UI + guest support), but **as of V5 (2026-09-13) a
preset emoji is also synced server-side** — `setAvatarEmoji` fires a best-effort
`PATCH /me` and `bootstrap()` prefers the server's `avatarUrl` on next login, so the
choice follows a signed-in user to another device. An **uploaded photo stays
device-local only** — there's no file storage service to upload it to yet, so
`avatarImagePath` never leaves the phone. `avatar_url` holds a bare emoji today; a
real URL is what it'll hold once photo upload has somewhere to land.

**Welcome-screen decoration**: `_BlobField` in `welcome_screen.dart` — three softly
blurred (`ImageFilter.blur`, sigma 70) solid-color circles behind the hero content.
Reusable pattern if another screen wants the same "playful, not sleek" background
treatment without repeating the blur setup.

---

## 6. Games catalog (multi-game structure)

`app/lib/features/games/game_select_screen.dart` defines `GameCatalogEntry` /
`gameCatalog` — the list Home's "New game" grid renders. TrueArena's social-deduction
engine ("Traitors") and Word Bluff are both `available: true`; two more entries exist as
`available: false` ("coming soon") placeholders so the grid doesn't look like a
two-item list. **Adding a real game means adding a new `GameCatalogEntry` here and
wiring its own lobby/game-screen flow — this screen was built specifically so that
doesn't require touching Home or Settings**, and Word Bluff (§8) is the proof: it
routes straight to `WordBluffLobbyScreen` instead of through `ModeSelectScreen`.

Tapping the Traitors tile still opens the existing `ModeSelectScreen` (the 5 GameConfig
presets: Classic Conspiracy, Midnight Heist, Blood Moon, The Last Alibi, Final Gambit —
see `docs/GAME_CONFIG.md`). There is currently **no lobby-side UI to pick a
non-default mode** — `GameOrchestrator.handleGameStart` on the backend always uses
`Presets.CLASSIC_CONSPIRACY` regardless of what's shown in `ModeSelectScreen`. That's a
known gap, tracked in `PROJECT_PLAN.md` Phase 4.

---

## 7. Notable build decisions (read before changing these areas)

- **One engine, many "modes"**: TrueArena is *the* social-deduction engine. The 5
  shipped modes (Classic Conspiracy, etc.) are **data**, not code — `GameConfig`
  presets stored as `game_config_preset` rows. The 12 "twists" (Poisoned Gift, Double
  Agent, …) are a **fixed enumerable catalog** (`TwistRegistry`), not arbitrary
  scripting. See `docs/GAME_CONFIG.md`. Future games are separate `GameModule`
  implementations behind the same generic WS transport, not new configs of this engine.

- **Phase 4 WebSocket transport ships with three deliberate v1 simplifications**
  (documented in `PROJECT_PLAN.md` Phase 4, not silent gaps):
  1. Room state lives **in-process per pod** (`RoomRuntime`/`RoomRuntimeRegistry`), not
     serialized to Redis — fine for one `ta-app` instance, breaks on multi-pod deploy
     without adding state rehydration.
  2. Auth **reuses the existing REST access JWT** as a `?token=` query param instead of
     a separate Redis session token.
  3. Phase timers are in-process `Mono.delay(...)`, not Redis keyspace-notification +
     sweep — a timer is lost if its pod restarts mid-phase.

- **`RoomLock.withLock` bug (fixed 2026-09-11)**: the original
  `.flatMap(result -> release(key)...)` success path never fired for a `Mono<Void>`
  action (no `onNext` on empty completion) — so `GAME_START`/`PLAYER_ACTION`/timer
  elapses never released the Redis lock, and every action after the first silently
  timed out after 5s with no error surfaced to the client. Fixed with a
  `.switchIfEmpty(...)` release path. **If a lock-based mutation on `RoomRuntime` ever
  seems to "just hang," check this pattern first** — it's an easy mistake to
  reintroduce in similar `Mono<Void>`-returning lock wrappers.

- **Backend build is Maven**, not Gradle (migrated early; don't reintroduce
  `.gradle.kts` files). Multi-module reactor: `ta-engine` → `ta-game-truearena` →
  `ta-persistence` / `ta-room` / `ta-ws` → `ta-api` → `ta-app`.

- **Guest identity**: a temporary guest is identified by device ID and gets exactly one
  game; everything about them clears afterward unless they verify a phone (preferred)
  or email. There is no "PIN" auth anywhere in this system — only phone + 6-digit OTP.

- **"Admin" = whoever starts the game, and only a registered account can be one** —
  confirmed already enforced end-to-end, not something to build: `POST /api/v1/rooms`
  (which sets the caller as `hostId`) requires a valid access JWT (401 without one);
  `/ws/room/{id}` closes with code 4401 for a missing/invalid token even though the
  path itself is public, and separately checks room membership; `GAME_START` is
  host-only against that same authenticated `hostId`, never client-supplied. A guest
  has no JWT, so the Flutter app's guest lobby is a local-only mock — its Start button
  never reaches a real room.

- **Gameplay audit (2026-09-13) — what the engine actually implements vs. what's just
  config surface.** Read this before assuming a config field or twist "does something":
  the core phase loop (roles → night kill → round table → vote → tie/AFK handling →
  elimination → veiled endgame → win check → results) is solid and now has dedicated
  outcome coverage in `GameOutcomesCoverageTest` (see below). Everything past that is
  **registered and validated, but has no behavioral code**:
  - **11 of the 12 twists are metadata-only.** Only `hidden_legacy` (the recruit
    mechanic) is wired into `TrueArenaModule`. Poisoned Gift & the Shield, Secret
    Accusation, Blackmail, Double Agent, Last Will, Confessional, Immunity Coin, Silent
    Witness, False Reveal, Trial of Two, and Survivors' Choice all pass
    `ConfigValidator` and can be toggled from the setup screen, but toggling them
    changes nothing about how a game plays. Implementing one means adding real branches
    in `TrueArenaModule`, not just leaving it registered in `TwistRegistry`.
  - **`hidden_legacy` isn't enabled by any of the 5 shipped presets.** It only fires on
    a custom/admin config that explicitly turns it on — every default game is playing
    without it.
  - **`tieBreak` has one real behavior, not six.** `no_elimination` is genuinely
    distinct (skips the banish). Every other value — `revote`, `random`,
    `sudden_death`, `host_decides`, `trial_of_two` — collapses to the exact same
    seeded-random pick among the tied players (`TrueArenaModule.tallyAndBanish`). There
    is no revote round, no sudden-death timer, no host-decides prompt, and no
    trial-of-two defense window. `secondTie` (a second-level tie rule) is validated but
    never read at all.
  - **Blood Moon's headline mechanic doesn't exist.** `NightKill.doubleAfterRound`
    (the "double murder" after a given round) is validated and stored but never read
    by `resolveNight` — every preset, Blood Moon included, only ever kills one player
    per night.
  - **`afk: host_assigns` behaves identically to `abstain`.** `closeVoting` emits a
    different event name (`AFK_PENDING` vs `AFK_ABSTAINED`) but there's no
    `PLAYER_ACTION` for a host to actually assign a missing vote — both configs just
    auto-abstain the missing voters. Every shipped preset hardcodes `afk: "abstain"`
    anyway (see `Presets.cfg`), so this has never been reachable from a real game.
  - **`voteReveal` (`sequential` vs `all_at_once`) is validated but never read.**
    `VoteReview` always behaves the same way regardless of this field: reveal-on-demand
    via `REVEAL_NEXT`, or reveal-all when the host advances the phase directly.
  - **`GameOutcomesCoverageTest`** (`ta-game-truearena`) is the test suite written
    against this audit — one scenario per implemented mechanic (both win conditions,
    hidden_legacy's recruit, all three `revealOnElimination` policies, `no_elimination`
    vs. every other tie rule, AFK auto-abstain, the veiled endgame, and the
    `RuleViolation`s a client can trigger), each driven with hand-picked actions rather
    than random bots so a failure points at the exact mechanic that broke. It
    deliberately does not assert anything about the gaps above — there's no code there
    to test yet.

---

## 8. Word Bluff — second game type (built, wired end-to-end)

`ta-game-wordbluff` is a sibling Maven module (same pattern as `ta-game-truearena`:
parent `truearena-backend`, one dependency on `ta-engine`) implementing a Catch
Phrase / Heads Up-style party game: 2 teams of 2+ take turns spinning a 20-category
wheel, revealing a word, and racing a shared clock (default 60s) to get their team to
guess it — describer can `SKIP` a hard word — before the other team's turn. First team
to a target score (default 30) wins. Playable end-to-end today: `POST /api/v1/rooms`
with `gameType: "wordbluff"` → the same `/ws/room/{id}` lobby/game socket TrueArena
uses → the Flutter app's `WordBluffLobbyScreen`/`WordBluffGameScreen`.

- **`GameConfig` is now genericized — `WordBluffModule` is a real `GameModule`.**
  Rather than the full record-to-interface rename originally scoped (~18 files), the
  lighter fix was a new empty marker interface `app.truearena.engine.GameSettings`;
  `GameConfig implements GameSettings` (TrueArena keeps its own type and all its
  concrete-field call sites untouched), `WordBluffConfig implements GameSettings`, and
  `GameModule.definePhases`/`initialState` now take `GameSettings` instead of
  `GameConfig` — each module casts back to its own concrete type on the first line of
  those two methods. `RoomRuntime.config` is typed `GameSettings` too. This is the
  one-line-per-file version of the deferred refactor noted below (kept for history):
  genericizing `GameConfig` into a marker interface was originally scoped as an ~18-file
  rename (`TrueArenaConfig implements GameConfig`) across `ta-engine`,
  `ta-game-truearena` (incl. tests), `ta-persistence`, `ta-api`, `ta-room`, `ta-app` —
  the `GameSettings`-interface approach got the same result touching only 6 files.
- **Room routing**: `rooms.game_type` (migration `V6__wordbluff.sql`, default
  `'truearena'`, CHECK `IN ('truearena', 'wordbluff')`) is set at room creation
  (`POST /api/v1/rooms` body: `{ groupId?, gameType? }`) and read by
  `GameOrchestrator.handleGameStart`, which branches to `startTrueArena` or
  `startWordBluff` — each builds its own config, module, and initial state, then shares
  the same `afterMutation`/event-log/timer/finish pipeline. Word Bluff sessions skip
  `ConfigValidator` (TrueArena-only) and the `roles` table (teams are public state, not
  secret roles — see `commonView` below) — `recomputeRoles`/`updateStats` no-op cleanly
  for it since they key off a `players`/`yourRole` shape Word Bluff's broadcast doesn't
  have. `game_results.winning_side`'s CHECK was widened to also allow `'A'`/`'B'`.
- **Rules**: min 4 players (2v2), enforced as a hard `NOT_ENOUGH_PLAYERS` `RuleViolation`
  (no 2-player mode, unlike TrueArena's presets — the user chose "require ≥4" over
  supporting heads-up-style solo play). Players shuffle-split alternately into
  `TEAM_A`/`TEAM_B` at game start. Each team rotates its own describer index
  independently, so a team's next describer is always "whoever's turn it is on that
  team," not tied to the other team's rotation.
- **Categories & word banks**: 20 categories (`Category` enum) — 19 backed by
  `src/main/resources/wordbank/<slug>.txt` (one word/phrase per line, hand-authored,
  ~90-100 words each for v1 — **not scraped**, despite an early ask to "go online and
  collect"; there's no reliable bulk-scraping capability in this environment, so I said
  so rather than silently substituting authored content while implying otherwise), plus
  `MIXED` (20th wheel slot, no file — computed as the deduplicated union of the other
  19, cached in `WordBank`). Growing any category toward the user's stated "up to 500"
  aspiration is just adding more lines to its `.txt` file — zero code changes.
- **No-repeat guarantee**: a single flat `usedWords` set on `WordBluffState` (not
  per-category) — a specific word never comes up twice in one game session regardless
  of which category (`MIXED` included) it was drawn from, though a category itself can
  land on the wheel repeatedly. If a category's own pool is exhausted mid-game,
  `pickUnusedWord` falls back to the full cross-category `MIXED` pool rather than force
  a repeat; if that's exhausted too (all ~1,700+ words used in one game — unlikely at
  current pool sizes but possible as a stress case) it throws `WORD_POOL_EXHAUSTED`
  rather than silently repeating.
- **Secrecy**: `currentWord` is revealed only to the current describer, via
  `GameEvent.toPlayer(...)` (same visibility-scoping mechanism as TrueArena's role
  secrecy) and `visibleStateFor` only ever adding `yourWord` when
  `playerId.equals(currentDescriber())`. Covered by `SecretWordGuaranteeTest`, mirroring
  `SecretDataGuaranteeTest`'s rigor for TrueArena.
- **Bug fixed while building this**: `WordBank.wordsFor` originally used
  `CACHE.computeIfAbsent(category, WordBank::load)`, but `load(MIXED)` recursively calls
  `wordsFor(...)` on the other 19 categories — a `computeIfAbsent` re-entering the same
  map throws `ConcurrentModificationException`. Fixed by replacing it with a plain
  `get`-then-`put` (correctness over the theoretical race, fine for this read-mostly
  cache).
- **Tests** (48 total across three files): `WordBluffEngineTest` (happy-path end-to-end
  flows — min-player enforcement, team split, turn-ownership `RuleViolation`s,
  spin/reveal/correct/skip scoring, turn-end rotation, win-at-target,
  no-repeat-within-session across ~150 draws); `SecretWordGuaranteeTest` (audits every
  view/broadcast/event after every action across 40 random-seeded full games for
  `currentWord` leakage); and `WordBluffCoverageTest` (39 tests, one scenario per
  branch, same discipline as `GameOutcomesCoverageTest` in `ta-game-truearena`) —
  every `RuleViolation` code (`NOT_ENOUGH_PLAYERS`, `NOT_YOUR_TURN`, `ALREADY_SPUN`,
  `WRONG_PHASE`, `NO_PENDING_SPIN`, `ALREADY_REVEALED`, `NO_ACTIVE_WORD`,
  `WORD_POOL_EXHAUSTED`, `UNKNOWN_ACTION`, `BAD_PHASE`), team-split parity for odd and
  even player counts, the untimed `TurnEnd` phase waiting on an explicit host
  `ADVANCE_PHASE`, describer rotation being per-team (not shared), an early host advance
  abandoning an in-progress word without scoring it, action-id idempotency and
  post-`Results` no-ops for both `onPlayerAction`/`onPhaseElapsed`, win/`WinResult`
  correctness, and the `visibleStateFor`/`broadcastState`/`drainEvents` contracts.
  `wordPoolExhaustionThrowsRatherThanRepeating` is a genuine stress test, not a mock —
  it drives one describer through every one of the ~1,823 unique words in the real
  banks (via `WordBank.wordsFor(Category.MIXED).size()`) before asserting the next
  reveal throws, so it will need updating if the word banks ever shrink below what a
  single turn's `SPIN`/`REVEAL`/`SKIP` loop can exhaust in reasonable test time.
- **Flutter**: `app/lib/features/wordbluff/wordbluff_lobby_screen.dart` and
  `wordbluff_game_screen.dart` mirror `LobbyScreen`/`GameScreen`'s shape (same
  SNAPSHOT/PHASE/EVENT-in, PLAYER_ACTION-out contract over the same `GameSocket`) rather
  than sharing code with them — Word Bluff has no `ModePreset`/twist config, and its
  phase set (`Turn` → `TurnEnd` → `Results`) and events (`GAME_STARTED`, `TURN_STARTED`,
  `CATEGORY_LANDED`, `WORD_REVEALED`, `WORD_RESOLVED`, `TURN_ENDED`, `GAME_OVER`) are
  different enough that forcing a shared screen would've meant more branching than
  duplication saved. The category wheel is a `CustomPainter` (`_WheelPainter`) with a
  fixed top pointer; `_settleWheel` computes the rotation landing a given category slug
  there — its 20-entry `_kCategories` list order must stay in sync with the backend
  `Category` enum's declaration order (a mismatch would visually land the wheel on the
  wrong slice while still describing the right word, since routing runs on the slug, not
  wheel position — cosmetic, not a real bug, but worth fixing if the two ever drift).
  `game_select_screen.dart`'s `bluff` catalog entry is now `available: true`.

---

## 9. Draughts — the third game type (1v1, International rules)

`ta-game-draughts` (new module, same shape as the other two): International
Draughts — 10x10 board, 20 pieces/side, mandatory-maximum capture, flying
kings. `Board`/`Piece` are the coordinate/cell primitives; `CaptureEngine` is
the whole rules engine as pure functions over a `Piece[50]` (no state, no
events) — `requiredCaptureCount` is the board-wide max-capture-length that
makes a capture mandatory *and* picks which one; `maxCaptureCount` is the
recursive per-square lookahead that backs it. `DraughtsModule` ties that to
the usual `GameState`/events/`GameSettings` shape — nothing is secret here
(both players always see the whole board), so `visibleStateFor` and
`broadcastState` are identical, unlike TrueArena/Word Bluff. Per-turn timers
actually reset because the phase name itself encodes whose turn it is
(`TurnA`/`TurnB`, not one shared `"Turn"`) — see the comment on
`DraughtsState.phase` for why that's load-bearing, not cosmetic. Flutter:
`draughts_rules.dart` is a second, Dart-side port of `CaptureEngine` purely
for the client's tap-to-move highlighting (the WS transport only pushes
discrete events after the first snapshot, not fresh snapshots, so trusting a
snapshot-only server field would go stale mid-game) — the server stays the
sole authority regardless, so a bug in the Dart port could only ever
mis-highlight, never produce a wrong outcome. 56 Java tests + 8 Dart tests
cover both copies.

### AI agents ("bots")

A bot uses one of the reusable system `users` rows seeded by migration V30
and gets a room-local `room_members` row. `POST /rooms/{id}/bots` is
host-only and lobby-only; the request supplies the name and difficulty for
that Huud. There is no player-owned inventory to create, rename, delete, or
lock. The same pool identity may serve simultaneous rooms because membership
preferences and `BotRuntimeRegistry` keys are scoped by `(roomId, botId)`.
Each runtime gets its own JWT and connects to `/ws/room/{id}` **exactly like
the Flutter app does**. `BotRuntime` knows nothing about any game's rules; it
relays inbound frames to a `GameBotAdapter` and sends back the resulting
`PlayerAction`.

- **Per-game adapter, not a shared one.** `GameBotAdapter` is a small,
  *stateful* interface (`onFrame`/`parseAction`/`fallbackAction`) — one fresh
  instance per room seat (`GameBotAdapterFactory`), since it has to track
  state itself from raw events (no different from the Flutter client's own
  state-tracking). All three games have an adapter now:
  - `DraughtsBotAdapter` reuses the **real** `ta-game-draughts`
    `CaptureEngine` directly (same JVM, no reason to port the rules a third
    time), unlike the Flutter client which necessarily has its own Dart copy.
  - `TrueArenaBotAdapter` tracks its own role, fellow Traitors, and the
    alive list off the per-player SNAPSHOT/EVENT frames the orchestrator
    already scopes to that bot's own connection; it only ever has something
    to submit during `Night` (a living Traitor picks a kill target, never a
    fellow Traitor) and `Vote` (any living player votes, never itself) —
    every other phase is host-advanced or automatic, so the bot stays quiet.
  - `WordBluffBotAdapter` has an honest, load-bearing limitation: **a bot
    can't speak a verbal description**, so it can never legitimately score
    as describer. When it's the bot's turn to describe, it cycles
    SPIN → REVEAL → SKIP so the game never stalls on its turn, but it
    never submits `MARK_CORRECT`. As a guesser it has nothing to submit at
    all — guessing in this game happens by voice, judged by the human
    describer — so a Word Bluff bot is effectively a seat-filler that
    contributes zero points either way. Tell users this plainly; it isn't
    hidden or silently degraded.
  - All three share one discipline worth calling out: a bare `PHASE` frame
    arrives **before** the domain `EVENT`s describing what just changed
    (`GameOrchestrator.afterMutation` calls `broadcastPhase()` synchronously
    while the event-log-append-and-broadcast `Mono` is still unsubscribed) —
    every adapter tracks the phase name off a `PHASE` frame but only ever
    *decides* an action once a following `EVENT` (or a fresh `SNAPSHOT`)
    confirms local state is caught up. Skipping this caused a real bug during
    development (`DraughtsBotAdapter` briefly decided moves off stale board
    state) — see the tests asserting a bare `PHASE` frame alone never
    produces a prompt.
- **LLM calls go through `LlmMovePicker`** (swappable bean, `BotLlmConfig`).
  `GroqMovePicker` (free tier, no card, at console.groq.com) is now wired in
  and becomes the active bean automatically once `GROQ_API_KEY` is set
  (`llama-3.1-8b-instant` for Easy/Medium, `llama-3.3-70b-versatile` for
  Hard). Leaving it unset keeps `StubMovePicker` active — it always returns
  `""`, routing every bot decision through `GameBotAdapter.fallbackAction`
  (a random legal move) instead. This was deliberate: the whole pipeline —
  bot creation, WS connection, auto-ready, turn detection, prompt building,
  the parse-or-fallback path, sending the action, and the illegal-move
  retry — was built and verified end-to-end with the stub (plus a manual
  live run over real WS: a real human move handed the turn to a bot, which
  replied with a legal move within milliseconds) *before* wiring in a real
  model, so a bad/failed API call degrades to "plays randomly" rather than
  stalling a game.
- **Difficulty (Easy/Medium/Hard, shown to players as Amateur/Pro/Legend)**
  is threaded through to the picker/prompt as a plain enum
  (`app.truearena.api.bot.Difficulty`) — the intended design (not yet
  exercised, since the stub never really calls a model) is a cheaper
  model + bare prompt for Easy, and the strongest model + fuller strategic
  prompt (multi-ply lookahead described in text) for Hard, rather than a
  separate search engine per level.
- **Mandatory-capture retry loop**: if the model (or its fallback) proposes
  an illegal move, the server rejects it with a normal `RuleViolation` →
  `ERROR` frame; `BotRuntime` catches that specifically and immediately
  tries `fallbackAction` once more so a bad model response can never stall
  the game.
- **Runtime lifecycle**: a bot's `BotRuntime`
  doesn't survive a server restart (no reconnect-on-crash — same in-memory,
  single-pod scope as `RoomRuntime`/`RoomRuntimeRegistry`, see §7); a bot
  never signs in and has no phone/email (`users.is_bot` widens the same
  contact-method CHECK guest accounts use). Removing a bot or ending/exiting
  its table stops only that room's runtime and deletes the membership; the
  reusable system identity remains available to every room.
- **Flutter**: every supported game's lobby shares one `AddCyberAgentSheet`
  (`widgets/cyber_agent_sheet.dart`) — an "Add a Cyber Agent" button
  (host-only, hidden once the room is full or in example/guest mode) opens a
  name + difficulty (Amateur/Pro/Legend) sheet, then `POST`s straight to the
  bot endpoint. It does not fetch or manage a saved roster. As many bots as
  there are open seats can be added this way —
  Draughts caps at exactly two players so the button disappears once full;
  TrueArena/Word Bluff allow adding one at a time up to the room's player
  cap. A bot shows up in the roster like any other member (already ready,
  tagged with a small 🤖 badge and a "CYBER AGENT" label) via the lobby's
  existing SNAPSHOT/EVENT stream — no bot-specific WS handling needed
  client-side.

## Whot player flow

Whot is enabled in the game picker. Verified hosts choose house rules and create
an unstaked room; friends join through the existing room-code or invitation flow.
The game table supports 2–20 players, a private scrolling hand, dealer shuffle/deal/
start controls, matching-card selection, wild-card shape choice, pick-two penalties,
turn countdowns, pause/resume, reconnection, and a winner restored from snapshots.
Cyber Agents are available for Whot Classic. The Tell remains human-only
because its private signal agreement and real-time calls require people.

The server sends each player an authoritative private snapshot after every action.
The UI never reconstructs a hand from public events. Turn timers are keyed by phase
and round; hold-on increments the round even when the same player plays again.
This prevents the first timer expiration from leaving subsequent turns untimed.

Whot's market is a fixed shuffled stack: each draw takes the next stored card.
When the last card is drawn, the server shuffles the discard cards into a new
market, keeps the current top discard in play, and emits `MARKET_RESHUFFLED`.
Snapshots expose market/discard counts and the last three face-up discard cards
for the table's stack display; they never expose the market order.

Whot offers two modes, **Classic** (individual play) and **The Tell** (teams
on the same Whot engine). The Tell supports 4, 6, or 8 human players, 30
private signal choices, three-second public signals with tap-to-buzz, and
server-ordered qualification and finals. The host configures Same Value,
Same Shape, or Either for Tell matching and a 2–12 card minimum (default 3).
The server redeals any initial hand that already satisfies the Tell rule.
See [WHOT_THE_TELL.md](WHOT_THE_TELL.md).

Verification:

```sh
cd app
flutter test test/whot_game_test.dart
cd ../backend
./mvnw -pl ta-api -am test -Dtest=WhotModuleTest,WhotSpecialsTest,WhotTurnTimerTest -Dsurefire.failIfNoSpecifiedTests=false
cd ..
WHOT_BASE=http://localhost:8081 node backend/dev-tools/whot-smoke-test.mjs
```

The smoke test requires Node with native WebSocket support and a local-profile
backend connected to development Postgres and Redis. It uses reserved test accounts
0900088801–0900088803 and the local OTP bypass (no SMS request), creates an unstaked
room, verifies two consecutive automatic timeouts, reconnects a player, plays to
Results, and checks spectator privacy and consistent winners. It refuses remote
hosts and leaves the completed test game in the development database.
