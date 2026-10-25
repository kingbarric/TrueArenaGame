# WHOT Monte Carlo and Ludo expectimax

These strategies extend the local gameplay boundary: server-validated moves
come from algorithms, while optional LLM communication runs independently.
Both strategies use the authoritative game modules for simulated moves. They
construct their search states from allowlisted player-visible snapshot fields.

## WHOT

Pro and Legend compare legal card plays, including all five possible shape
calls when playing a wild. For each comparison they sample a possible deal:

1. Infer the number of combined decks from public hand sizes, discard count
   and market size; use the module's real card composition and wild setting.
2. Remove the bot's own cards and known current discards with their correct
   multiplicity. Publicly observed discards are remembered by pile position.
3. Shuffle the unknown cards, assign opponents their public hand counts, sample
   any unobserved discards, and use the remainder as the simulated market.
4. Play bounded continuations through `WhotModule`. Rollout players choose
   from their own sampled hands using legal-card heuristics with some variety.
   They cannot inspect other sampled hands when selecting their moves.

Candidates in one comparison receive the same sampled deal and policy seed.
Only a completed comparison across all candidates updates the result. Terminal
wins/losses dominate the hand-count evaluation at the rollout horizon. A single
legal action is returned directly. The root plays a matching card when one is
available, rather than searching voluntary draws.

The model uses uniform deals consistent with known card composition. It does
not infer a person's hand from their dialogue, gestures or past willingness
to draw. This is flat Monte Carlo, not a complete game-theoretic solution or
an ISMCTS tree. Unknown hands are hypotheses, never server hands.

| Level | Samples per candidate | Maximum rollout actions | Known discard memory | Time / total transitions |
| --- | --- | --- | --- | --- |
| Rookie | No rollouts | — | — | Existing legal heuristic and controlled randomness |
| Pro | 8 | 12 | Latest 12 observed cards | 100 ms / 4,000 |
| Legend | 32 | 24 | All observed cards still discarded | 250 ms / 16,000 |

Limits are ceilings: search stops earlier when necessary. Discard memory
resets on a market reshuffle, a shrinking pile or contradictory overlapping
snapshots; repeated snapshots do not duplicate known cards. On reconnect,
unobserved discards remain unknown. Incomplete or inconsistent snapshots retain
the existing legal heuristic.

### The Tell

Cyber Agents can fill any of the 4, 6 or 8 seats, including a human's partner.
The first member of an all-agent pair proposes a private random symbol; the
other confirms it. Agents accept a human partner's choice and reconfirm when
it changes. Finalists choose fresh symbols for the final.

An agent signals a valid whole-hand shape/value set using the host's rule and
minimum, even off turn. It can buzz its partner's agreed symbol within the
three-second window, and ignores different symbols, expired signals and
obviously undersized hands. It trusts the partner's agreed symbol without
seeing their cards. Opponent signals are not blindly buzzed; this policy does
not yet learn opponent tells or generate decoys.

Rookie uses team-aware legal heuristics, preferring moves that leave a Tell
set and avoiding attacks on its partner. Pro/Legend use the same bounded
Monte Carlo limits above, with the actual Tell reducer, public team membership,
qualification/elimination state and team win evaluation. Rollouts model card
play and value possible sets; live signaling and buzzing use the separate
local signal strategy. No other player's hand, opponent secret signal, actual
market order or server-only signal-validity flag enters a decision. LLMs have
no role in card plays, signal agreement or buzz decisions.

## Ludo

Pro and Legend search every distinct legal choice for the known dice, including
both orders and using both dice before reaching a future-roll boundary.
Equivalent choices involving tokens at the same progress are merged. Each
future chance node enumerates 21 unordered dice pairs, representing all 36
ordered outcomes: doubles have probability 1/36, other pairs 2/36.

The chance transition shares the module's roll-result logic. Production ROLL
still generates dice from the server seed; no client action can specify a
roll. Search never reads that seed or uses the real future dice sequence.
Canonical moves handle release, safe squares, blocking, the game's capture
rule that finishes the attacker, remaining-die restrictions, exact finishing,
double-six bonus rolls and eliminated players.

At decision nodes each player maximises their own evaluated outcome. For more
than two players this uses a utility vector, rather than assuming opponents
cooperate against the bot. Evaluation weighs finishing, progress, release,
safety, exposure and opponents' progress; a game win dominates these scores.

| Level | Future roll horizon attempted | Width after future rolls | Time / visited nodes |
| --- | --- | --- | --- |
| Rookie | No expectimax | — | Existing immediate utility and controlled randomness |
| Pro | 1 | Best 2 choices per decision | 100 ms / 6,000 |
| Legend | Up to 2 | Best 3 choices per decision | 300 ms / 20,000 |

Future decision width is pruned by immediate utility; known-dice choices are
fully searched. Consequently this is bounded, approximate expectimax. A cache
shares equivalent positions. Iterative horizons commit only after all root
candidates and complete chance averages finish. If a deeper horizon times out,
the last completed horizon remains selected. A legal immediate utility choice
is available even when no complete horizon fits. Think limits exclude small
snapshot parsing and root move-generation overhead.

## Validation

Tests cover card conservation across multiple decks, unknown hands and partial
reconnect history, public discard recycling, hold-on finishing sequences, wild
shape choices, stacking switches, node limits and interruption. Ludo tests
check an analytically known 11/36 winning-roll probability, both known dice,
capture/finish behavior, bonus rolls, eliminated seats and agreement between
the actual server roll and the search chance transition. Extra hidden-hand,
market, seed and future-dice fields cannot influence search observations.

Adapter play-throughs cover Pro and Legend, classic WHOT with and without
wilds/specials, Ludo with two/three/four seats and eight-piece games. These
checks establish rule correctness and execution limits; playing strength and
production concurrency still need match testing. No Elo rating is claimed.

Full offline backend `verify -DskipITs` passed after this change: **760 tests
across 100 suites, zero failures, errors or skipped unit tests**. That run also
enabled the real Stockfish executable and rebuilt the backend jar. Docker
integration tests were skipped. `git diff --check` passed. The later current-main
integration and deployment checks are recorded in
[Scan verification](SCAN_INTEGRATION.md#verification).

The Tell integration includes main through `ab315c5`. Full backend
`verify -DskipITs` completes with **883 tests, zero failures or errors and seven
skipped tests** (six require local native-engine executables; one requires live
object-storage credentials). All **116 selected Flutter tests** pass, including
Whot, Huud rosters, difficulty selection and the latest main UI changes. Tests
cover bot-filled 4/6/8-seat games through a fresh final, human/bot signal
agreement, off-turn signaling and buzzing, host rules, stale/decoy signals,
private-information boundaries and starting a human-hosted room with bots.

The test VPS image passes real Stockfish and Scan container smoke checks and
startup validation against the existing test database. The test backend was
updated successfully with both native workers ready; production container
identities and start times were unchanged. Build and deployment metadata is
recorded in `output/phone-deploy/2026102505/manifest.json`.

Signed iOS build `2026102505` was installed on the connected iPhone. Automatic
launch was blocked because the phone was locked. GitHub main was verified at
`299e68e`, which includes this integration.
