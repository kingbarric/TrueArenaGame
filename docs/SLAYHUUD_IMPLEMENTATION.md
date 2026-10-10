# SlayHuud: implementation and handoff

Branch: `codex/slayhuud`. Updated 9 October 2026.

SlayHuud is a social styling competition inside PlayHuud. Its complete loop is theme → style a 3D avatar → save a look → submit → vote or receive a system score → results → coins/XP/wardrobe → another challenge. The current build includes converted MakeHuman male/female avatars, eyes/brows, 11 outfits, six hair entries and two shoes. The UI offers only wardrobe items with real assets; unfinished cultural outfits, accessories and makeup remain future catalogue entries. This is a development branch, not a deployed release.

The original product note is the product direction. [SLAYHUUD_PLAN.md](SLAYHUUD_PLAN.md) records the initial design; this document describes the implementation that supersedes its proposed module/storage choices.

## 1. Architecture and reuse

```text
PlayHuud Flutter
  existing authentication / AppScope / ApiClient / navigation / themes
  features/slayhuud: hub, studio, competitions, Fashion Cups
    SlayStage: local WebView → bundled Three.js renderer
    wardrobe selections → versioned bridge → GLB rendering → PNG snapshot
  existing Huud, room joining, watch, profiles, leaderboards, notifications

Spring WebFlux backend
  ta-engine/.../slay: pure validation, scoring and competition transitions
  ta-api/.../slay: catalog, ownership, looks, competitions, ballots, settlement
  existing RoomService, CoinService, RatingService, ChampionshipService, push
  PostgreSQL: durable Slay state and server deadlines
  existing room WebSocket bus: SLAY_CHANGED invalidation
```

Flutter remains responsible for all product controls. The renderer owns graphics, assets, animation and camera only. The backend calculates scores, closes voting, decides results and awards rewards. Neither client supplies its own score, placement or reward.

Live modes reuse existing room IDs, codes, membership and WebSocket transport. Their game state and deadlines are durable PostgreSQL records rather than the existing board-game runtime timer. Daily/weekly modes use the same state machine without rooms. This permits restarts, asynchronous voting and rounds lasting longer than a socket connection. No duplicate user, wallet, social network, rating or tournament service is created.

A three-second lifecycle scheduler advances expired competitions. `FOR UPDATE` serializes a competition's transitions, submissions and votes. REST reads catch up expired state too; WebSocket invalidation accelerates refresh and a three-second client poll covers missed events. Multi-pod fan-out still inherits the existing room bus's single-pod limitation; database settlement remains authoritative.

## 2. UI and entry points

SlayHuud opens from both the home tiles and the game picker. Existing room invitations and spectator routes open its competition screen. The hub links to the personal studio, four V1 modes, daily/weekly challenges, client briefs, Fashion Cups and existing Slay rankings. Every Slay screen has the existing games' gear-menu pattern with rules and navigation back; the studio also offers the challenge brief and a fresh look. Returning from a live competition does not automatically submit or surrender a look: its server deadline continues.

Screens inherit the selected PlayHuud theme: Palm Wine, Nebula or Supercar, in light/dark mode. They reuse `NeonColors`, typography and `NeonCard`; buttons follow the shared accent and stadium treatment. Wine, gold and existing backgrounds remain the default visual language. Production item thumbnails replace the temporary wardrobe icons when supplied. The hub shows Slay rating, wins and top-three finishes using existing competitive profile data.

The studio has a large 3D stage, rotate/pinch controls, front/back/face camera shortcuts, avatar body selection in solo play, wardrobe categories, skin/face selection, poses and backgrounds. A brief sheet shows requirements/style tags, and competitive styling shows its deadline. Draft selections persist locally. The primary action is **Show off & see my score** in solo play and **Show off & submit** in competition. It waits for the exact outfit to load, plays an 8.6-second approach, pose and full turn, exports the final portrait, then saves and scores/submits. The default signature stance finishes confident; another selected pose is preserved. Stop, leaving the studio, changing outfits or backgrounding during the walk cancels the pending submission. Competition deadlines continue during the animation; late finishes are rejected. A separate pill previews the show without saving.

The separate `lib/slayhuud_preview.dart` entrypoint uses local fixture API responses and a UI PREVIEW banner. It starts on SlayHuud with the game picker underneath, so exit works in the preview too. It runs the actual WebView renderer but does not authenticate or write to a PlayHuud server. Its scores are fixtures, not backend verification.

## 3. New persistence (V37)

| Table/change | Purpose |
|---|---|
| `slay_profiles` | Saved avatar selections and XP; linked to existing user |
| `slay_wardrobe` | Earned/purchased ownership; default items come from catalog |
| `slay_looks` | Immutable selections, catalog version and bounded PNG snapshot |
| `slay_competitions` | Mode, linked room/host, durable JSON state, indexed deadline, settlement flag |
| `slay_ballots` | Server-issued pair, voter, round, timestamps and accepted choice |
| `slay_reward_claims` | Unique reward idempotency key per user/source |
| `user_blocks` | Generic block relationship, absent in the inspected architecture |
| `content_reports` | Generic report queue, also absent before this change |
| `match_participants.placement` | Group finishing position in existing match history |
| Existing constraints | Register `slayhuud` rooms and allow 64/128-player championships |

