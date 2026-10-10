# SlayHuud: handoff for the next agent

Written 10 October 2026. Read this first, then [SLAYHUUD_IMPLEMENTATION.md](SLAYHUUD_IMPLEMENTATION.md) for the full design (architecture, bridge protocol, lifecycle, scoring, API, abuse controls).

SlayHuud is a styling competition inside PlayHuud. Players dress a 3D avatar for a theme, show it off on a runway, submit it, and get a system score and/or community votes. Wins earn coins, XP and wardrobe unlocks.

## 1. Branches

| Branch | Remote | What it is |
|---|---|---|
| `codex/slayhuud` | `origin/codex/slayhuud` | Codex's working line. 24 commits since it forked from `feature/huud-session` at `8aade42` (8 Oct). Still being worked on. |
| `feature/slayhuud-shipping` | `origin/feature/slayhuud-shipping` | Branched from `codex/slayhuud` at `6c89905` (10 commits behind its tip), plus `da22532` (app size, rating off, JPEG snapshots) and this doc. **Continue here.** |
| `feature/huud-session` | `origin/feature/huud-session` | The main product line. SlayHuud is **not** merged into it yet. |

Rules the user has set:

- Do not commit to `codex/slayhuud` or edit its worktree (`/private/tmp/TrueArena-slayhuud`) while Codex is active.
- When the user says **"Codex is done"**: merge `codex/slayhuud` into `feature/slayhuud-shipping`, run `npm run build` in `slay-renderer`, resolve conflicts in generated files (`app/assets/slay_renderer/catalog.json`, `index.html`, `starter/`, `asset-manifest.json`) by rebuilding rather than hand-merging, then run all tests and report. Get explicit approval before that merge.
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

## 3. Not committed yet: Codex's career mode

Codex's worktree has uncommitted work that is **not on any branch** (as of 15:19 on 10 October). It adds a solo career: chapters of challenges ("Your first impression", "Coffee date", "The weekend edit"…) with personal bests.

- New: `app/assets/slay_renderer/career.json`, `backend/ta-api/src/main/resources/slay/career.json`, `SlayCareerCatalog.java`, `SlayCareerService.java`, `SlayCareerCatalogTest.java`, `slay_career_screen.dart`, `app/lib/dev/slay_preview_career.dart`, `app/test/slayhuud_career_test.dart`, `V38__slay_solo_career.sql` (`slay_solo_bests` table).
- Modified: `slay_hub_screen.dart`, `slay_models.dart`, `slay_studio_screen.dart`, `slay_style_report.dart`, `slayhuud_preview.dart`, `SlayController.java`, `SlayService.java`, `SlayHuudIT.java`, `slay-renderer/scripts/bundle.mjs`.

Wait for Codex to commit it before you depend on it.

## 4. Codex commits newer than the shipping branch

These are on `codex/slayhuud` and will come in at the merge:

```
6bf0b2c Speed up SlayHuud runway and preview four finishing poses
904a795 Evaluate SlayHuud styling scores and explain deductions
c4a5e42 Add five women's shoe styles and saved garment colour choices
c180681 Fit both tube tops to the avatar and mask covered chest skin
c306884 fix(slayhuud): remove duplicate wardrobe groups and entries
c46e307 feat(slayhuud): add female beauty choices and coin-locked hairstyles
126c3ff Add twelve fitted hairstyle choices for each SlayHuud avatar
4a6b194 Add fitted SlayHuud characters and studio scenery; repair eyes and hand poses
8a5045b Fit male trouser waistbands and remove unavailable SlayHuud themes
6060ae3 Fix male shirt and trouser layering through poses and catwalk
```

They add new GLBs and thumbnails, so the merge **must** be followed by `npm run build` to publish them through the art-delivery pipeline. Otherwise the app will reference files that are neither bundled nor in the manifest.

## 5. Known blockers before merging into `feature/huud-session`

1. **Migration numbers clash.** SlayHuud uses `V37__slayhuud.sql` and (uncommitted) `V38__slay_solo_career.sql`. `feature/huud-session` already has `V39`–`V46`. Renumber them to the next free numbers (currently `V47`, `V48`) before merging. Check prod's Flyway history first. Never edit a migration that prod has already applied.
2. **Overlapping files with `feature/huud-session`:** `ChampionshipService.java`, `ChampionshipRow.java`, `GameOrchestrator.java` (also uncommitted on huud-session), `HuudService.java`, `huud_screen.dart`, `huud_models.dart`, `home_screen.dart`, `game_select_screen.dart`, `RoomService.java`, `RatingService.java`, `application.yml`, `pubspec.yaml`. Expect conflicts.
3. **Repo size:** about 80 MB of source GLBs are in git history (largest single file 8 MB). The plan is to strip them from history before the final merge, keeping the hashed delivery files outside git.
4. **Vendored WebView plugin:** `app/vendor/flutter_inappwebview_android` (207 files) is a patched copy for AGP 9. `slay_stage.dart` is now its only user, so switching to the official `webview_flutter` would remove it. Do this after Codex is done.
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

1. Wait for "Codex is done", then merge `codex/slayhuud` into `feature/slayhuud-shipping`, rebuild, and run every suite above.
2. Renumber the migrations to the next free versions after checking prod.
3. Replace `flutter_inappwebview` with `webview_flutter` and drop the IndexedDB cache.
4. Rsync `website/slay-assets/` to the VPS and check real downloads and visual parity on a device.
5. Strip source GLBs from history, then ask the user about merging into `feature/huud-session`.
