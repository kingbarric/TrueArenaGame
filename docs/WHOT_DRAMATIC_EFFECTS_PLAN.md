# Whot dramatic effects and selectable final-card celebrations

Status: implemented and verified on `codex/local-bot-gameplay`, including main
through `362503f`. Deployed to the isolated test backend and iPhone build
`2026102508`; these changes have not been pushed.

## Goal

Make Whot's attacks, counters, narrow escapes and wins feel like table-wide
events. Pick Two stacking is the signature spectacle. Ordinary plays stay
quick; stronger effects mark escalating debt and decisive moments.

Both Classic and The Tell participate. Human players, Cyber Agents and
spectators see the same confirmed action and outcome, subject to their own
sound and reduced-motion preferences.

## Effects catalogue

| Moment | Visual treatment | Sound / suggested callout |
| --- | --- | --- |
| First Pick Two | The card slams down. A red streak travels from the attacker toward the actual next target. A floating **+2** debt badge appears at that seat. | Short impact and attack sting. **PICK TWO!** |
| Counter Pick Two | The answering card intercepts the attack with a clash. The debt badge updates to the confirmed total, such as **+4**. In a two-player game the streak ricochets back; at larger tables it travels onward to the next eligible player. | Metallic clash. **STACKED!** or **RETURNED!** when it actually returns to the attacker. |
| Growing Pick Two chain | At **+6, +8, +10** and beyond, the badge grows within a fixed size limit, cards glow hotter, and impacts deepen. Escalation uses a few bounded intensity tiers. | Rising tension. An occasional **WHO'S TAKING IT?** cue, rather than a new announcement for every card. |
| Debt collected | The outstanding debt resolves into cards flying from the market to the drawing player's seat. The last stacker gets a brief spotlight. | One payoff sting. **TO MARKET!** No loud repeated hit for every drawn card. |
| General Market · 14 | A shockwave circles the table. Each affected player receives a card animation at their seat. | Broad wave / market sting. **EVERYBODY TO MARKET!** |
| Hold On · 1 | The turn spotlight hints at moving, then snaps back to the same player. | Short rewind / snap. **STILL MY TURN.** |
| Suspension · 8 | The turn spotlight vaults over the actual skipped player. A crossed-out turn icon briefly stamps that avatar. | Quick skip / swoosh cue. |
| Whot wild card | The chosen shape blooms over the table and changes its accent colour. The shape and label remain readable without colour. | Brief transformation sting after the shape choice is confirmed. |
| One card remaining | The player's seat receives a pulsing gold outline and a short heartbeat sting. The player is offered the final-card effect chooser described below. | **LAST CARD!** with a bounded pulse, rather than a continuous alarm. |
| Winning card | A brief anticipation beat leads into the final slam, the player's selected finisher, a winner spotlight and celebration. | A short victory payoff matched to the selected finisher. |

Pick Two effects apply only when the corresponding house rules permit the
attack or stack. Other special-card effects likewise require the special to
be enabled and actually applied by the game. A printed number alone is not
enough to trigger one.

The streak, debt total, draw count, skipped seat and market recipients must
match the accepted game outcome. Animation must never imply a reversal of
turn order, capture or penalty that the rules did not produce.

## Choose a final card effect

When a human player's confirmed hand first reaches one card in a round,
offer a compact popup titled **Choose a final card effect**. This is a
cosmetic celebration choice for a successful final-card play.

The shared gold last-card warning remains consistent for everyone. Choosing a
finisher changes the celebration when the card wins or qualifies the team;
it does not hide the player's publicly visible last-card warning.

### Starter choices

These are proposed names and treatments for the initial catalogue:

| Choice | Final-card treatment |
| --- | --- |
| **Thunder Slam** | A lightning frame, one strong impact and a brief table jolt. |
| **Fire Burst** | The card leaves a fiery trail, then releases a short flame ring. |
| **Neon Shockwave** | Expanding rings carry the card's chosen accent across the table. |
| **Royal Spotlight** | A gold beam highlights the winner, with a crown flourish above their seat. |
| **Confetti Storm** | A colourful burst of bounded paper particles and a celebratory sound. |