Competition JSON contains members, submitted entries, system scores, pairwise comparisons, judge decisions, round state and eliminated contestants. It is the durable source, not an in-memory room snapshot. A future high-volume async release can normalize entries/votes without changing renderer contracts.

Snapshots are stored as PostgreSQL `BYTEA` for the working V1; no external storage credentials are required. PNG size is capped at 1 MB and dimensions at 1024×1536, with actual decoding validation. Flutter exports 600×900. The WebFlux JSON body limit is 2 MB to accommodate base64. Move images to object storage/CDN before large-scale launch. `snapshot_verified` is reserved for future server verification and is not currently populated.

## 4. Renderer and bridge

Source: `slay-renderer/`. Runtime: bundled single HTML/JS file in `app/assets/slay_renderer/`, served on device loopback port 8187 by `flutter_inappwebview`.

Three.js supplies orbit controls, portrait camera, lighting, stage, GLTF loading, named skeleton binding, body-region masking, skeletal catwalk/pose animation and morph presets. The starter catwalk uses two-bone leg IK and level foot joints; garments and shoes share the live skeleton. Skirt weights bridge smoothly across both walking legs. This is authored motion, not cloth simulation. GLB with Meshopt compression and KTX2 textures is supported. Draco is not currently configured. The renderer loads only the avatar and selected items, retains equipped objects and releases replaced geometry/materials/textures. Immutable GLBs have a bounded 32 MB IndexedDB cache; cache failures still permit network loading.

Bridge envelope:

```json
{"v":1,"id":"slay-12","type":"applyLook","payload":{"look":{
  "body":"female","skinTone":"#623a27","facePreset":"classic",
  "items":{"outfit":"female-owambe","hair":"female-hair-0","shoes":"shoe-3"},
  "pose":"signature","background":"studio"
}}}
```

| Direction | Messages |
|---|---|
| Flutter → JS | `init` (catalog, tier), `applyLook`, `setCamera`, `rotateCamera` (radians), `setPose`, `showcase`, `stopShowcase`, `snapshot`, `pause`, `dispose` |
| JS → Flutter | `ready`, `ack`, `snapshotResult` (PNG base64), `error`, `showcaseState` (playing, phase), `perf`, `contextLost` |

Commands execute serially and responses match request IDs. `showcase` releases the command queue immediately and acknowledges only after the final pose; cancellation rejects that pending request so Stop/Pause remain responsive. Snapshot export is blocked during motion. Requests time out rather than silently submitting missing imagery. Snapshot export requires a fully applied look; a failed replacement invalidates export until a successful retry. Foreground/background transitions and covered routes pause rendering, and performance samples restart on resume so inactive time does not lower the quality tier. WebGL context loss reloads and reapplies the look. Low measured frame rate reduces pixel density through high/standard/low 3D tiers; there is no 2D replacement. Physical-device performance targets still require real assets and profiling.

Grouped body meshes and all matching body regions support skin tint/masking. Skin materials are isolated to avoid recolouring shared clothing materials; supplied makeup overlays receive matching face/expression morph weights. Replaced skeleton GPU textures and animation bindings are released. Self-contained GLB structure is checked before parsing network or cached bytes; external texture/buffer URLs are rejected.

Production missing assets produce errors; mannequins are permitted only while `developmentAssets=true`. Development competitions never move rating.

## 5. Competition lifecycle

```text
lobby → styling → voting → results
                      ↘ round_result → styling (Slay or Pass)
expired empty lobby / no submissions → cancelled
```

Spectator judging replays immutable submitted 3D looks **one at a time**. Battle/group ballots show A then B and unlock pairwise choices after both performances. Slay or Pass shows only the server-revealed contestant and unlocks Slay/Pass after their performance; the final two are also shown sequentially. Replay is available. Older/failed 3D submissions offer a saved-photo fallback. There is one WebView per judging sequence, released when the ballot or revealed entry changes. This is per-viewer replay within the existing voting window, not a synchronized live broadcast; contestant animations are not streamed over WebSockets.

`GET /api/v1/slay/looks/{id}` returns only canonical `look` and `catalogVersion` for rendering. It shares image authorization: owner access, eligible competition visibility, private-room/block protections and elimination reveal restrictions. It never exposes owner identity or changes scoring/reward rules.

Server timestamps control every window. Missing looks forfeit; closing a client never auto-submits its draft.

- **Style Battle:** two contestants, one theme, independent styling, anonymous community pairs, results and rematch. Equal final scores produce a draw, participation rewards and a draw in existing history.
- **Groups:** 4, 6, 8, 10 or 16 contestants; ranking uses the same voting/settlement engine. Shared scores may share a placement.
- **Slay or Pass:** 3+ contestants and 3–6 opposite-avatar-body judges. These are avatar role selections, not stored real-world gender. One anonymous look at a time; each judge chooses Slay/Pass once. Lowest score is eliminated and remaining players restyle. Final two receive Red Carpet and each judge chooses one finalist anonymously. Judges do not receive contestant rewards/rating. Reverse contestant/judge pools are supported.
- **Daily/weekly:** entry at any time during the window, then community voting; no opponent needs to be online. Daily UTC windows use one day of entry followed by one day of voting. Weekly Monday UTC windows use seven days of entry and two days of voting.
- **Solo/client:** same deterministic score engine and wardrobe ownership, with catalogue client briefs. Solo rewards are claimable once per theme per UTC day; repeated practice remains playable.

