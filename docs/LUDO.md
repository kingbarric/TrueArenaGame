# PlayHuud Ludo

PlayHuud Ludo is a 2-4 seat game. Any seat can be a person or a Cyber Agent.
Two players use opposite corners; three use three corners; four use all four.
When a two-player host starts the match, they choose four or eight pieces per player (eight is preselected). The two players occupy opposite diagonal corners. Three- and four-player games start with four pieces per player without this prompt. The first to bring all of their pieces to the center wins.

## Two-dice turn

- Tap the cup to roll two server-generated dice. The client never chooses the values. A roll with no legal move still displays both dice briefly before the turn passes.
- Both dice stay visible to everyone while the rolling player uses them; spent dice and an opponent's tray are dimmed. The tray border follows the rolling player's board color.
- The player chooses which die to use first. Each die moves exactly one chosen piece.
- Both dice may move the same piece, or they may move different pieces.
- A six may bring one piece out of the yard onto its colored start square instead of moving a piece already on the track. The other die may then move the released piece.
- A die with no legal move is discarded. When neither die can move, play advances.
- Only a pair of double sixes earns another roll after both dice are used. Consecutive double sixes can repeat again.
- Capturing a rival or bringing a piece into the center does not earn another roll.

## Board

- Pieces travel around the shared 52-square ring, then into their own five-square colored lane and the center.
- A piece needs the exact die value to reach the center; it cannot overshoot.
- Landing on a single rival on an ordinary square sends that rival back to its yard.
- The four start squares and four marked stars are safe. Pieces of different colors can share those squares.
- Two pieces of one color on an ordinary square form a block. Rivals may pass over it but cannot land there.

## Match and controls

- The server validates every move and owns the timer. A turn timeout discards unused dice and advances to the next active player.
- A player may forfeit even off-turn. In a 3- or 4-player match, the remaining players continue.
- The cup has its own roll sound; pieces use the shared movement sound. Sound effects can be muted in the game bar.
- Players and spectators share the comments panel. Spectators cannot roll or move pieces.
- The game screen uses the shared room code, settings menu, blurred pause state, and comments patterns from Draft and Whot.

## Verification

`LudoModuleTest` covers seat counts, configurable eight-piece play, release, same-piece and different-piece moves, die order, safe and blocked squares, captures, exact finishing, bonus rolls, timeouts, forfeits, deterministic rolls, and action idempotency. `LudoBotAdapterTest` checks the agent's server-provided legal moves and fallback. `app/test/ludo_game_test.dart` checks the socket handoff, cup action, no-move feedback, both move styles, eight-piece layout, and 2-, 3-, and 4-player compact layouts.
