# SlayHuud: handoff for the next agent

Written 10 October 2026. Read this first, then [SLAYHUUD_IMPLEMENTATION.md](SLAYHUUD_IMPLEMENTATION.md) for the full design (architecture, bridge protocol, lifecycle, scoring, API, abuse controls).

SlayHuud is a styling competition inside PlayHuud. Players dress a 3D avatar for a theme, show it off on a runway, submit it, and get a system score and/or community votes. Wins earn coins, XP and wardrobe unlocks.

## 1. Branches

| Branch | Remote | What it is |
|---|---|---|
| `codex/slayhuud` | `origin/codex/slayhuud` | Codex's line. Codex has stopped; the user handed its work over. Its tip `6060ae3` is merged into the shipping branch. |
| `feature/slayhuud-shipping` | `origin/feature/slayhuud-shipping` | Everything on `codex/slayhuud` up to `6060ae3`, Codex's unfinished career work (carried over), and the shipping, career, scenery and UI work below. **Continue here.** |
| `feature/huud-session` | `origin/feature/huud-session` | The main product line. SlayHuud is **not** merged into it yet. |

Rules the user has set:

- Do not commit to `codex/slayhuud` or edit its worktree (`/private/tmp/TrueArena-slayhuud`).
- After any art or catalogue change, run `npm run build` in `slay-renderer`; resolve conflicts in generated files (`app/assets/slay_renderer/catalog.json`, `index.html`, `starter/`, `asset-manifest.json`) by rebuilding rather than hand-merging.
- **UI direction:** the user rejected Codex's rigid panel UI. SlayHuud screens should be playful and game-like, matching PlayHuud: cabinet cards (ink outline, hard shadow), `Bouncy` presses, sparkles, celebrations. Use the kit in `slay_ui.dart`.
- Merging into `feature/huud-session` is a separate decision the user has not made.
- Ask before any phone install, prod deploy, TestFlight or APK upload.

## 2. What is built

### Game modes (all working against the real backend; tested in a fixture preview and integration tests)

- **Solo / client briefs:** style for a theme, get a deterministic server score and a once-per-theme-per-UTC-day reward.
- **Style Battle:** 1v1, anonymous community pairwise voting, results, rematch, draws.
- **Groups:** 4, 6, 8, 10 or 16 players, same voting/settlement engine.
- **Slay or Pass:** contestants vs 3–6 judges of the opposite avatar body. Lowest score is eliminated each round, the last two go to a Red Carpet final.
- **Daily / weekly challenges:** async entry window followed by a voting window. No opponent needs to be online.
- **Fashion Cups:** knockout brackets (4–128) built on the existing `championships` tables.

### 3D studio and renderer (`slay-renderer/`, Three.js in a WebView)

- Converted MakeHuman male and female avatars with eyes, brows, skin tones and face presets.
- Wardrobe: fitted outfits, male separates (shirts/trousers with waistband fit and layering), dresses and tube tops masked so skin doesn't show through, women's shoes (five styles) and men's shoes fitted per body, 12 hairstyles per body, female beauty (lipstick, earrings, eye colour), bags, watches, saved garment colours, coin-locked items.
- Studio: rotate/pinch, front/back/face camera presets, explicit full-rotation controls, poses, backgrounds/scenery, draft saved locally.
- **Show off:** an 8.6 s runway walk (leg IK, level feet), finishing pose and full turn, then a snapshot, then save and score or submit. Stop, leaving or backgrounding cancels it.
- Judging replays each submitted 3D look one at a time; a saved photo is the fallback.

### Scoring (`backend/ta-engine/.../slay/SlayRules.java`)

- System score: theme tag fit 50%, required categories 30%, colour harmony 10%, completeness 10%. 85/65/40 for 3/2/1 stars.
- The style report now explains each deduction (`slay_style_report.dart`).
- Community votes use regularized Bradley–Terry, blended with the system score by each challenge's `systemWeight`. Too few votes means the system score is used and the result is unranked.

### Platform wiring

Home tile, game picker, Huud game requests (`HuudService`, `huud_screen.dart`), room join and spectate, the coin ledger, profile badges and achievements, championships, and the `SLAY_CHANGED` event on the existing room WebSocket.

### Shipping changes (only on `feature/slayhuud-shipping`, commit `da22532`)