## 6. System score, community voting and rating

System score is deterministic: theme tag fit 50%, required categories 30%, colour harmony 10%, completeness 10%. Neutral colours are compatible; excess accent colours reduce harmony. Three stars begins at 85, two at 65, one at 40. Theme body eligibility and any budget are enforced. Rarity does not buy a higher score.

Community pairwise scores use regularized Bradley–Terry strengths and convert them to a 0–100 average win expectation against the field. Per-challenge `systemWeight` controls the system/community blend. Every entry needs the minimum exposure (six comparisons by default; three judge responses in Slay or Pass). If exposure is insufficient, the result uses system score and is unranked. Names, countries, followers and ratings are withheld during voting; identities appear in final results.

Slay rating reuses Glicko-2 math in a separate `game_type='slayhuud'` namespace. A head-to-head outcome is a win/loss/draw; group `rank:n` is expanded into pairwise outcomes against each opponent. Opponent strength therefore matters. Existing guest/bot checks, repeated-opponent limits, history, global/country boards and achievement infrastructure remain in force. Dev assets and insufficient voting override tournament rating eligibility.

Anonymous PNGs are client-rendered. Validation proves format/size, not that the image matches the submitted outfit. A production anti-cheat/moderation decision is still needed before trusting every screenshot for competitive voting.

## 7. API and realtime

All feature routes are beneath `/api/v1/slay` and use existing authentication.

| Routes | Behavior |
|---|---|
| `GET catalog`, `GET profile`, `GET wardrobe` | Catalogue, XP/stats/avatar and ownership |
| `POST wardrobe/buy` | Atomic existing-coin debit plus unique ownership |
| `POST looks`, `POST looks/{id}/snapshot`, `GET looks/{id}/snapshot` | Save selections, bounded immutable PNG, image read |
| `POST solo/{theme}/score` | Server score and idempotent reward |
| `GET/POST competitions`, `GET competitions/{id}`, `GET rooms/{id}` | Browse/create/read and existing room adapter |
| `POST competitions/{id}/join`, `/start`, `/submit`, `/cancel` | Membership and competition lifecycle |
| `POST competitions/{id}/judge`, `/final-vote` | Judge-only reveal/final decisions |
| `GET competitions/{id}/ballot`, `POST ballots/{id}` | Server-assigned anonymous pairs and valid vote |
| `POST reports`, `POST blocks` | Report a look; block future room/voting interactions |

Existing `/ws/room/{id}` sends `EVENT` with payload type `SLAY_CHANGED` and competition ID after a committed change. Clients refetch authorized REST views. No private looks or rankings are broadcast on that public event.

## 8. Huud, cups, profiles and rewards

Existing Huud game requests accept SlayHuud, retain a real lobby and can be joined without friendship. The competition UI can explicitly post its lobby request. Slay match records feed existing social win/history mechanisms. No posts are automatically published while testing the fixture preview.

Fashion Cups use `championships`, participants, matches, game history, badges and existing invitation links. Create requests add an optional `gameType` while preserving Draughts defaults. Knockout sizes are 4/8/16/32/64/128. Match rooms receive round themes. A tie replays the pairing; one submitted look wins by forfeit at deadline. With both entrants absent, the match closes with no winner and the bracket advances its byes.

Competition settlement writes existing game results/history, updates a bracket and applies coins/XP once inside the transaction. Competitive reward coins/XP are capped at ten competition claims per rolling 24 hours. Group first/second/third normally earn 100/60/30 coins; other submitted participants receive 10. Tied battles receive 30 each. Existing coin stakes are explicitly disabled for Slay.

Five wins and a Fashion Cup championship unlock exclusive wardrobe items for both avatar bodies. Slay top-three/five-win/champion achievements reuse existing profile badges. Rating remains separate from XP and coins.

## 9. Abuse controls and remaining scale work

Implemented: registered non-bot competitor/voter accounts, account-age gate for community voting, no contestants voting in their own competition, unique pair/voter/round ballots, one-second minimum ballot dwell, voting cap, server expiry, one decision per judge/look or final, ownership/body/slot/budget checks, immutable submitted looks, row locking, duplicate reward protection, block exclusions, private cup access checks and report actions.

Existing architecture had no generic block/report tables, so V37 introduces them. Enforcement currently covers Slay room joining and its ballots; it does not retrofit every existing chat/game. Reports persist for review but a staff review UI/automated image moderation is not part of this branch. Image UUIDs are opaque; image reads enforce ownership or a published competition phase and private cup access. Device/account linkage and stronger collusion/bot detection remain future abuse work.

The async implementation is appropriate for testing and modest V1 traffic. It stores votes with competition state and computes field comparisons at settlement; mass participation needs indexed/normalized ballot scheduling, performance measurements, pagination and load tests. Results show the top 100 plus the viewer’s submitted look when outside that range. Current hub lists are bounded and existing room fan-out is local to one backend process.

