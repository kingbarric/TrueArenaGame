# SlayHuud — V1 Development Plan

> Status: **initial design reference** from the SlayHuud V1 product note. Implementation has begun on `codex/slayhuud`; see [SLAYHUUD_IMPLEMENTATION.md](SLAYHUUD_IMPLEMENTATION.md) for the actual architecture, completed work and remaining asset/launch gates.
> Rendering decision: **real-time 3D** (Three.js in a WebView), with every submitted look
> also saved as an image for voting, Huud and sharing.
>
> Written against the codebase as of `9d592e5`. Where this plan says "reuse", the
> existing table/service is named; where something doesn't exist yet, it says so.

---

## 0. What already exists vs what's new

| Need (from the note) | Exists today | Plan |
|---|---|---|
| Auth, users, guests | `users`, guest accounts (V7) | Reuse |
| Rooms, timers, live WS | `ta-engine` `GameModule`, `ta-room`, `/ws/room/{id}`, Redis phase timers | Reuse for live modes (Style Battle, Slay or Pass, live group) |
| Competitive rating | `player_game_ratings` (Glicko-2, per `game_type`), `PairwiseOutcomes` already turns a multi-player placement into pairwise results | Reuse with `game_type = 'slayhuud'` — this *is* a separate Slay rating, not Chess's |
| Match history, stats | `match_records`, `match_participants`, `player_game_stats` | Reuse; SlayHuud results write here so profile cards and Huud win cards work unchanged |
| Leaderboards global / country | `LeaderboardService` over `player_game_ratings` | Reuse |
| Achievements / badges | `player_achievements` + `AchievementType` catalog in code | Reuse; add Slay achievement types |
| Coins | `users.coins` + `coin_transactions` ledger | Reuse |
| Huud posts (game request, challenge) | `huud_posts` → always backed by a real lobby room | Reuse; add `slayhuud` to seat/label maps |
| Tournaments | `championships` (1v1 knockout, size 4/8/16/32) | Reuse for knockout Style Battle; needs per-round themes + bigger sizes |
| Push notifications | `device_tokens`, `PushNotificationService` | Reuse |
| Spectating | `features/spectate` | Reuse for live battle spectators who vote |
| **Block / report** | **Not found** — no tables or services | **New, generic** (not Slay-specific) |
| **File / image storage** | **Not found** — avatars are emoji presets, no upload path | **New** — needed for look snapshots |
| **Player gender** | **Not stored** on `users` | Decision needed (§13) |
| **WebView / 3D** | No WebView or 3D package in the app | **New** |

Note: [ARCHITECTURE.md](ARCHITECTURE.md) predates most current games; the code is the truth.

---

## 1. Proposed architecture

```
Flutter app
 ├─ features/slayhuud/            screens, state, API client, bridge
 │    └─ SlayStage (WebView) ───► slay-renderer (Three.js, bundled in app)
 │                                  └─ GLB/KTX2 assets from CDN (cached)
 │
 ├─ existing: huud, competitive, spectate, wallet, notifications
 │
Backend (Spring Boot / WebFlux)
 ├─ ta-game-slayhuud   (NEW) GameModule for live modes + pure scoring/ranking code
 ├─ ta-api/slay/       (NEW) catalog, wardrobe, looks, challenges, ballots, results
 ├─ ta-api existing:   rooms, huud, competitive (rating), championships, coins, push
 └─ Postgres (new slay_* tables) · Redis (live room state) · object storage (snapshots)
```

**Split of responsibility**

| Layer | Owns |
|---|---|
| **Flutter** | Navigation, auth, wardrobe/theme UI, timers, the *outfit state* (source of truth on device), submit, voting screens, results, Huud, profile |
| **Three.js renderer** | Drawing only: avatar, garments, hair, lighting, camera, poses, snapshot to PNG. Holds no game state |
| **Backend** | Item catalog, wardrobe ownership, look records, scoring, competitions, ballots and votes, results, rewards, rating, tournaments |

**Two kinds of competition, one data model**

