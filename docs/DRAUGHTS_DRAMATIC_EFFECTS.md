# Draughts dramatic effects

Implemented on `codex/local-bot-gameplay`, after pulling main through `806a9ea`.
Finish celebrations are **random per game**, chosen by the server from Royal,
Thunder, Fire, Neon and Confetti. There is no selection prompt or finisher button.

## Moments

- **Capture chains:** confirmed jumps leave a bounded trail, stronger impact rings
  and rising capture sounds. Two captures show DOUBLE TAKE, three TRIPLE TAKE,
  and longer chains BOARD SWEEP with their actual count.
- **Crowning:** a gold ring and settling crown mark KING ME at the promoted square.
- **King down:** the captured crown splits apart, followed by the existing trophy
  flight. This can also carry the chain count.
- **Seizure:** SEIZED and a square spotlight accompany the confirmed seizure;
  available seizures retain their existing selection ring and rule guidance.
- **Decisive position:** the last capture or move blocking the opponent receives
  FINAL TAKE or NO WAY OUT before the results appear. This is a presentation
  hold after the server has already ended play, with no effect on clocks or wins.
- **Finish:** the server's random celebration plays above the result. Draws have
  no victory celebration. Everyone receives the same style, including spectators.
- **Spectators:** six emoji reactions rise in two clipped 24-pixel lanes outside
  the board. Server and client rate limits apply. At most eight are visible;
  one cleanup timer removes them. Muting clears the audience effects. Tournament
  spectators remain read-only.

## Safeguards

Effects use authoritative event sequences and public victim-type/finish metadata.
Snapshots establish a sequence floor; duplicates, reconnect history and VAR do
not replay celebrations. Undo clears pending effects. Queue sizes and durations
are bounded so capture bursts cannot create a long animation backlog. Effects
never intercept input or change card/piece legality, capture choice, clocks,
bot search, undo consent, or results.

A fresh HELLO still sends Draughts spectators the authoritative board. During
play they reduce the same complete public move events as players; a post-move
snapshot is no longer sent ahead of those events. Whot and Traitors retain their
existing spectator snapshot behavior.

Reduced motion uses static, fading callouts, skips travelling particles and
captured-piece flights, and removes the result trophy bounce. Results loaded
from a snapshot remain quiet.

## Start-game checks

Main's authoritative table minimums and Huud pre-start validation are retained.
Standalone Chess, Draughts, Whot, Macala and Word Bluff also explain who to add;
SlayHuud's runway blocks Start until its contestant/judge requirements are met.
Whot lobby snapshots include the mode so The Tell's team sizes are checked even
before the Huud metadata arrives.

## Verification

- Full backend `verify -DskipITs`: **903 tests across 134 suites**, no failures or
  errors; seven checks skipped (six need local native engine executables, one
  needs live storage credentials). Docker integration tests were excluded.
- **121 Flutter regression tests passed** across Draughts, Whot effects, VAR,
  lobby minimums, Huud entry and SlayHuud controls/navigation. The final effects
  suite also checks authoritative mid-chain counts and separation of queued
  effects from different turns. All 13 final effect tests and six final start
  checks passed.
- Static analysis of the effects, game screen and shared reaction components
  reports no issues. Full-motion 390×844 previews were rendered and inspected.
- Evidence: `output/draughts-effects-validation/verification.json` and the
  adjacent `king-down.png` / `king-me.png` previews.
- Deployed source `7ea7818` to the isolated test backend and iPhone build
  **2026102511** on 25 October 2026. Confirmed the installed version and
  successful launch. Both native engines passed container smoke checks and
  reported ready after rollout. Production container identities and start
  times were unchanged. Deployment hashes and evidence are recorded in
  `output/phone-deploy/2026102511/manifest.json`.
