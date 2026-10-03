# Whot: The Tell

Status: implemented mode with server-owned teams, signals, buzzes, qualification, and a final.

## Purpose

The Tell is a team mode built on PlayHuud's existing Whot game. Players still
shuffle, deal, take turns, play matching cards, use the configured special-card
rules, and draw from the market. At the same time, teammates try to recognise
their private signal while opponents watch for it and send decoys of their own.

The Whot entry offers two choices:

| Mode | Experience |
| --- | --- |
| **Classic** | The existing individual Whot game and its current house rules. |
| **The Tell** | Team Whot with private signals, public decoys, buzzes, qualification, and a final. |

Both choices use the same Whot deck and turn engine. The Tell adds a mode and
tournament rules layer; it must not contain a second Whot implementation.

## Teams and private setup

| Players | Teams | Mode structure |
| --- | --- | --- |
| 4 | 2 pairs | One final round |
| 6 | 3 pairs | Qualification, then a two-team final |
| 8 | 4 pairs | Qualification, then a two-team final |

- Each team has exactly two players. Team membership is visible; each team's
  chosen signal is visible only to its two members.
- Before each round, both teammates privately choose or confirm one symbol from
  a shared set of 30 space and mystery symbols. The server stores the
  agreed symbol and sends it only in those players' private state.
- A new final is a new round: the eligible teams choose a signal again and the
  Whot cards are freshly shuffled and dealt. It is not a continuation of the
  qualification hands or market.

## Play and public signals

- Whot's existing actions and house rules continue to govern cards and turns.
  Playing the last card is a normal Whot win for the player's whole team.
- Every active player can display any symbol from the shared set at any time,
  including on another player's turn. The public event identifies its sender
  and symbol, for example `ERIC → 🪨`. It appears briefly to all players.
- A symbol other than the team's secret can be used as a decoy. The UI must
  never mark a public symbol as genuine before buzz resolution.
- A valid Tell requires **every card remaining in the sender's hand** to share
  one value or one shape. The host can choose Same Value, Same Shape, or Either
  (default), and a minimum of 2–12 cards (default 3). The server checks the
  hand when the signal is sent. Public signals, including decoys, display for
  about three seconds and can be tapped to buzz or intercept.

## Buzz and interception

- A teammate can buzz a specific, recent signal sent by their partner. A
  successful buzz requires that the symbol matches their shared secret and
  that the sender's hand satisfied the SET condition when the signal was sent.
- An opponent can intercept that signal by buzzing it before the sender's
  teammate. A correct interception qualifies the interceptor's **team** in
  qualification or wins the final. An incorrect interception permanently
  eliminates that team from this tournament session.
- If a teammate buzzes their partner without a valid SET and genuine signal,
  their own team is permanently eliminated from this tournament session.
- Buzzes must reference a server-issued signal/event ID. The server records the
  hand validity when the signal is sent, orders buzz actions by the order in
  which it accepts them, and resolves the first eligible buzz atomically.
  Client clocks and animation timing do not decide who buzzed first. Once a
  signal is resolved, a later buzz against it has no effect.
- Signal choice, displayed signals, validation results, buzz order, and team
  outcomes belong in authoritative server state/events. Only the teammates
  receive their secret signal; public events must not reveal it.

## Qualification and final

1. In a preliminary round, the first team to empty a hand, complete a valid
   teammate buzz, or make a correct interception qualifies and leaves active
   play. Its players wait with their cards removed from the active round.
2. The remaining active teams continue under the same Whot rules and current
   market/discard state. Eliminated teams never return during this session.
3. Once two teams have qualified, the other teams leave the tournament. The
   two qualifiers enter a fresh final with freshly shuffled/dealt cards.
4. With four players, the initial round is already that final. The first team
   to win by normal Whot, valid teammate buzz, or correct interception wins
   the tournament.

For six players, this means A can qualify and wait, B and C continue, and C
can qualify next; A and C then play the final. For eight players, the first two
qualifying teams form the final, subject to the open rule choices below.

## Whot stack invariant

The Tell uses the same server-owned market as ordinary Whot. The server
shuffles before dealing; afterward, each draw takes the next card from that
fixed order. Drawing never picks a random card from the remaining market.
Before play begins, the server rejects any deal that already gives a player a
valid Tell. It reshuffles and redeals the complete deck, up to 1,000 tries,
then freezes the accepted market order. When the last market card is taken, eligible discard cards are shuffled into a
new fixed market, while the current top discard stays in play. The client
animates that recycle and displays the real market/discard counts.

## Integration notes

- The Whot lobby needs a **Classic / The Tell** mode choice. Classic preserves
  the existing 2–20 player flow; The Tell accepts only 4, 6, or 8 players and
  opens its team/signal setup before cards are dealt.
- Reuse the current Whot deck, `WhotConfig` house rules, card legality,
  special-card effects, draw/market behaviour, and private-hand snapshots.
  Add The Tell's mode config and team/tournament state around these rules.
- The current Whot module ends the game when a hand becomes empty. The mode
  layer needs to convert that outcome into team qualification or a final win,
  rather than immediately ending every multi-team tournament.
- Deal/start, signal selection, active play, qualified-team waiting, final
  creation, and results need explicit server transitions. A reconnecting
  player must recover their team, current stage, eligible actions, public
  signals, and their own secret without learning another team's secret.
- Room action handling must serialize simultaneous buzzes against the same
  server state and accept exactly one outcome. Keep one authoritative event
  sequence for action ordering and replay.
- The UI needs a shared symbol tray, sender-labelled signal display, buzz and
  intercept controls tied to a signal ID, clear qualification/elimination
  feedback, and a waiting view for qualified teams.

## Acceptance criteria

- Only rooms with 4, 6, or 8 players can start The Tell; everyone belongs to
  exactly one pair. Ordinary Whot still supports its existing player range.
- A player sees only their own team's secret, including after reconnect.
- Decoys are public but never expose secret or SET validity by themselves.
- A valid teammate buzz qualifies/wins the team; a correct earlier opponent
  buzz qualifies/wins the interceptor's team instead.
- Incorrect teammate or opponent buzz permanently eliminates that team.
- Two nearly simultaneous buzzes resolve once, in server acceptance order.
- A normal last-card Whot win qualifies/wins the entire team.
- Qualified teams wait; two qualifiers reach a newly dealt final; the final
  produces one winning team.
- Market draws remain sequential between shuffles; recycled discards become a
  new fixed stack and produce a visible reshuffle event.

## Fixed timing and agreement rules

- A teammate who chooses a different secret resets both confirmations; both
  players must confirm the same symbol. The final asks for a fresh signal.
- The newest signal replaces the earlier one. Buzzes received after three
  seconds or after another buzz resolves are rejected with no elimination.
- A buzz on a live decoy or a genuine signal without a valid Tell eliminates
  the caller's team. Server action order resolves a play and buzz racing each
  other.
- Cyber Agents cannot start The Tell because its private signal agreement
  requires a human teammate.