- **Live** (Style Battle, Slay or Pass, live group): a normal room running
  `ta-game-slayhuud`. The room handles presence, the styling timer, reveal and judging phases.
- **Async** (daily/weekly challenges, community voting after a battle): no room. A
  scheduler opens and closes windows; voting happens through the ballot API.

Both write to the same `slay_competitions` / `slay_entries` tables, so results,
rewards, rating and Huud cards are produced once by one code path.

**Server never trusts the client's score.** A look is submitted as item IDs; the
server computes the system score from the catalog. The snapshot image is for display
only.

---

## 2. New DB models

All in one Flyway migration (next free number at implementation time — check prod
Flyway state first). Item and theme *catalogs* live as JSON in the repo and are synced
to tables on boot (same pattern as builtin `game_config_preset` rows), so content
ships through code review and stays versioned.

| Table | Key columns | Notes |
|---|---|---|
| `slay_items` | `id` (slug), `name`, `category`, `body` (`male`/`female`/`unisex`), `rarity`, `style_tags[]`, `colour_tags[]`, `culture_tags[]`, `event_tags[]`, `asset_path`, `thumb_path`, `hides_regions[]`, `unlock_rule` JSONB, `coin_cost`, `is_default`, `is_limited`, `catalog_version`, `active` | Synced from `slay/catalog/*.json` |
| `slay_themes` | `id`, `title`, `description`, `body_eligibility`, `required_categories[]`, `optional_categories[]`, `colour_theme`, `style_tags[]`, `budget`, `scoring` JSONB (weights + rules) | Reusable theme templates, synced from repo |
| `slay_avatars` | `user_id` PK, `body`, `skin_tone`, `face_preset`, `updated_at` | Player's base avatar |
| `slay_wardrobe` | `user_id`, `item_id`, `source` (`default`/`purchase`/`reward`/`achievement`), `ref_id`, `acquired_at` | PK `(user_id, item_id)` |
| `slay_looks` | `id`, `user_id`, `body`, `skin_tone`, `face_preset`, `items` JSONB (slot → item + colourway), `pose`, `background`, `snapshot_url`, `catalog_version`, `created_at` | Immutable once submitted |
| `slay_competitions` | `id`, `mode` (`solo`/`battle`/`group`/`slay_or_pass`/`daily`/`weekly`/`client`), `theme_id`, `room_id` NULL, `championship_match_id` NULL, `status`, `config` JSONB (time limit, weights, min votes, rewards, seats), `opens_at`, `closes_at`, `voting_closes_at`, `resulted_at`, `ranked` | One row per contest |
| `slay_rounds` | `competition_id`, `round`, `theme_id`, `status` | Slay or Pass and tournament themes per round |
| `slay_entries` | `id`, `competition_id`, `user_id`, `look_id`, `round`, `system_score`, `community_score`, `final_score`, `placement`, `eliminated_round`, `votes_for`, `votes_against` | `UNIQUE (competition_id, user_id, round)` |
| `slay_ballots` | `id`, `competition_id`, `voter_id`, `entry_a`, `entry_b`, `kind` (`pair`/`slay_pass`), `served_at`, `answered_at`, `choice`, `weight`, `flags` | Server-issued; the client can only answer what it was given |
| `slay_npc_clients` | `id`, `brief`, `target_tags`, `scoring` | Only if NPC mode makes V1 |
| `user_blocks` | `blocker_id`, `blocked_id`, `created_at` | **Generic**, usable by every game |
| `content_reports` | `id`, `reporter_id`, `subject_type`, `subject_id`, `reason`, `status`, `created_at` | **Generic** |

Reused unchanged: `match_records` / `match_participants` (`game_type = 'slayhuud'`),
`player_game_ratings`, `player_game_stats`, `player_achievements`, `coin_transactions`,
`huud_posts`, `rooms`.

Needs a small change: `championships` (size check `IN (4,8,16,32)` → add 64/128,
plus per-round themes via `slay_rounds`).

---