- **Art on demand:** the app bundles only a 2.7 MB starter pack instead of ~83 MB. `npm run build` compresses every GLB (Meshopt + WebP, triangle order kept), checks each against its source, writes content-hashed files to `website/slay-assets/` (git-ignored; rsync to the VPS, served by Caddy at `https://playhuud.com/slay-assets/`) and writes `backend/ta-api/src/main/resources/slay/asset-manifest.json`. `app/lib/features/slayhuud/slay_assets.dart` serves the renderer from the starter pack, a disk cache or a SHA-256-checked download. **Publish `website/slay-assets/` before deploying a backend whose manifest names new files.**
- **Slay rating off:** `slayhuud` is not in `truearena.competitive.rated-game-types` (`COMPETITIVE_RATED_GAMES`). Matches still record wins, placements and unlocks. The hub hides the rating chip while it is off.
- **JPEG snapshots:** raw ~100 KB `image/jpeg` uploads capped at 512 KB on their own route; the global 2 MB codec limit was removed. Old PNG rows still serve.

## 3. Solo career (done on the shipping branch)

The brief the user gave is the product direction: a fashion career with progression, competition, rewards, replay and unlocks.

- **One character for the whole career.** The player picks a character once ("Who’s your star?", a live 3D picker); `POST /slay/career/start` stores body + character on `slay_profiles` (`V47__slay_solo_career.sql`). The server refuses career looks on any other body or character; the studio hides the body/character switch in career mode.
- **Five stages**, each with a dressing room and an event venue drawn by the renderer: Starter Studio (bedroom vanity → home photo wall), City Style (boutique fitting room → city street), Nightlife (club green room → rooftop at night), Luxury Events (hotel suite → ballroom), Fashion Week (backstage mirrors → runway). Styling uses the room; the catwalk and final photo use the venue.
- **Stage wardrobes.** `career.json` `chapters[].collection` opens clothing per body as each stage unlocks; `rewards.four/five` pools give a piece on a first 4★ and a first 5★ per event. Hair and beauty are not gated. The studio shows locked pieces with their reason ("Opens at Nightlife", "Earn 4★ in City Style"). `SlayCareerCatalogTest.everyEventCanEarnFourStarsWithOnlyItsStageWardrobe` proves every event is winnable with only its stage's clothes, for both bodies.
- **Rank-up** (Unknown → Rising Star → Trendsetter → Style Icon → Fashion Elite → Global Star) opens the next stage's collection and poses.
- **Competition:** personal bests, Daily Slay, streak, and global/friends standings (`GET /slay/career/{event}/leaderboard`, also returned with each score).
- **UI:** `slay_career_screen.dart` (picker, rank card, Next Up, Daily Slay, winding stage map, invitation-style briefs), `slay_results.dart` (count-up score, popping stars, fireworks, feedback, rewards, unlocks, rank-up, standings).