Use the normal final slam as the default when no effect is selected. All
starter choices should be available in the initial version; an economy or
unlock system is outside this plan.

### Popup behaviour

1. Offer the chooser once when that player's confirmed hand reaches one card
   during the round. Show readable names, small previews and a clear selected
   state. Preselect the last saved preference, or the normal final slam.
2. A tap selects the effect and closes the popup. Also provide **Use default**
   and an obvious dismiss control. Dismissal must be safe and immediate.
3. Keep the popup compact and non-blocking. The player must still be able to
   play their card, draw, pause, or respond to The Tell's live signal. Avoid
   covering the hand, market controls, signal tray or buzz target. Collapse
   the chooser to the **Final effect** control if those controls need the space.
4. The turn clock continues normally. Selection never pauses the match,
   creates another ready step, or becomes a prerequisite for playing.
5. If the player plays before choosing, use the existing/default preference.
   Do not hold an accepted final-card action while waiting for a choice.
6. Save the preference for future rounds and allow reopening through the
   **Final effect** control. A local thumbnail preview stays private; the actual
   confirmed finisher is visible to the table and spectators.
7. If a draw takes the player above one card, close the automatic popup and
   stop the one-card pulse. Keep their cosmetic preference. Returning to one
   card in the same round must not repeatedly reopen the popup.
8. Reconnection restores the preference and current hand state without
   repeatedly prompting or replaying an old celebration. A fresh final in
   The Tell counts as a new round for the once-per-round offer.

Cyber Agents use a valid default or assigned preset automatically. They do
not open a chooser or wait on an LLM to pick an effect.

### When the selected effect plays

- In Classic, play it after a confirmed final-card win.
- In The Tell qualification, use a shorter version with **TEAM QUALIFIED**.
  Keep the remaining teams' play visible and usable.
- In The Tell's final, use the full version when the final card wins for the
  team. Highlight both winning teammates while identifying who played it.
- A rejected or duplicate card action must never trigger a finisher.
- A last-card play that does not produce a win or qualification must not
  display a victory celebration.
- A Tell signal/buzz victory uses the Tell outcome effect below. It must not
  pretend that a final card was played.

## The Tell: signal suspense and interception

- Show a public signal as a floating symbol labelled with its sender and a
  shrinking ring for its existing three-second lifetime.
- Show genuine signals and decoys identically before resolution. Animation,
  colour and sound must not reveal secret symbols or hand validity.
- The ring reflects the server-issued send time. Animation never extends the
  buzz window or changes which buzz the server accepts first.
- Use a sharp buzzer for the confirmed resolution. A successful opponent
  interception earns **STOLEN!**, with the spotlight switching to that team.
- Distinguish **TEAM QUALIFIED**, **TEAM ELIMINATED** and **TEAM WINS**. Use
  compact effects during qualification and the full celebration for a final
  victory.
- An expired, replaced or already resolved signal disappears cleanly; a late
  tap must not replay an outcome or generate a false elimination celebration.
- Signal and buzz controls stay usable during all other cosmetic effects.

## Pacing, accessibility and performance

Proposed timing budgets, to tune during implementation:

| Effect | Target duration |
| --- | --- |
| Ordinary play | Existing quick card movement; no extra cinematic pause. |
| Attack / counter impact | Roughly 250–450 ms, with the debt badge left readable. |
| General Market wave | Roughly 400–700 ms; group recipients rather than serialising the table. |
| Last-card warning | One short sting and a bounded pulse, followed by a static marker. |
| Final-card anticipation | Roughly 150–250 ms, purely visual after server confirmation. |
| Winning celebration | Roughly 1–2 seconds, followed by the results view. |

These are presentation budgets, not extra game-clock time. Never delay the
network action or change turn/buzz deadlines to accommodate an animation.

- Respect independent sound and music settings. A muted client stays muted.
- Offer reduced effects and respect the device's reduced-motion preference.
  Replace camera shake, fast trails and large bursts with static outlines,
  readable badges and gentle fades. Avoid rapid flashing.