## 3. WebView / Three.js structure

**Package:** `flutter_inappwebview` (recommended over `webview_flutter`) — it can serve
bundled files from a local origin (`https://appassets…`), which avoids `file://`
module/CORS problems on Android and lets the HTTP cache work for downloaded assets.

**Renderer project:** `slay-renderer/` at repo root, TypeScript + Vite + `three`.
`vite build` outputs into `app/assets/slay_renderer/` so the renderer ships inside the
app (works offline, starts fast). Only garments/hair download at runtime.

```
slay-renderer/src/
  main.ts        boot, quality tier, message loop
  bridge.ts      typed message envelope, request/response by id
  scene.ts       renderer, camera, one key light + env map, baked floor shadow
  avatar.ts      base body load, shared skeleton, skin tone, face preset
  wardrobe.ts    equip/unequip per slot, region hiding (no body poke-through)
  loader.ts      GLTFLoader + KTX2Loader + Meshopt, in-memory LRU, abort on swap
  poses.ts       AnimationMixer: idle loop + pose clips, crossfades
  controls.ts    constrained orbit (yaw 360°, limited pitch), pinch zoom
  snapshot.ts    fixed "portrait" camera → PNG at fixed size
  quality.ts     tier → pixel ratio, texture size, antialias, shadow on/off
```

**Lifecycle rules**

- One WebView per SlayHuud session, created when the player enters SlayHuud, kept warm
  across screens, disposed on exit.
- The renderer holds no game state. Flutter owns the current look; after any WebView
  reload, context loss or app resume, Flutter re-sends the full look (`applyLook` is
  idempotent). This removes the "lost outfit after backgrounding" risk.
- Styling timers run in Flutter and on the server, never in JS.

**Quality tiers** (chosen by Flutter from device RAM/model, overridable by a
renderer self-check on first frames):

| Tier | Target | Settings |
|---|---|---|
| High | iPhone 12+, flagship/upper-mid Android | DPR up to 2, 2K hero textures, MSAA |
| Standard | mid-range Android | DPR 1.5, 1K textures |
| Low | budget Android | DPR 1, 512 textures, no idle animation; fallback to snapshot-only if WebGL2 missing |

---

## 4. Flutter ↔ JS bridge contract

Versioned JSON over the WebView JS channel. Every request has an `id`; the renderer
answers with the same `id`.

```jsonc
{ "v": 1, "id": "r-42", "type": "equip", "payload": { ... } }
```

**Flutter → JS**

| type | payload |
|---|---|
| `init` | `{ tier, assetBaseUrl, catalogVersion, locale }` |
| `applyLook` | `{ body, skinTone, facePreset, items: {slot: {itemId, colourway}}, pose, background }` (full state, idempotent) |
| `equip` / `unequip` | `{ slot, itemId?, colourway? }` |
| `setPose` | `{ poseId }` |
| `setBackground` | `{ backgroundId }` |
| `setCamera` | `{ preset: "full"\|"face"\|"feet"\|"back" }` |
| `prefetch` | `{ itemIds: [] }` (e.g. items matching the current theme) |
| `snapshot` | `{ width, height, preset }` |
| `dispose` | `{}` |

**JS → Flutter**

| type | payload |
|---|---|
| `ready` | `{ rendererVersion, webgl2, maxTextureSize }` |
| `ack` | `{ id }` / `error { id, code, message }` |
| `loadProgress` | `{ itemId, loaded, total }` |
| `snapshotResult` | `{ id, pngBase64 }` |
| `perf` | `{ fps, frameMsP95, jsHeapMb }` (sampled, for tier downgrade + telemetry) |
| `contextLost` | `{}` → Flutter re-inits and re-sends `applyLook` |

The contract lives in `shared/contract/` next to the existing WS schema so Dart and
TS types are generated from one source.

---

## 5. Asset format and loading strategy

**Format:** glTF 2.0 binary (`.glb`), Meshopt-compressed geometry, KTX2 (Basis)
textures. Pipeline: Blender export → `gltf-transform` (resize, KTX2, meshopt, prune)
in a repo script, so every asset is processed the same way.