## 10. Asset handoff and launch gates

See [SLAYHUUD_ASSETS.md](SLAYHUUD_ASSETS.md) for exact filenames, skeleton/material/morph requirements and asset validation. The catalogue currently contains 20 themes, 17 outfits per avatar body (including unlocks), six hairstyles per body, eight shoes, twelve accessories, eight makeup choices, five backgrounds and four poses. These are metadata and procedural stand-ins, not completed fashion art.

Before enabling a production catalogue:

1. Supply and visually fit male/female GLBs, clothes, hair, accessories, makeup overlays, poses and thumbnails.
2. Assign immutable HTTPS asset/thumbnail URLs and increase the catalogue version; set `developmentAssets=false` only after the catalogue is complete.
3. Test real loading, rig deformation, clipping, skin tones, face/makeup overlays, textures and poses from all angles.
4. Profile actual iPhone 12+ and representative Android hardware for frame rate, memory, cache, load time, thermal behavior and app lifecycle.
5. Complete launch review of screenshot trust/moderation, image storage and expected async traffic.

## 11. Development and validation

```sh
cd slay-renderer
npm ci
npm run build
npm test
npm run assets:validate -- /path/to/asset-delivery
# For an initial smaller delivery and a report to return to the artist:
npm run assets:validate -- /path/to/asset-delivery --partial --report /tmp/slay-assets.json
```

`npm run build` refreshes the bundled Flutter HTML and catalogue. Run it after renderer or catalogue edits.

```sh
cd app
flutter run -t lib/slayhuud_preview.dart --dart-define=API_BASE=http://localhost:55667
flutter analyze lib/features/slayhuud lib/slayhuud_preview.dart
flutter test test/slayhuud_vote_test.dart test/visual_theme_test.dart
```

The dummy API_BASE keeps fixture preview image/socket destinations local. Normal development runs use the existing backend and authentication flow.

Backend verification uses normal Maven reactor checks. `SlayHuudIT` supports either Testcontainers or `it.r2dbc.url`, `it.jdbc.url`, `it.db.user`, `it.db.password`, `it.redis.port` pointing at disposable local services. It exercises real PostgreSQL/Redis wiring. No production database is used.

## 12. Implementation phases

| Phase | Current state |
|---|---|
| Architecture inspection and contracts | Implemented/documented against actual services |
| First vertical slice | Theme → 3D stage → look/PNG → 1v1 → third-party vote → result/reward |
| V1 modes | Solo, groups, Slay or Pass, async daily/weekly and client briefs implemented |
| Platform integration | Existing rooms, Huud requests, spectator entry, coin ledger, profiles/ranks, achievements and knockout cups wired |
| Asset production | Awaiting supplied GLBs, thumbnails and baked animation/morph content |
| Launch hardening | Real-device profiling, screenshot/moderation and scale/storage decisions remain |

### Cleanup verification (9 October 2026)

- Backend Maven reactor: 647 tests passed. Mockito required an unrestricted test run so its Java agent could attach; the unrestricted suite passed without code changes for that environment issue.
- Flutter: eight related navigation, anonymous voting and theme tests passed. Focused feature, route, preview and badge analysis is clean.
- Renderer: TypeScript/Vite build and 21 tests passed, including GLB structure, bind-pose skinning and eye-height regressions. All 21 delivered GLBs validate; 55 undelivered catalogue slots are skipped and 11 asset-size budget warnings remain.
- iPhone 16e simulator: verified the supplied game icon, hub/studio gear menus, help, exit/re-entry, wardrobe thumbnails, female outfit/hair changes, male body switching, camera presets, fresh look, draft restoration and PNG submission into the fixture score sheet. Fixture scores/rewards are simulated; this session does not verify live multiplayer or production settlement.
- SlayHuud now runs separately on the iPhone 17 Pro simulator because another preview replaced the app on the shared iPhone 16e during testing. Verified the studio's explicit rotation controls through a full 360° turn. Drag/pinch is routed directly to the WebView; automation did not establish touch-gesture behaviour, so that still needs a manual/device check. Physical-device frame rate, memory and thermal measurements remain outstanding.

### Playful interface refinement (9 October 2026)

- Added raised pill buttons with press feedback across the hub, studio, competitions, cups and help. Retained the selected PlayHuud palette and fonts.
- Compact wardrobe tiles fit four columns on a typical phone, with selection badges, larger thumbnails and labels that grow with accessibility text settings. Camera, avatar and category controls use rounded pills; hub modes have individual colour accents and bounce feedback.
- Focused Flutter suite: 12 passing tests covering navigation, anonymous voting, theme behavior, disabled submissions, keyboard wardrobe selection and large text in light/dark themes. Feature analysis is clean.
- Visually reviewed the hub and studio in the dedicated iPhone 17 Pro simulator. The Mac locked before further outfit tap testing; keyboard activation was verified by a widget test. This is still the fixture UI preview, with simulated scores/rewards.

### Shoe fit and real poses (9 October 2026)

