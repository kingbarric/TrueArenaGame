# Scan and Draughts game modes

The Draughts setup sheet offers two explicit choices:

- **International:** captures are compulsory and the maximum capture count
  must be taken. Cyber Agents use Scan 3.1, with the current Java search as
  operational fallback.
- **Optional capture:** a player may choose a quiet move even when a capture
  exists. Cyber Agents use the current Java search, which understands this
  house rule. Scan is never sent these positions.

The existing casual default remains Optional capture; ranked matches remain
locked to International by the client and server. This does not change bot
eligibility for ranked games or championships. The existing `mandatoryCapture`
wire setting is retained, so explicit settings in existing rooms keep their
meaning. Both modes require a started capture sequence to be completed.

## Rules and move translation

Scan uses Hub protocol version 2. Server board indices 0–49 map to standard
Hub squares 1–50; server side A is Hub black and side B is Hub white. This
preserves both movement directions without rotating the board.

Hub capture notation lists the origin, final destination and captured squares
in any order. It does not list the intermediate landing squares. `ScanMoveCodec`
resolves a matching complete path through the real `DraughtsModule`, including
maximum-capture legality and promotion at the end of a sequence. A result is
accepted only when its complete path agrees with the server. The adapter then
plays ordinary MOVE actions one hop at a time, checking each expected board
before reusing the queued continuation. Undo, a changed board or a changed
mode invalidates that continuation.

International capture rules also require captured squares to remain blocked
until the whole sequence ends. The previous reducer and Dart preview removed
that restriction along with the displayed victim, allowing some kings to
reverse across a square they had just captured. They now track these squares
through the chain. Public snapshots add `capturedSquares` and `remainingCaptures`
so reconnecting clients and fallback search preserve the exact continuation.
Blockers clear when the turn ends or an undo is accepted. Both modes use this
capture-sequence rule; Optional capture changes whether a sequence must start.
Optional chains also reject a quiet move offered in place of a required jump.

## Strength and process limits

| Difficulty | Scan depth ceiling | Native request budget |
| --- | --- | --- |
| Rookie | 4 | 150 ms |
| Pro | 8 | 450 ms |
| Legend | 99, effectively time-limited | 1300 ms |

The process search also obeys `SCAN_MAX_THINK_MS` and reserves request time
for communication and full-path validation. Default search times are at most
about 100/400/1200 ms for the three levels. These settings are not Elo ratings.
Fallback uses the corresponding Java depth 1/3/5 and 30/100/250 ms budget.

The bounded pool defaults to two reusable native processes. Each uses one
thread, 2^20 transposition entries (16 MiB), no pondering, no opening book and
no endgame bitbases. Evaluation data and process overhead use additional memory.
Scan is strong without bitbases; large endgame databases are not bundled by
this change. Playing-strength and concurrency calibration remain necessary.

Workers initialise at backend startup, then clear unrelated game state before
each request. Waiting, startup and search share one deadline. Crashes, malformed
or illegal moves, exhausted capacity and timeouts return control to Java search;
failed processes are killed and restart after a one-second backoff. Shutdown
destroys workers and cancels searches. Standard positions entered mid-chain
without a verified queued plan use the local reducer-based continuation.

Only the current public position is sent to Scan. Cross-turn repetition history
is not currently forwarded; Scan can still detect cycles within its own search.
The game retains its existing draw/undo behavior.

| Variable | Default outside Docker | Purpose |
| --- | --- | --- |
| `SCAN_ENABLED` | `true` | Enable the primary engine for International |
| `SCAN_PATH` | `scan` | Executable; Docker sets `/opt/scan/scan` |
| `SCAN_DIRECTORY` | `.` | Working directory containing `scan.ini` and `data/`; Docker sets `/opt/scan` |
| `SCAN_PROCESSES` | `2` | Workers, accepted range 1–8 |
| `SCAN_TT_SIZE` | `20` | Transposition-table exponent, accepted range 16–24 |
| `SCAN_MAX_THINK_MS` | `1200` | Search ceiling, accepted range 10–10000 ms |

`/actuator/info` exposes `scan` status: enabled, live processes, capacity,
successful native turns, fallback requests and last failure. Warning logs are
rate-limited. These process counts are not a health probe; counters reset with
the backend. A local developer without Scan can use Java fallback or configure
an absolute executable path and its data directory.

## Packaging and source

Both backend Dockerfiles use `backend/scan/install.sh` to download and verify
the official Scan 3.1 archive, then compile its unmodified C++14 source for the
target architecture. The build avoids x86-only compiler flags, supporting ARM64
and x86-64. The runtime includes libstdc++, the binary, configuration, evaluation
data, complete source, GPLv3 licence, installer and provenance. The restricted
test-deployment build context now includes the installer. No runtime download
or LLM call is required.

Archive: https://hjetten.home.xs4all.nl/scan/scan_31.zip

SHA-256: `7579cc16cb3650a6bc5e98035a4052fe7941959050f72e4c4b42fc6fde02ece4`

Author-provided distribution and manual: https://hjetten.home.xs4all.nl/scan/scan.html

## Verification

Scan was compiled locally from the verified official archive and exercised
through real Hub processes. Tests cover opening moves from both sides,
server-approved play at all three difficulty levels, flying-king blockers, path reconstruction,
mid-chain snapshots, selected difficulty and mode routing, fallback, process
reuse, crash recovery, timeouts, pool saturation, shutdown and Spring wiring.

Full backend `verify -DskipITs` passed with both real native engines enabled:
**775 tests across 104 suites, zero failures, errors or skipped unit tests**.
The backend jar was rebuilt with the Scan engine and status wiring included.

All **49 targeted Flutter tests** pass, including both mode choices, ranked
locking, capture chains, mirrored rules and replay/turn UI. Flutter analysis
found no errors or warnings; it reports five existing brace-style informational
notices on unchanged lines in the lobby screen.

Docker remains unavailable locally (HTTP 500 on `docker version`), so the image
build and Docker integration tests remain unverified. Installer shell syntax
checks pass. Nothing was deployed.