**Rig rules (the art contract)**

- One skeleton per body (male, female). Every garment, hair and accessory is skinned to
  it or attached to a named bone (earrings → head, watch → wrist, bag → hand).
- Each garment declares `hides_regions` (e.g. `torso`, `upper_legs`); the base body is
  split into regions so covered skin is hidden, not clipped through.
- Flowing traditional pieces (agbada, kaftan, wrapper, gele) use extra bones or
  hand-built pose shapes, **not** cloth simulation.
- Colourways by texture tint/mask, so one Ankara garment ships several prints without
  new geometry.

**Budgets per asset**

| Asset | Triangles | Textures |
|---|---|---|
| Base body + head | ≤ 20k | 2K hero / 1K std |
| Garment | ≤ 10k | 1K |
| Hair | ≤ 8k | 1K |
| Accessory | ≤ 2k | 512 |
| Whole dressed avatar | ≤ 80k | — |

**Loading**

1. Bundled in app: renderer, both base bodies, default hair/outfit, 1 background, idle animation.
2. Catalog manifest (`GET /slay/catalog`) lists every item with thumbnail + asset path.
3. Wardrobe grids show **thumbnails only** (WebP, ~256px). The 3D asset loads when
   the item is tapped.
4. When a theme is shown, `prefetch` the player's owned items that match its tags.
5. Assets are immutable at `/{catalogVersion}/{path}`, served with long cache headers.
   Caddy serves them in V1; move to a CDN when traffic needs it.

---

## 6. Competition state model

```
DRAFT ─► OPEN ─► SUBMISSIONS_CLOSED ─► VOTING ─► TALLYING ─► RESULTED
            └──────────────────────────────────────────────► CANCELLED
```

| Mode | OPEN (styling) | VOTING | Result |
|---|---|---|---|
| Solo / NPC client | client-paced | none | system score → stars |
| Style Battle | room phase, ~3 min | room spectators live + community ballots until `min_votes` or window ends | higher final score |
| Group (4–16) | room phase | pairwise ballots | ranking → placement |
| Slay or Pass | per round: styling → reveal one by one → Slay/Pass → elimination; repeat to final 2 | judges in room | elimination order = placement |
| Daily / weekly | window (e.g. until 8 PM) | ballots until `voting_closes_at` | ranking, top N |

**Live room phases (GameModule `slayhuud`):** `Lobby → Styling → Submitted → Judging →
RoundResult → (next round) → Results`. When a battle's voting outlives the room,
the room ends at `Submitted` and the competition moves on asynchronously. Players get a
push when results land.

**Finalisation** happens once per competition, idempotently, keyed by competition id:
scores → placements → `match_records` row (ranked or unranked with reason) → rating via
the existing `RatingService` → coins/XP/items → achievements → Huud card.

**Fallbacks**

- Too few community votes by close → system score decides; match recorded **unranked**
  (`unranked_reason = 'insufficient_votes'`).
- A player doesn't submit in time → their current look auto-submits if it meets the
  required categories, otherwise forfeit.
- Slay or Pass tie → system score breaks it.

---

## 7. Voting model

- **Server-issued ballots.** The client asks for the next ballot; the server picks the
  pair and records `served_at`. A vote can only answer an open ballot it was issued.
- **Anonymous by default.** Ballots carry snapshot URLs and the theme only. No username,
  rank, country or followers. Identities are revealed after the result.
- **Pair scheduling.** Prefer entries with the fewest comparisons, then pairs with close
  current scores (most information per vote). This avoids tiny grids of 8 avatars.
- **Ranking.** Bradley-Terry over all pairwise results, which gives a community score
  per entry (0–100). Same code for group, daily and weekly.
- **Final score** = `w_sys × system + w_comm × community`, weights from the
  challenge config (e.g. battle 30/70, daily 40/60, solo 100/0).