- Keep every state understandable without sound, colour, haptics or motion.
  Optional haptics should be brief and respect the player's preference.
- Cap concurrent particles, screen shake, audio layers and debt badge size.
  A large draw animates a small representative group plus the correct count;
  it does not allocate an unbounded number of moving cards.
- At a busy table, prioritise the active signal/buzz target, current action
  and debt amount. Coalesce cosmetic flourishes rather than blocking input
  behind an animation queue.
- Dispose of animations, audio and timers when leaving the game. Backgrounding,
  pause/resume and rematches must not produce delayed sounds or stale effects.

## Implementation constraints: preserve game correctness

The first implementation should add a presentation layer around the existing
Whot state and events. The rule reducer remains authoritative for cards,
penalties, next player, winners and team outcomes.

- Trigger effects only from accepted actions/events and confirmed state.
  Do not animate a successful attack or win from a local button tap alone.
- Use stable event/action identifiers to avoid duplicate effects from
  acknowledgements, repeated snapshots, reconnect replay or retransmission.
- Use snapshots to restore the current hand, debt and turn. Do not infer
  private cards from public events or replay historical fireworks on reconnect.
- Calculate each effect from the authoritative before/after state and event
  payloads. Do not introduce a second implementation of special-card rules.
- Allowlist cosmetic preset IDs when sharing preferences with the room.
  Missing, invalid or older-client preferences fall back to the normal slam.
  Resolve the preset once for a confirmed finish so later preference updates
  cannot alter an already playing celebration.
- If sharing a preference needs a small protocol addition, keep it separate
  from the legal card action. Failure to save a preference must not reject,
  duplicate or delay that card action.
- No gameplay LLM calls are needed. Cosmetic selection and playback do not
  affect bot difficulty, randomness, market order, rewards or rankings.

Current integration points to inspect when implementing:

| Confirmed information | Presentation use |
| --- | --- |
| `CARD_PLAYED`, current rules, pending debt and next-player state | Attack, stacking, hold-on, suspension and wild-shape effects. |
| `CARD_DRAWN`, private `YOUR_DRAW`, confirmed hand sizes | Debt payoff and market-to-hand movement without exposing another hand. |
| `GENERAL_MARKET` | Table-wide market wave for the actual affected seats. |
| Confirmed hand size of one | Last-card marker and the player's once-per-round chooser. |
| `SIGNAL_DISPLAYED`, `BUZZ_RESOLVED` | Signal ring, buzzer and interception outcome. |
| `TEAM_QUALIFIED`, `TEAM_ELIMINATED`, `FINAL_STARTED`, `GAME_OVER` | Correct team-stage treatment, round reset and winning finisher. |

## Delivery order

All catalogue items are in scope. Build and verify them incrementally:

1. Effect settings, event deduplication and reduced-motion baseline; Pick Two
   attacks, counters, escalating debt and debt collection.
2. Last-card warning, non-blocking finisher popup, saved preference and final
   slam; General Market shockwave.
3. Hold On, Suspension and wild-shape flourishes.
4. The Tell signal ring, buzzer, interception and stage-specific celebrations.
5. Tune pacing, sound balance, small-screen layouts and busy-table performance.

## Acceptance and regression checks

- In two-player Whot, a Pick Two counter visibly returns to the attacker; in
  larger tables, it follows the real next eligible player and direction.
- Escalation displays the exact confirmed debt. Drawing clears the attack and
  updates the correct hand size, including large chains and market reshuffles.
- Disabled specials and disabled stacking never receive a false special effect.
- Hold On and Suspension show the actual turn outcome, including eliminated
  or qualified teams in The Tell.
- A wild transformation shows the confirmed selected shape.
- The final-card popup offers each named choice, safely defaults when ignored,
  saves selection and never blocks play, drawing, pause or a Tell buzz.
- Drawing above one card, returning to one card, reconnecting and starting a
  fresh final produce the specified popup and last-card marker behaviour.
- Selected finishers appear once to players and spectators for a confirmed
  card win/qualification. Rejected actions, duplicate events and old snapshots
  never create extra wins, sounds or celebrations.
