# Stockfish Chess integration

Chess Cyber Agents use Stockfish 19 for move selection. The existing Java
`ChessEngine` remains available if the native process cannot start, crashes,
returns an invalid move, exceeds its deadline, or the process pool is busy.
This keeps a match moving during an operational failure. Normal Stockfish
play does not switch engines based on the player's performance.

Stockfish runs on the backend using UCI, with no runtime network or LLM call.
It receives the public board and validated complete UCI move history, preserving
repetition information. Imported positions without matching history use FEN.
Every returned move must match the server's legal moves before submission.
The existing server reducer remains authoritative.

## Strength and resources

Rookie/Pro/Legend map to Stockfish Skill Level **2/10/20**, respectively.
Legend uses full skill within the available time; these labels do not promise
an Elo rating. All three use the same clock-aware time ceiling. Fallback uses
the corresponding existing Java engine level. With less than 50 ms left in its
move budget, it chooses an immediately legal move instead of starting a search.

The pool defaults to two persistent native processes, each using one thread,
16 MiB hash and no pondering. NNUE and process overhead require additional
memory beyond the hash allocation. Startup warms the processes and loads
NNUE weights before they serve a game. Each request resets engine game state,
sets the difficulty and sends the full position. Waiting, startup and search
share one deadline; part of the adapter's clock budget is reserved for fallback.
Failed workers are killed and can restart after a short backoff. Application
shutdown destroys the pool and pending searches.

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `STOCKFISH_ENABLED` | `true` | Enable the native primary engine |
| `STOCKFISH_PATH` | `stockfish` | Executable path; image sets `/opt/stockfish/stockfish` |
| `STOCKFISH_PROCESSES` | `2` | Maximum native workers, accepted range 1–8 |
| `STOCKFISH_HASH_MB` | `16` | Hash per worker, accepted range 1–256 MiB |
| `STOCKFISH_MAX_THINK_MS` | `1500` | Search ceiling per move, accepted range 10–10000 ms |

The clock can shorten the configured search ceiling. Increasing worker count
also increases peak CPU and memory usage; concurrent-match load testing is
needed to size production capacity. A saturated pool can cause fallback.

`/actuator/info` includes `stockfish` status: enabled, live process count,
maximum processes, successful native moves, fallback requests and last failure.
Warnings are rate-limited to once per 30 seconds. These counters reset when
the backend restarts; live process count is not a benchmark or health probe.

## Packaging

Both backend Dockerfiles run `backend/stockfish/install.sh` in an image build
stage. It downloads the official **sf_19** Linux universal release for x86-64
or ARM64, verifies the pinned SHA-256 before extraction, and checks the UCI
handshake. The complete release contents, including `Copying.txt`, `src/`,
authors and provenance, remain under `/opt/stockfish` beside the executable.
The restricted test-deployment build context now includes the installer.

Official release: https://github.com/official-stockfish/Stockfish/releases/tag/sf_19

| Archive | SHA-256 |
| --- | --- |
| `stockfish-linux-x86-64-universal.tar.gz` | `9defc0d4e55d49c65a6d042f3e571a39fcea499ade6dbe741b53b8c65e03611f` |
| `stockfish-linux-arm64-universal.tar.gz` | `fe26cfd1d9db4c8af3d21e24d9ff34cacb31c1f940085a7583da11796f2bac01` |

Local Java development can set `STOCKFISH_PATH` to an executable from the
official platform release. Without an executable, startup reports degraded
mode and Chess uses the Java fallback. No system-wide installation is required.

## Verification

Process tests use a real child process to exercise UCI framing, process reuse,
difficulty changes, crashes, deadlines, illegal/malformed replies, restart,
pool saturation and shutdown. Adapter tests exercise primary selection and
server-approved fallback; Spring tests exercise configuration, factory wiring,
actuator status and lifecycle.

Real-engine tests run when `-Dstockfish.test.path=/absolute/path/to/stockfish`
is supplied to Maven. They check mate, promotion, and server-approved play
at all three levels with zero fallback, plus the Spring-wired factory.

On 25 October, the full offline Maven `verify -DskipITs` passed: **742 tests
across 98 suites, zero failures, errors or skipped unit tests**. The real
Stockfish 19 executable was enabled for that run, and the backend jar was
rebuilt. The macOS universal test archive was verified against SHA-256
`a1f0e3bcc5a6927a11fe6fc8e54a779754645f3c2bae2cf13420fd1957adaa77`.
Shell syntax checks and `git diff --check` passed. Docker image building and
Docker integration tests were not verified: the local Docker server returned
HTTP 500 even on version queries. Nothing was deployed.

## Draughts is a separate engine

Standard Stockfish plays Chess and cannot be used for this game's Draughts.
The later Draughts implementation adds **Scan 3.1** for International mode,
with the existing search for Optional capture and operational fallback. See
[Scan integration and modes](SCAN_INTEGRATION.md) for rules alignment, full
capture-path validation, deployment configuration and test coverage.