- **Slay or Pass** uses `kind = slay_pass` ballots: one look, Slay or Pass, judges only.
- **Eligibility to vote.** Not a participant in that competition, not blocked by either
  contestant, a full account (not a guest), and account older than a small minimum.

---

## 8. Rating approach

Reuse the existing Glicko-2 pipeline with `game_type = 'slayhuud'`. It is already
per-game and separate from Chess and Draughts.

- **Style Battle:** a win/loss pair, rated like any 1v1.
- **Group / Slay or Pass:** placement goes through `PairwiseOutcomes`, which already
  weighs placement against opponent strength. This is exactly what the note asks for.
- **Ranked only when trustworthy:** minimum community votes met, no bots, no
  farming flags (`RatedMatchPolicy` gets a Slay rule).
- **Not rated in V1:** solo, NPC client, daily/weekly. Large async fields are noisy and
  easy to brigade. They get their own leaderboards and prizes instead.
- Profile stats map onto what exists: rating, global/country rank, wins and
  competitions (`player_game_stats`), best streak, tournament wins (`championships`).
  **Top 3 count** is new, read from `slay_entries.placement`.

Coins and XP stay fully separate from rating.

---

## 9. API and WebSocket requirements

**REST — `/api/v1/slay`**

```
GET  /catalog?since=<version>         manifest: items, themes, poses, backgrounds
GET  /avatar  · PUT /avatar           body, skin tone, face preset
GET  /wardrobe                        owned items
POST /wardrobe/buy        {itemId}    coin purchase (ledger entry)
POST /looks               {look}      → lookId (validates ownership + body)
PUT  /looks/{id}/snapshot (PNG)       → snapshotUrl
POST /solo/{themeId}/score {lookId}   → per-dimension scores + stars
GET  /challenges                      open daily/weekly
POST /challenges/{id}/entries {lookId}
GET  /ballots/next?competitionId=     → ballot (or none)
POST /ballots/{id}        {choice}
GET  /competitions/{id}               state + results (identities after result)
POST /reports  · POST /blocks         generic, used app-wide
```

Live modes use the existing room APIs with `gameType = "slayhuud"` and a mode config
(`battle` / `group` / `slay_or_pass`, theme, timer, seats). Rating and leaderboards
come from the existing `/competitive` endpoints with `slayhuud`.

**WebSocket — existing `/ws/room/{id}`, new `PLAYER_ACTION`s**

| action | who | data |
|---|---|---|
| `SUBMIT_LOOK` | contestant | `{ lookId }` |
| `READY_RESTYLE` | contestant | `{}` (next Slay or Pass round) |
| `JUDGE` | judge | `{ entryId, verdict: "slay"\|"pass" }` |
| `SPECTATOR_VOTE` | spectator | `{ ballotId, choice }` |

Broadcast state never includes another contestant's look before the reveal phase.
That's the same secret-data rule the other games follow, and it needs a contract test.

To verify during build: whether the orchestrator currently accepts actions from
spectators (needed for live battle voting).

---

## 10. Integration points

| Area | Change |
|---|---|
| Rooms | add `slayhuud` to `RoomService.GAME_TYPES`; seat rules per mode |
| Huud | add to `HuudService` seat/label maps; request cards show mode + theme + seats; win cards read `match_records` as today, plus a **View look** link to the snapshot |
| Tournaments | knockout Style Battle = each `championship_matches` row runs a battle competition; per-round themes from `slay_rounds`; sizes 64/128 |
| Profile / player cards | SlayHuud card from rating + stats + Top 3; best look as the card art |
| Achievements | new `AchievementType`s (e.g. 5 battle wins, top 10 Owambe, Slay champion), each granting a wardrobe item |
| Coins | rewards and item purchases through the existing ledger |
| Notifications | "Your battle results are in", "Daily challenge closes in 1h", "Vote needed" |
| Game select | new SlayHuud tile → SlayHuud hub (Play solo · Battle · Group · Slay or Pass · Daily) |
| Sharing | reuse `card_share.dart` story sharing with the look snapshot |