- Simultaneous Tell buzzes still resolve exactly once in server order. No
  visual cue distinguishes a genuine Tell from a decoy before resolution.
- Effects remain readable on a small phone, under larger text settings, in
  reduced-motion mode and with sound disabled.
- Existing card legality, private-hand visibility, turn timers, pause/resume,
  reconnect, bot play and results behaviour pass regression checks unchanged.

Related specifications: [The Tell](WHOT_THE_TELL.md),
[WHOT bot search](WHOT_LUDO_BOT_SEARCH.md).

## VAR, take-backs and spectator reactions

- **VAR** opens a read-only replay of the latest 24 public card turns, with
  previous/next controls, a scrubber and replay from the start. It shows played
  cards, draw counts and public hand sizes. It never shows another hand or the
  market order, and never pauses the live clock. Reconnect restores the public
  history from the authoritative snapshot; old effects are not replayed.
- **Undo** means take back the last card turn, matching Draughts' request and
  acceptance flow. Only the most recent mover can ask, before play continues.
  Every other active player must accept; any decline cancels it. Cyber Agents
  accept once and wait for remaining human votes. A move, draw, Tell signal,
  buzz, timeout or stage/result transition expires the request/checkpoint.
- Acceptance restores exact hands, market order, discard pile, shape demand,
  penalty and turn ownership. It preserves cosmetic preferences, monotonic
  event IDs and processed action IDs. The restored turn gets a fresh clock
  through the existing turn scheduler. An undone turn is marked in VAR.
  Completed wins and qualification cannot be rewound. A live Tell signal must
  resolve or expire before an undo can be requested.
- **Spectator reactions** use an ephemeral `REACTION_SEND` room message, with
  `👏 🔥 😂 😮 💔 🎉` as the available choices. The server validates spectator
  identity, honours spectator muting and championship read-only rules, and
  limits each spectator to one reaction per second.
- Received reactions float only in two clipped 24-pixel lanes outside the
  wooden table. They never cross the board, hand, market, discard, signal or
  controls and do not intercept touches. At most eight are visible; one cleanup
  timer removes expired reactions. Reconnect does not replay them. Reduced
  motion uses a static fade in the lanes.
- The final-card chooser occupies the review-control strip while open. Closing
  it returns VAR/Undo controls. It leaves card and market input available and
  uses a separate acknowledgement, so saving a cosmetic choice cannot release
  an unrelated pending card action.

## Verification results

- Full backend `verify -DskipITs`: **892 tests across 130 suites, zero failures
  or errors, seven skipped checks**. Six skipped checks require local native
  Scan/Stockfish executables; one requires live object-storage credentials.
  Docker integration tests were excluded.
- **155 selected Flutter tests passed**, covering existing Whot play, all six
  finishers, chooser input and cosmetic acknowledgements, VAR, take-back
  consent, spectator side-lane geometry/expiry, reduced-motion dealing, Tell
  interception results, reconnect suppression, shared Draughts VAR controls
  and the latest Huud flows.
- Static analysis of the three Whot UI files reports **no issues**.
- A 390×844 phone layout was rendered and inspected. Animations preserve
  authoritative card legality while the visible card fan catches up; the
  finisher chooser replaces the review strip while open to preserve play space.
- Validation metadata and the rendered preview are in
  `output/whot-effects-validation/`. Your earlier local multiple-Huud plan was
  preserved in `output/merge-backups/20261025-whot-effects/` when main's updated
  tracked version was merged.

## Test deployment — 25 October 2026

- Fetched main and confirmed `362503f` is included in the deployed source
  revision `9accc8b` on `codex/local-bot-gameplay`.
- Installed and launched signed iPhone build **2026102508**, targeting the test
  API. Confirmed the installed version and that its process remained running.
- Matching test backend passed container health checks. Stockfish and Scan
  each have one ready native worker and no startup failure. Production
  container identities and start times were unchanged.
- Build hashes, engine status, installation and launch evidence are recorded
  in `output/phone-deploy/2026102508/manifest.json` and adjacent evidence files.