- Removed the downloaded shoe models' sock UV islands and generated separate male/female fits within each shoe GLB. Matching fit meshes are selected by `extras.slayBody`. Added a foot-only skin mask, kept exposed legs visible, and rendered accurate sock-free wardrobe thumbnails with Blender.
- Replaced the root-only turns with four articulated starter fashion poses and a subtle breathing cycle. Fitted shoulder/head joints for each body and added blended weights at joints. All joints are keyed to prevent stale poses; the selected pose is evaluated immediately for screenshots.
- Catalogue v9 / starter rigs v2 invalidate old cached assets. The studio displays the selected pose, describes each stance, and provides a shoe close-up camera button.

- Verification: 23 renderer tests passed, including loaded-GLB limb movement, pose reset, skin deformation, body-fit selection and grounded shoe skinning. Nine focused Flutter tests passed and feature analysis is clean. All 21 bundled models pass partial structural validation; 55 future items remain skipped and 11 existing size-budget warnings remain.
- Visually checked both body fits and articulated stances in Three.js, including shoe side/heel views. Rebuilt the iPhone 17 Pro preview and verified the pose chooser applies a visibly different hand-on-hip stance and the shoe camera opens a close-up. Scores/rewards in this preview remain fixtures.

### Dress clipping repair (9 October 2026)

- Reproduced skin patches at the waist/hips of the halter dresses. Transferred the clothing authors' MakeHuman coverage masks through the low-poly female proxy and embedded per-outfit triangle masks in the base GLB. The renderer removes covered skin faces on equip and restores them when switching outfits. Exposed shoulders, open backs and short-dress legs remain visible.
- All seven enabled female outfits now use precise coverage instead of coarse torso hiding. Catalogue v10 invalidates the previous cached body. No per-frame coverage calculation is added.
- Verification: 26 renderer tests pass, TypeScript/Vite build passes, and all 21 delivered GLBs validate (the existing 11 size warnings remain). Reviewed the seven female outfits from front/back in all four poses in Three.js, and checked First Impression in the dedicated iPhone 17 Pro simulator. This remains the fixture preview; physical-device performance and live multiplayer are outside this repair.

### Recorded checks (8 October 2026)

- Backend: 107 relevant checks passed (68 unit tests; 39 PostgreSQL/Redis integration tests across SlayHuud, competitive ratings and Huud).
- Flutter: seven voting/theme widget tests passed; targeted feature/integration-route analysis is clean.
- Renderer: TypeScript/Vite build and 17 bundle/skeleton/presentation/snapshot/asset-delivery tests passed after asset-readiness hardening. Backend and Flutter counts above are from the foundation verification; this renderer-only continuation does not rerun those suites.
- Android: debug APK built successfully using the stable plugin compatibility patch. Android runtime/performance has not been tested on a physical device.
- iOS: fixture preview built and ran on iPhone 16e simulator; inspected studio, outfit swapping, back camera and PNG submission/score flow. This does not substitute for real asset/device measurements or a signed release.

Android uses a locally vendored stable `flutter_inappwebview_android` 1.1.3 with two upstream ProGuard filename fixes for AGP 9.1. See `app/vendor/flutter_inappwebview_android/PATCHES.md`; the shared Pub cache is untouched. All other WebView platforms remain on the stable release.

### Ankle continuity repair (9 October 2026)

- The shoe coverage mask removed the female ankle above the low shoe opening. Catalogue v11 retains the real foot/ankle inside both fitted shoe styles instead of hiding the entire foot region. Toe, heel and ankle fit was checked from front, side, back and an angle on both bodies in Three.js.
- All 26 renderer tests pass, including a new actual-catalogue check that skin remains visible and rays through both ankle openings reach skin below the old cutoff. The Mac was locked during this inspection; browser review was available.


### Starter wardrobe expansion (9 October 2026)

- Catalogue v12 adds 28 immediately available items: three date dresses, three male suits, three casual shirts, one fitted pair of wool trousers, three eye colours for each body, three lipstick shades, three earrings, three bags and three original watch styles.
- Converted the selected MakeHuman assets to embedded GLBs with small textures and actual-model thumbnails. Added precise coverage to the new dresses, fitted the polo shoulder line and aligned earrings/lipstick to the female face. Eyes respect transparent corneas; removing an eye choice restores the base mesh. Watches contain separate body fits and held bags follow the avatar hand.
- Studio categories expose these assets and offer None for optional beauty/accessories. Wardrobe credits are bundled offline and available from the gear menu; CC-BY bag authors/licenses/modifications are recorded in SLAYHUUD_ASSET_CREDITS.md. The subsequent underwear-start update below makes tops and bottoms independent selections.
- Verification: 32 renderer tests, 13 focused Flutter tests and eight SlayRules tests passed. Feature analysis and the TypeScript/Vite build pass. All 49 enabled GLBs validate; 55 future slots remain skipped and 13 soft size-budget warnings remain. The bundled GLBs total approximately 45.7 MB, with models loaded only when selected.
- Visually checked dresses/suits/shirts, eye/lip/earring selections and front/angled bag and watch fits in Three.js. Rebuilt and launched the dedicated iPhone 17 Pro fixture preview; the Mac locked before native tap verification of this expansion. Live multiplayer/rewards and physical-device performance are not verified by this asset update.

### Runway and expanded separates (9 October 2026)

