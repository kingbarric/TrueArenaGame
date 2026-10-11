# Monopoly — first playable implementation

**Branch: `codex/monopoly-classic-depth`.** The game description and approved concept were committed in `9a6626c` before application or backend code was added.

## Implemented

- **Classic 40-space board for 2–8 selected players:** automatic bank, starting cash, server dice, GO, purchases, round-roster auctions, rents, doubles, jail and both shuffled card decks.
- **Property management:** even building and selling, 32-house/12-hotel bank inventory, group sales when a hotel cannot be exchanged for replacement houses, mortgages, redemption and mortgage transfer interest.
- **Private bilateral trades:** cash and deeds, atomic acceptance with fresh ownership/funds checks, public completed exchanges. Pending offers and future randomness never enter spectator snapshots.
- **Debt and bankruptcy:** cash-raising decisions, creditor transfers and auctions of bank-held estates. Conservative 180-second decision timeouts; disconnecting alone never bankrupts a player.
- **Huud integration:** separate admission and play requests, admin selection and start, locked match roster, viewers, existing voice/mic moderation, persistent Huud chat and return to the same Huud after a game.
- **A host may watch:** in a waiting Monopoly roster the host can release their own seat, select up to eight other players, open the lobby and start. Only that room's authenticated host gains the control connection without a player seat. Monopoly does not transfer game administration when the host briefly disconnects. Other games retain their existing lobby behavior.
- **Bold classic screen:** warm walnut material, slight overhead perspective, beveled ivory tiles, raised colour bands, green felt, shaded metal tokens, houses/hotels, dice, heavy cash/decision labels, zoom, a large deed inspector and reduced-motion token transitions.
- **Visible bottom chat:** the recent message, text box and Send control remain on screen. History opens separately. Huud membership permissions govern sending; failed sends retain the draft.
- **Temporary network loss:** the board and recent chat are cached per account and room. Private trade offers are excluded from the saved view. Actions remain disabled until a live connection and snapshot are available.

![Actual Flutter phone layout](phone-preview-v1.png)

The preview is a 390 × 844 phone viewport at 2× resolution. Its sample positions/cash come from the real engine's canonical board snapshot, not from a second board definition.

## Validation

- **26 Monopoly rule tests**, including auction turn authority, idempotency, even building, stock shortages, stale/private trades, mortgage interest, cards, jail, bankruptcy and twelve 4,000-decision simulations.
- **API snapshot and capacity tests:** reconnect delivers the full board and only the subscriber's own private offers; spectators receive no deck, seed or offer data. Huud capacity comes from the engine's limit.
- **35 Huud database integration tests:** temporary local PostgreSQL and Redis; includes separate join/play requests, admin-only start, player mic permission, chat/audience persistence and an organising host without a game seat.
- **Migration V48 applied successfully.** A separate transaction tested that the same migration adds Monopoly while preserving an existing SlayHuud registration.
- **Local Android arm64 debug APK compiled successfully.**
- **65 Flutter screen/layout and Huud regression tests passed:** active decisions, spectator/read-only controls, saved offline views, cached-snapshot reconnect handling, persistent chat endpoints, private-offer cache exclusion, large text, narrow phones and keyboard placement. Existing Huud/mic/resume tests run alongside them.

Reproduce the core checks from the repository root:

```sh
./backend/mvnw -f backend/pom.xml -pl ta-api -am test
cd app
flutter test test/monopoly_game_test.dart test/monopoly_table_test.dart test/huud_space_test.dart test/huud_mic_request_test.dart test/game_resume_test.dart
```

The database suite is `HuudSpaceIT` under `ta-app`. It supports temporary external database properties (`it.r2dbc.url`, `it.jdbc.url`, `it.db.user`, `it.db.password`, `it.redis.port`), used here because this machine's Docker version is newer than the existing Testcontainers client's supported API.

## Release boundaries

**This is isolated branch work.** Production deployment, installation on the phone and a merge into main are separate release steps. The app must run with the corresponding Monopoly-enabled backend.