Not built yet (outside the brief's V1 list): weekly events, flash/VIP events, streak rewards, creativity/pose/accessory scoring categories.

**Art gap:** Fashion Week opens no new clothing, and the men's wardrobe is thin (7 outfits, 3 shirts, 4 trousers, 2 shoe styles), so later men's stages reuse pieces. New designer/luxury pieces for both bodies would fill this; add them to the matching `chapters[].collection` and rerun the winnability test.

## 4. Codex's work

Codex's commits up to `6060ae3` are merged (`1e5576f`), and its uncommitted career work was carried over unchanged in `05c5d5c`, apart from renumbering its migration to V47 and updating tests to the current constructor. Then `4fafc58` (career rules), `3c18dc3` (stage scenery) and the UI rework build on it.

## 5. Known blockers before merging into `feature/huud-session`

1. **Migration numbers.** Production has already applied `V37__slayhuud.sql` (byte-identical to this branch's file) and an unrelated `V38__social_huud_sessions.sql`; `feature/huud-session` tolerates both with `ignore-migration-patterns: "*:missing"`. So **keep `V37__slayhuud.sql` exactly as it is**: renaming it would make Flyway run it again on prod and fail on existing tables. The career migration is `V47__slay_solo_career.sql`; if `feature/huud-session` has used V47 by the time you merge, renumber it to the next free version (it has never been applied anywhere). Check prod's Flyway history before deploying.
2. **Overlapping files with `feature/huud-session`:** `ChampionshipService.java`, `ChampionshipRow.java`, `GameOrchestrator.java` (also uncommitted on huud-session), `HuudService.java`, `huud_screen.dart`, `huud_models.dart`, `home_screen.dart`, `game_select_screen.dart`, `RoomService.java`, `RatingService.java`, `application.yml`, `pubspec.yaml`. Expect conflicts.
3. **Repo size:** about 80 MB of source GLBs are in git history (largest single file 8 MB). The plan is to strip them from history before the final merge, keeping the hashed delivery files outside git.
4. **Vendored WebView plugin:** `app/vendor/flutter_inappwebview_android` (207 files) is a patched copy for AGP 9. `slay_stage.dart` is now its only user, so switching to the official `webview_flutter` would remove it. Codex has stopped, so this can be done now.
5. **Redundant cache:** the renderer's 32 MB IndexedDB cache (`slay-renderer/src/cache.ts`) duplicates the `SlayAssets` disk cache and can go.

## 6. Launch gates (still open)

- Art: 55 catalogue slots still have no models, so `developmentAssets=true`. Production needs every slot filled, versioned HTTPS URLs and `developmentAssets=false`.
- Real-device profiling (iPhone 12+ and a mid-range Android): frame rate, memory, thermal, load time. Only simulators have been used so far.
- Screenshots are client-rendered and not proven to match the submitted outfit. Decide on anti-cheat/moderation before turning Slay rating back on.
- No staff UI for reviewing reports; no automated image moderation.
- Snapshots live in Postgres `BYTEA`; move them to object storage before large-scale launch.
- Async voting needs normalized ballots, pagination and load tests for mass participation. Room fan-out is single-pod.
- Not yet verified on device: real downloads from playhuud.com and visual parity of the compressed models.

## 7. Where things live

| Area | Paths |
|---|---|
| Flutter feature | `app/lib/features/slayhuud/` (`slay_hub_screen`, `slay_studio_screen`, `slay_competition_screen`, `slay_cups_screen`, `slay_stage`, `slay_runway`, `slay_wardrobe`, `slay_style_report`, `slay_assets`, `slay_models`, `slay_theme`, `slay_pose_picker`, `slay_colour_picker`, `slay_game_menu`) |
| Fixture preview | `app/lib/slayhuud_preview.dart`, `app/lib/dev/slay_preview_scoring.dart` |
| Flutter tests | `app/test/slayhuud_*_test.dart`, `app/test/home_game_theme_test.dart` |
| Backend API | `backend/ta-api/src/main/java/app/truearena/api/slay/` (`SlayController`, `SlayService`, `SlayCatalog`, `SlayScheduler`, `SlayErrors`), `resources/slay/catalog.json`, `asset-manifest.json` |
| Pure rules | `backend/ta-engine/src/main/java/app/truearena/engine/slay/` (`SlayRules`, `SlayCompetition`), `engine/rating/PairwiseOutcomes.java` |
| Schema | `backend/ta-persistence/src/main/resources/db/migration/V37__slayhuud.sql` |
| Integration test | `backend/ta-app/src/test/java/app/truearena/SlayHuudIT.java` |
| Renderer | `slay-renderer/src/` (`main`, `studio`, `avatar`, `rig`, `poses`, `showcase`, `presentation`, `coverage`, `variant-fit`, `male-separates`, `item-colours`, `look-state`, `glb`, `cache`), build/asset scripts in `slay-renderer/scripts/`, tests in `slay-renderer/test/` |
| Bundled output | `app/assets/slay_renderer/` (`index.html`, `catalog.json`, `starter/`); source art in `assets/` is not bundled |
| Asset docs | `docs/SLAYHUUD_ASSETS.md`, `docs/SLAYHUUD_ASSET_CREDITS.md`, `docs/SLAYHUUD_PLAN.md` |

## 8. Build and test

```sh
# Renderer: rebuild bundle, starter pack, hashed delivery files and manifest
cd slay-renderer && npm ci && npm run build && npm test

# Flutter
cd app
flutter analyze lib/features/slayhuud lib/slayhuud_preview.dart
flutter test test/slayhuud_*_test.dart test/home_game_theme_test.dart
flutter run -t lib/slayhuud_preview.dart --dart-define=API_BASE=http://localhost:55667   # fixture UI, no server

# Backend
cd backend && mvn -q test
# SlayHuudIT: Testcontainers cannot create containers in this sandbox; point it at
# disposable local services with -Dit.r2dbc.url, -Dit.jdbc.url, -Dit.db.user,
# -Dit.db.password and -Dit.redis.port instead.
```

Last recorded results on `feature/slayhuud-shipping` (10 October): 42 renderer tests, 22 SlayHuud/home Flutter tests, 248 backend unit tests and the 10 `SlayHuudIT` tests passed. Codex's newer commits have their own renderer tests (`male-trouser-fit`, `hair-expansion`, `item-colours`, `female-beauty` and others) that have not been run against the shipping changes.

## 9. Suggested next steps

1. Try the career in the fixture preview on a simulator (`flutter run -t lib/slayhuud_preview.dart --dart-define=API_BASE=http://localhost:55667`) and on a device; check the stage scenery, picker and results feel.
2. Commission designer pieces for Fashion Week and more men's clothing; slot them into `career.json`.
3. Replace `flutter_inappwebview` with `webview_flutter` and drop the IndexedDB cache.
4. Rsync `website/slay-assets/` to the VPS and check real downloads and visual parity on a device.
5. Strip source GLBs from history, then ask the user about merging into `feature/huud-session` (renumber V47 if needed).