- Show off plays an 8.6-second approach, articulated pose, full turn and final stance. Solo scoring/submission waits for animation completion. Cancelling or leaving prevents submission. Battle/group voters review anonymous looks sequentially before choosing; Slay or Pass and its final use the same presentation. This is a spectator-controlled replay during the voting window, not a synchronized live broadcast.
- Submitted runway looks use the backend's immutable saved look and its existing image visibility/block rules. `GET /api/v1/slay/looks/{id}` returns styling data without player identity. Shoes, clothing and accessories follow the same live rig.
- Catalogue v15 delivers 50 more clothing choices: ten extra female dresses, ten skirts, ten tops and ten trousers (distinct downloaded silhouettes plus colour/crop variations), with three additional female tops, four female bottoms and three male bottoms. Models load on selection; the wardrobe uses thumbnails.
- Each ten-item female set includes four free choices and six permanent coin unlocks priced at 40, 60, 80, 100, 120 and 150 coins. Clicking a locked item asks Yes/No, shows balance when available and disables Yes when known funds are insufficient. Only backend success equips/unlocks it. Existing transactional purchase infrastructure debits coins and grants ownership together, preventing duplicate charges and insufficient-balance unlocks. An authoritative wallet refresh follows purchase.
- Clothing tabs have All/Casual/Corporate/Date Night/Party/Formal/Traditional filters based on catalogue tags. Fresh sessions start in fitted underwear (male boxer briefs; female sports bra and briefs), with hair and no automatic outfit/shoes. Resume draft is explicit and requires available, owned items. Removing clothing restores underwear. A complete outfit or top plus bottoms is required for submission.
- Coverage preserves exposed ankles/thighs under shorts and midriffs under cropped tops. Clean plane clipping avoids jagged starter-underwear/crop hems. All 40 collection choices include actual-model PNG previews. Credits and modifications are bundled offline.
- Verification: 39 renderer tests, 16 Flutter tests and 18 backend checks (eight scoring tests and ten PostgreSQL/Redis integration tests) passed; feature analysis and the TypeScript/Vite build are clean. All 99 bundled models validate with no missing/invalid deliveries, 55 future catalogue slots skipped and 15 soft asset-size warnings. Browser review covered the starter bodies and casual separates from front/back and during walking.
- Dedicated iPhone 17 Pro fixture preview: verified underwear start, style filters, real-model thumbnails, No leaving 600 coins/item locked, Yes unlocking a 40-coin skirt and showing 560 coins, and pairing that skirt with a free cropped top to enable submission. Show off walked/posed before opening the fixture score report, and returning to the studio retained the unlocked outfit/560 balance. Backend integration tests separately verified real transactional deduction, duplicate-purchase rejection, insufficient funds and incomplete-look rejection. Simulator balances, scores and multiplayer responses are fixtures; production settlement/live spectators and physical-device performance are not established by this preview.

### Studio spacing and navigation hierarchy (9 October 2026)

- Inset and rounded the avatar stage, added 12 px beneath it and a divider between styling actions and wardrobe navigation. Reduced the stage height slightly to retain wardrobe space.
- Styling actions retain raised pills; wardrobe categories use underlined tabs; style filters use smaller flat outlined pills. Camera controls are circular and Her/Him uses a joined selector. Existing PlayHuud colours and typography remain.
- Avatar selection starts with an eligible body and resets the wardrobe to Looks. Stage disposal defers indicator notifications until the widget tree has unlocked, fixing a listener assertion exposed when the preview layout changed.
- Visually reviewed the updated layout in the dedicated iPhone 17 Pro preview. Feature analysis and ten existing controls/navigation/show-off tests passed.

### Faster catwalk and four show-off finishes (10 October 2026)

- Shortened show off from 8.6 to 5 seconds: 1.8-second catwalk, quicker blend into the selected stance, full turn and final hold. The authored gait plays faster without enlarging strides or changing shoe fit. Runway timing uses elapsed time rather than the idle-animation frame cap, so low frame rates do not stretch the sequence.
- The pose picker exposes Signature, Hand on hip (confident), Cover star (editorial) and Victory (celebrate) as compact raised choices. Tapping any choice previews its catwalk and finish without submitting. The selected pose stays on the look for submission and spectator replay; Signature is no longer silently replaced with Confident.
- Pose previews lock styling/submission until completion and remain cancellable using Stop show off. The stage's automatic outfit update queues before playback to prevent it interrupting the new animation.
- Verification: 41 renderer tests and 18 Flutter tests passed; feature analysis and the TypeScript/Vite build pass. Actual male/female rigs preserve all four distinct finishing stances, walk onto the stage within two seconds, and keep shoes grounded while walking. The picker tests verify all four labels map to the existing saved-pose IDs.
- Rebuilt the dedicated iPhone 17 Pro fixture preview and reviewed the four-choice sheet, automatic catwalk previews, and distinct Victory/Cover star finishes. Styling/submission controls unlock after playback; changing the preview pose does not save or score a submission.

### Styling score correction (10 October 2026)