The shared ordinary-game runtime remains in memory, as for the existing games. **Reconnect to a running server is supported; recovery after a server process restart is not added here.** Durable checkpoints should be addressed before relying on long Monopoly matches across backend deployments.

**Cyber Agents:** the host can add agents from the Huud roster. They choose only engine-validated actions from their own player snapshot, including purchase/auction, jail, debt, property management and trade responses. An economical fallback keeps games moving without model credentials. Private offers stay out of spectator state and Huud chat is never passed to the move picker.

**Deliberate V1 limits:** no agent-initiated trades, no simultaneous building-stock auctions, no jail-card trading, and no parallel matches inside one Huud. A large property sheet and private offer composer provide the first management UI; further polish can follow human multiplayer testing.

The wood texture is a generated material, with its exact prompt and generation mode in [the asset note](../../app/assets/images/monopoly/README.md). The bundled fonts retain their [license](../../app/assets/fonts/monopoly/LICENSE.txt).

## Test mirror and background fix

The user requested a complete production PostgreSQL snapshot in isolated test. See [test setup](../../infra/TEST_ENVIRONMENT.md). The new **V49** migration adds the already offered Blank background to the database constraint; V43 previously rejected it during updates. All public HTTP/game errors and app error presentations use **“Error has occurred, try again later.”** Status codes and safe machine outcomes remain available for app navigation; SQL and exception details stay in server logs.

## Phone layout and cinematic music — 11 October 2026

- The board now uses the available phone width with a deeper perimeter and a smaller centre. Tile names and prices are bold; short labels such as Chance and Luxury Tax stay readable without splitting their words, while long property names use balanced lines. All 40 spaces share the same drawing, tap and animation geometry.
- Removed the separate Your Turn banner. The active player's card carries the gold highlight and the timer/paused state sits in the header. Trade lives in the settings menu; the later update below moves Properties beside Chance on the board.
- Reuses `GameVoiceControl` for the existing mic access/request/moderation behavior and the ordinary `PAUSE_TOGGLE` transport for pause/resume. Pausing disables move controls until the server resumes the match.
- Reuses Chess's `TableChatPanel` at the bottom, initially minimised with the latest message visible. Expand it to read/send Huud chat; collapse it for more space. Huud message persistence and offline cache remain unchanged. Smaller screens, enlarged text and the keyboard retain scrolling as a fallback.
- Bundles Kevin MacLeod's **Drums of the Deep**, a 174-second cinematic percussion/strings track, normalised to −22 LUFS and played at 14% volume. It loops locally without a network dependency and honours the shared persisted music toggle. Settings includes the existing music/game-sounds toggles and attribution/license/modification notice. See [music credits](../../app/assets/music/CREDITS.md).
- This update changes the app only; it requires no backend or database deployment.

## Icon, dice and landing inspection — 11 October 2026

- Uses the exact user-provided cash/top-hat mascot PNG as the Monopoly catalogue
  badge. The source image is bundled unchanged for offline use.
- A raised **Properties** button sits inside the board beside Chance and opens
  the existing property/building sheet. It replaces the menu entry.
- The dice are clickable on the active player's roll phase, with shaded front,
  top and side faces. They tumble while waiting for the server, settle on its
  actual values, and then animate the token to the destination. Repeated values
  are supported through `DICE_ROLLED`; cash-only updates do not replay animation.
- After the token arrives, a gold circular magnifier shows the actual tile/token
  for **three seconds**, then disappears. It does not intercept board taps.
  Reduced-motion settings skip tumbling/movement and retain landing inspection.
- The shared bottom chat, voice/mic, settings, offline snapshot and server-side
  game authority remain in use.

Validation: **318 full Flutter tests passed**, including the new Properties,
settled dice, repeated-roll and three-second landing checks. The changed Flutter
files have no analyzer issues. Rendered phone layout and magnifier were inspected.

The branch policy now reserves **main for isolated test** and **release for
production**. Release was preserved from pre-merge main at `b2dc34d` before
these changes. See [deployment policy](../../infra/TEST_ENVIRONMENT.md).
