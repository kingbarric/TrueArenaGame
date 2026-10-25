# Local bot gameplay and optional LLM communication

Branch: `codex/local-bot-gameplay`, based on local `main` (`78bce10`).

Status: initial implementation complete; local verification passed.

## Scope

Every currently supported Cyber Agent chooses gameplay actions locally. The
server remains authoritative. LLM calls are optional communication only and
must not block processing turns, phase changes or reconnect snapshots.

Retain the existing Chess engine as fallback. Reuse per-session adapters and player-visible
state; do not introduce access to opponents' private cards or secret roles.
This change does not add bots to The Tell, SlayHuud or championships or deploy
anything. The 25 October follow-ups add user selection of bot difficulty and
Stockfish as the primary Chess engine, with the Java engine as fallback, then
WHOT Monte Carlo rollouts and Ludo expectimax planning.
The next follow-up adds Scan for International Draughts and explicit
International / Optional capture choices in setup.

## Implementation

- [x] Make the runtime's action path local for all registered games. Run bounded,
  cancellable communication separately; discard stale speech after phase/word
  changes. Retain existing wire actions and server validation.
- [x] Ludo: utility scoring of legal moves, including home, captures, safety and
  exposure. WHOT: legal-card scoring, hand shape continuity, special-card rules
  and controlled randomness. Huudpoly: promote existing purchase/trade utility
  decisions to the normal gameplay path.
- [x] Draughts and Macala: bounded alpha-beta search using the real game reducers,
  including capture chains, optional/mandatory captures and relay/Oware rules.
- [x] Traitors: programmed targeting from public behavioural signals and the
  bot's own role knowledge. Keep discussion expression on the communication
  path; never expose private role knowledge in public communication prompts.
- [x] Word Bluff: select guesses from public clues using the existing offline
  matcher; use curated clue text directly. Arbitrary clue rephrasing is deferred
  because it changes the puzzle. Generic banter can still use the LLM.
- [x] Add regression tests for actual engine-approved play, tactical decisions,
  private-information boundaries, unavailable/slow LLMs and stale communication.
- [x] Run the backend unit suite, inspect the diff, and record results here.
- [x] Add a shared, compact three-dot difficulty control to the Add Cyber Agent
  sheet and directly to the Huud roster. Rookie/Pro/Legend map to the existing
  easy/medium/hard API values; Pro remains the default. Selection applies to
  the next agent added, not agents already seated.
- [x] Differentiate Word Bluff levels by clue memory (1/2/8 clues) and matching
  confidence; Legend Traitors additionally weighs public revealed-vote evidence,
  while Pro uses simpler accusation/participation signals.
- [x] Integrate Stockfish 19 through bounded reusable UCI processes, validated
  move history and server-legal moves. Retain the existing Java search as
  operational fallback. Bundle a checksum-pinned official binary, source and
  licence in both backend image builds; expose status through actuator info.
- [x] WHOT: sample unseen cards from the real deck composition and public
  counts, track public discards with recycling/reconnect handling, and compare
  legal plays and wild shape choices through bounded canonical-rule rollouts.
- [x] Ludo: finish the known dice choices, average future rolls with exact dice
  probabilities, and model each player's own utility using canonical moves,
  captures, bonus turns, eliminated players and two/three/four-player seats.
- [x] Verify rollout tactics, probability weighting, hidden-information
  boundaries, work limits and end-to-end play; run the backend suite again.
- [x] Integrate Scan 3.1 for International Draughts with a bounded Hub worker
  pool, canonical full-turn validation and queued multi-hop continuations.
  Keep optional-capture games and native-engine failures on local search.
- [x] Align captured-square blocking across server, fallback search and Dart
  chain previews, including public mid-chain state for reconnects. Expose both
  named modes while preserving the existing settings and ranked constraints.
- [x] Complete full backend verification with real Scan and Stockfish and
  record results. Current-main integration passes 859 backend tests and 110 targeted Flutter tests.

## Difficulty and follow-ups

Easy uses simpler evaluation and legal randomness; Medium uses stronger
heuristics/modest search; Hard gets deeper bounded search and less randomness.
These are initial settings, not calibrated ratings. WHOT now adds Monte Carlo
rollouts on Pro/Legend, and Ludo adds bounded expectimax. Scan serves standard
Draughts. Playing-strength calibration and optional endgame databases remain
follow-ups.

## Validation

- Current main (`1ff71d5`) is merged into `codex/local-bot-gameplay`, preserving
  the newer Huud roster, rewards, age safety and Draughts seizure behavior.
- Full backend `verify -DskipITs` passes with real Scan and Stockfish enabled:
  **859 tests across 125 suites, zero failures or errors**. One live storage
  test is skipped because `R2_ENDPOINT` is not configured.
- All **110 targeted Flutter tests** pass. Signed iOS build `2026102504` builds
  successfully. The test VPS image passes both native-engine smoke checks and
  startup validation against the existing database.
- Verification used Maven offline, the cached Byte Buddy 1.14.19 agent explicitly
  at JVM startup (the sandbox blocks Mockito self-attachment), and permission
  for localhost-only test servers used by the existing email tests.
- Added real-reducer play-throughs, mandatory/optional Draughts capture tests,
  Oware feeding and relay-capture tests, Ludo finishing and WHOT hand/stacking
  tests, Huudpoly debt handling, and public-clue/role-information checks.
- Runtime regression tests cover an unavailable model, a hung model during a
  vote, stale phase replies, one-shot rejection recovery, and cancellation on
  explicit stop or remote WebSocket closure.
- `git diff origin/main --check` passes. Deployment evidence is recorded in
  `output/phone-deploy/2026102504/manifest.json`.

## Implementation notes

The legacy `BotPrompt` and `LlmMovePicker` names and parser methods remain for
compatibility. The runtime's gameplay path does not call a model or parse its
response; only explicit communication markers can reach the provider. Local
moves retain a brief 400 ms cosmetic pause; Chess retains its own clock-aware
pacing. The initial difficulty settings need playtesting before claiming rated
strength. Word Bluff's offline matcher is intentionally less flexible with
arbitrary human clues than an LLM.

Stockfish integration, configuration, test coverage and Draughts compatibility
are documented in [STOCKFISH_INTEGRATION.md](STOCKFISH_INTEGRATION.md).
Card sampling, dice probabilities, search budgets and approximation limits are
documented in [WHOT_LUDO_BOT_SEARCH.md](WHOT_LUDO_BOT_SEARCH.md).
Scan's process pool, mode selection and capture-rule alignment are documented
in [SCAN_INTEGRATION.md](SCAN_INTEGRATION.md).

## App difficulty control validation (25 October)

- 47 permanent widget tests pass across the shared agent sheet and Huud screens;
  one additional temporary test rendered a preview for visual inspection.
- Tests verify tap/drag selection, accessible names, narrow screens with enlarged
  text, default Medium requests and explicitly selected Hard requests.
- Targeted Flutter analysis reports no issues.
- The three positions are named Rookie, Pro and Legend. "Classic" is avoided
  because it can be mistaken for a game mode. The selected title sits above
  its highlighted dot; users can tap a position or drag along the control.