---

## 11. Anti-abuse

| Threat | Control |
|---|---|
| Voting for yourself | participants can't receive ballots for their own competition |
| Repeat votes | one answer per ballot; one ballot per voter per pair; per-voter cap per competition |
| Vote farming / rings | rate limits; weight down voters whose choices track one contestant; repeat-pair farming guard (already exists for rating) |
| Random tapping | occasional control pairs (clearly on-theme vs clearly off-theme); voters who fail get weight 0 |
| Bots / alts | no guest voting; minimum account age; device-id signals from the guest system |
| Voting after close | server rejects answers after `voting_closes_at` |
| Popularity bias | anonymous ballots; reveal after result |
| Harassment | no free text on looks in V1; outfit-only judging; block + report on every reveal and result screen |
| Fake snapshot | score always from item IDs; snapshot uploaded by the app only. V2 option: server-side render check |
| Coin exploits | rewards issued once per competition id (idempotent); item purchase checks ownership + balance in one transaction |

---

## 12. Phased implementation plan

### Phase 0 — 3D proof (gate before real build)

- 1 rigged female body, 1 hair, 3 garments (incl. one flowing traditional piece), 1 shoe.
- Renderer + WebView + bridge running inside PlayHuud.
- Measure on an iPhone 12-class phone, a mid-range Android and a budget Android:
  cold start, FPS, memory, download size, clipping in poses.
- Get an artist's estimate for the V1 catalogue.
- **Exit:** acceptable numbers + an art pipeline. Otherwise re-plan before Phase 1.

### Phase 1 — First vertical slice (the note's milestone 23)

1. SlayHuud tile → hub screen.
2. Male + female avatars load; change hair, outfit, shoes/accessory; rotate/zoom.
3. Catalog sync (small seed), wardrobe of defaults.
4. One theme; style; submit → `slay_looks` + snapshot upload.
5. Solo score shown (system score).
6. One 1v1 Style Battle via room (`slayhuud` GameModule, styling timer).
7. Third users vote A vs B via ballots (spectators + community).
8. Winner computed; coins + match record (+ rating if ranked).
9. Optional Huud post (request + win card with View look).

Also in this phase: object storage for snapshots; generic block/report; contract test
for "no look leaks before reveal".

### Phase 2 — Progression and solo depth

Full scoring engine (all dimensions), wardrobe unlocks and coin shop, achievements →
items, profile card + leaderboards, 15–20 themes, solo challenge ladder with stars,
NPC client mode if cheap.

### Phase 3 — Group competition + daily/weekly

Pairwise ballot scheduler + Bradley-Terry ranking, group rooms 4–16, async daily/weekly
scheduler, top-N results pages, notifications.

### Phase 4 — Slay or Pass

Multi-round rooms, judge role, reveal-one-by-one flow, eliminations, reverse mode,
friends-only and public rooms.

### Phase 5 — Tournaments + polish

Knockout Style Battle cups with per-round themes, 64/128 sizes, poses and expressions,
outfit transition animations, content up to the V1 target.

**Art track runs in parallel from Phase 0**, and it sets the pace. Code for Phases 2–5
can move ahead with placeholder items, but nothing feels like a real game until the
catalogue lands.

---

## 13. Decisions needed

1. **3D art source.** Who builds the rigged bodies and garments (in-house, contractor,
   studio)? This blocks Phase 0.
2. **Snapshot storage.** S3-compatible bucket (e.g. Cloudflare R2, recommended) or a
   disk volume on the prod server behind Caddy.
3. **Slay or Pass "male/female" pools.** `users` has no gender field. Options:
   (a) base it on the avatar body chosen for that room (recommended — matches "judge
   the look, not the person"), or (b) add a self-declared profile field.
4. **Guest voting.** Recommend guests can play solo but can't vote or play ranked.
5. **Daily/weekly rated?** Recommend leaderboard + prizes only in V1, no rating change.
6. **Tournament size.** Confirm 128 is wanted in V1; it needs a `championships` change.