- Removed the preview's fixed 89/three-star response. It evaluates the saved look against the selected catalogue theme; 18 shared examples assert identical preview/backend results. Production remains server-authoritative.
- Theme fit evaluates each main garment independently (85% of theme fit), with matching footwear/details contributing the other 15%. Hair/eye tags cannot turn an unrelated outfit into a matching outfit. Separates do not merge their tags to hide a mismatched garment. Basic completeness uses outfit, footwear and the challenge's required categories, without requiring a hairstyle.
- Overall weights are 50% theme fit, 25% requirements, 15% palette balance and 10% completeness. Each missing requirement caps the final result by 25 points, so incomplete required categories cannot earn three stars. Palette balance counts wardrobe/makeup accent colours against neutrals; it is a simple tag heuristic, not visual colour analysis. Prices, rarity, skin, face, pose and scene provide no score bonus.
- Reports name the theme, show the component scores and explain missing items, clothing tag mismatch, unrelated details and overloaded palettes. Feedback scrolls on small screens. The fixture preview explicitly says it does not award coins or XP.
- Verification: 39 Flutter checks and 14 backend unit/contract checks passed; feature/preview analysis is clean. In the dedicated iPhone 17 Pro preview, submitting First Impression with no footwear now returns 75, 50% requirements/completeness and a missing-shoes explanation. No production score/reward settlement was exercised by the simulator.

### Women’s footwear and garment colours — 10 October 2026

Added five female shoe options: Mary Jane Heels, Stiletto Ankle Boots, Ballet Flats, Strappy Sandals and Flat Slippers. The existing two unisex shoes remain available. Downloaded licensed MakeHuman packs are retained locally outside Git; adapted GLBs, thumbnails and credits ship in the app. Shoes load on selection. Cutout shoes keep texture alpha, open footwear retains the real feet, and the closed high-heel boot masks only the covered foot region. Starter auto-fit and shared rig weights still require final artist review before release.

Equipped shoes, shirts and tops offer twelve colour swatches plus Original colour. `Look.itemColours` records palette names keyed by wardrobe category, travels in the existing saved-look JSON, and replays with the runway avatar. Legacy looks load with an empty map. Replacing/removing a garment clears only that garment’s override. The renderer dyes fabric luminance in its material shader without duplicating textures or touching the body; resetting restores the original textured material. The backend validates allowed categories and palette names and uses the selected colours when judging palette coordination.

Verification: 46 Flutter tests, 47 renderer tests (including all five shoes through three runway finishes), 16 backend tests, Flutter analysis and renderer build. Asset delivery: 104 GLBs valid; 55 future catalogue placeholders skipped, 18 soft size-budget warnings. Simulator preview rebuilt; final interactive check requires the Mac to be unlocked.

### Tube-top coverage repair — 10 October 2026

Colour Pop Tube Top and Warm Colour Pop Top used a source mesh authored on a shorter, narrower body. In the starter avatar they sat below the chest and inside the skin, while choosing a top correctly replaced the previous dress and hid the starter bra. Both exports now fit the chest before rig weights are assigned, with a deeper back panel and a conservative body mask for the covered chest band. Bare shoulders and midriff remain visible; briefs remain visible when no bottom is equipped. Catalogue version 17 invalidates cached models and thumbnails.

Both variants were rendered from the front/back with the real avatar and coverage masks. The renderer’s 49 tests pass, including new ray checks that fabric covers chest/back samples in every pose, exposed midriff is retained and removing the top restores body and underwear. Renderer build passes.

### Exclusive wardrobe groups — 10 October 2026

Catalogue version 18 assigns every visible garment to one clothing category and one style group. Removed the All filter, which repeated the same garments. Style groups and clothing categories are shown only when they contain visible items after deduplication. Female dress assets previously displayed under Looks now appear under Dresses.

Seven identical aliases are merged into their original, least expensive/default wardrobe entries. Deduplication compares source mesh, texture and conversion options; distinct cuts and material colours remain separate choices. Original IDs remain in the catalogue for saved looks, scoring and ownership compatibility. Restored aliases highlight the canonical tile, and None removes the actual equipped slot even when its browsing category has changed. Source identity metadata is generated during the renderer build and shipped through the existing catalogue API.

Verification: 46 focused Flutter tests, 50 renderer tests and 17 backend unit/contract tests pass; Flutter feature analysis and renderer build pass. New checks cover exclusive grouping for both bodies, hidden empty categories, alias selection compatibility and unchanged catalogue IDs. Rebuilt and launched the dedicated iPhone 17 Pro fixture preview. The Mac was locked, so native tap verification of the new groups remains unverified.

### Female beauty expansion — 10 October 2026

Catalogue version 19 adds three distinct CC0 MakeHuman hair meshes: Chic Bob (free), Sleek Ponytail (80 coins) and Long & Flowing (120 coins). The two priced additions use the existing Yes/No unlock dialog, transactional purchase API and ownership rules. Existing hairstyles remain available. New hair textures are sized to 512 px and the GLBs are each below 0.8 MB, loaded only when selected.

Five free lipstick shades join the existing three: Peach Nude, Cocoa Gloss, Coral Kiss, Berry Wine and Hot Pink. All eight lip overlays now clip to a curved mouth contour rather than colouring neighbouring skin triangles. Matching face/expression morphs remain intact. Gold Nose Hoop is a free original, fitted lightweight mesh in Details (`accessories`), allowing it to be worn with earrings. It shares head rig bindings and face/expression morphs, hides no body regions, and persists in saved looks.

Rendered real-model thumbnails for all additions and refreshed the original three lipstick thumbnails. Close-up avatar renders verified each new hairstyle with lipstick and the hoop. Source files/licenses remain in the local MakeHuman archive; bundled credits include the new hair and original hoop.

Verification: 53 renderer tests, 40 focused Flutter tests and 17 backend unit/contract tests pass; renderer build passes. New actual-model checks cover head bindings through every pose, nose fit through facial presets/poses, three distinct hair sources with exactly two locks, and all eight lipstick contours. Flutter save/restore retains a new hairstyle, lipstick, earrings and the hoop together. Delivery validation checks 113 valid GLBs, with no missing/invalid assets; 55 future placeholders remain skipped and 18 existing size warnings remain. Rebuilt and launched the dedicated iPhone 17 Pro fixture preview; the Mac locked again before native tap verification. Live production purchases were not exercised by this fixture preview.

### Twelve hairstyles per avatar — 10 October 2026

Catalogue version 20 delivers twelve distinct hairstyle meshes for each body. Added six female choices and nine male choices while preserving existing IDs, prices and saved-look compatibility. New women's silhouettes include a pixie, blunt fringe bob, braided top knot, tousled curls, beaded cornrows and vintage updo. Men's additions include a textured crop, side sweep, slick back, messy shag, layered fringe, spiked quiff, swept pompadour, cornrows and braided top knot. Each body has twelve different meshes rather than colour-only copies.

Corrected scalp alignment for ten new/existing hair assets and rendered all twenty-four hairstyles against the actual avatar heads. Hair follows the shared head bone through every pose. New assets have embedded 512 px textures, real-model wardrobe thumbnails and load on selection. Most additions are below 0.8 MB; the pompadour is about 1.1 MB and the two cornrow exports about 2.1 MB each, retained as soft size warnings pending further optimisation.

Free and coin-locked choices use the existing ownership, Yes/No purchase and wallet-refresh flow. Bundled credits retain CC0 authors and CC-BY attribution from source metadata, including the stricter source notice on the braided bun.

Verification: 56 renderer tests, 40 focused Flutter tests and 17 backend unit/contract tests pass. Renderer build and asset delivery validation pass: 128 valid GLBs, no missing/invalid deliveries, 55 future placeholders skipped and 21 soft size warnings. Rebuilt and launched the dedicated iPhone 17 Pro preview. Native checks confirmed twelve choices per body, free Blunt Fringe Bob and Slick Back selection, and the 80-coin Beaded Cornrows Yes/No unlock prompt; accepting changed the fixture wallet from 600 to 520 coins and equipped the unlocked hair. Preview coins are fixtures; production purchases and physical-device performance were not exercised.

The MakeHuman 50s Women's Clothing page contains posed renders and clothing links rather than a downloadable pose asset. Those stances can guide future rig poses after the catwalk; this hairstyle update does not add poses.

### Additional characters, dressing-room scenery and pose repair — 10 October 2026

Catalogue version 22 adds Girl02 (female) and Indian Male (male), chosen in Beauty → Your character. Their CC0 MHM shape definitions are adapted to the existing fashion bodies and shared rig; these are fitted versions, not unchanged full MakeHuman scene exports. A small continuous fitting field adjusts selected wardrobe meshes on loading, avoiding a duplicate wardrobe for every character. Original bodies remain available. Character identity persists with the saved look, while changing character retains clothing, colour overrides and pose. Legacy looks default to the original character, and the backend rejects unavailable or wrong-body character IDs. Source recipes, author attribution and the repeatable offline conversion script are retained.

Male eyes previously sat behind the face surface. The base eyes and all three selectable eye assets now fit the wider, higher sockets. The studio now includes a distant wardrobe, warm vanity lights and flowers using inexpensive procedural meshes. Furniture follows the viewing side and stays at least three metres behind the avatar during rotation; it appears only in the studio scene.

Hand on Hip and Cover Star had two deformation causes: hanging male fingertips could receive leg weights, and an added wrist twist compressed the female palm. Fingertips now follow the arm/hand bones, their coverage region belongs to the arms, and both finishes inherit the forearm orientation without the extra wrist twist. All four body exports carry the corrected clips. Catalogue version 22 invalidates older cached assets. Actual-mesh regression checks verify fingertip bindings and preserve palm/finger edge lengths within 0.2% in both finishes on all four characters.

Verification: 60 renderer tests, 41 focused Flutter tests and 18 backend unit/contract checks pass; Flutter analysis and TypeScript/Vite build pass. Delivery validation reports 130 valid GLBs, no missing/invalid assets, 55 future placeholders skipped and 21 existing soft size warnings. Simulator previews use fixture wallet/scoring responses; these checks do not establish live production settlement or physical-device performance.

Rebuilt and launched the dedicated iPhone 17 Pro preview with catalogue 22. Native review confirmed Girl02 and Indian Male selection retains equipped clothing, Girl02's Hand on Hip and Cover Star catwalk finishes keep hands intact, and Indian Male's Cover Star finish no longer pulls fingertips towards the legs. Male Deep Blue and Emerald Eyes visibly change the irises. The distant wardrobe, vanity lights and flowers are visible in full-body views.
