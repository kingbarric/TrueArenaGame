# Whot Game Summary

## Overview

Whot now replaces Goosi in the main game selection and opens its own setup, lobby, and gameplay screens. Players can create or join a room, add Cyber Agents, play a complete match, comment during play, and watch as spectators without seeing private hands.

## Setup and Lobby

- The setup form fits on one phone screen without scrolling.
- Hosts can choose the starting hand, turn time, Whot wild cards, Pick Two, Pick Two stacking, Market, Hold On, and Skip rules.
- A new game deals automatically and starts turns within five seconds.
- Saved Cyber Agents can be added from the lobby and use their own bot identity.
- Player avatars use the actual profile or agent avatar.
- The full six-character room code is visible. Tapping it copies the code and briefly shows `COPIED`.

## Gameplay Interface

- The board uses a compact green felt table with a wooden edge.
- Opponents appear as small player icons. Their exact card counts remain private and are represented by a fixed card stack.
- The active player glows green; inactive players use amber.
- The market sits beside a layered discard pile with visible card edges.
- The local player's cards form a compact overlapping hand. Selecting a covered card brings it forward with a smooth transition.
- Cards are played by dragging them onto the discard pile.
- The local player label sits below the hand.
- The turn instruction appears above the table.
- The board and comment panel fit in one view without scrolling, with a small gap between them.
- Spectators can watch the board and participate in comments when spectator chat is enabled.

## Card Animations

- Drawn cards travel from the market to the player's hand before appearing there.
- A Pick Two penalty animates two staggered cards from the market into the affected player's hand.
- When an opponent draws, cards animate from the market to that opponent's position.
- The activity line announces market actions, for example: `Alex went to market · drew 2 cards`.
- Opponent plays animate from their seat to the discard pile before the new top card is shown.

## Turns and Pausing

- The game does not give cards automatically when a player runs out of time.
- A turn timeout pauses the table, matching the Draughts behavior.
- While paused, the wooden game table is blurred and covered by a clear `GAME PAUSED` marker.
- The room header, status, settings menu, and comment panel remain sharp and usable while paused.
- The gear menu provides pause or resume, music, sound effects, spectator-comment controls, end game, and leave actions.

## Whot Wild Cards

- Hosts can include or exclude Whot wild cards during setup.
- Playing a Whot card opens a high-contrast shape selector so the next shape is easy to choose.
- Pick Two debt cannot be answered with a Whot card. A two can only be stacked when Pick Two stacking is enabled.

## Game Completion and Reliability

- The Whot game supports end-game and forfeit behavior.
- If a player forfeits, the next occupied seat wins.
- Disconnect and reconnect states are handled in the game screen.
- Spectator hands remain private throughout play.

## Main Files

- `app/lib/features/whot/whot_game_screen.dart` — table layout, player seats, hand interaction, animations, pause treatment, controls, and comments.
- `app/lib/features/whot/whot_lobby_screen.dart` — compact setup and room creation flow.
- `app/lib/features/whot/whot_card.dart` — Whot card rendering and play validation.
- `app/test/whot_game_test.dart` — widget and rules coverage for gameplay behavior.
- `backend/ta-game-whot/` — Whot game rules and server-side state.

## Validation Status

- 13 Whot Flutter tests pass.
- Flutter static analysis reports no issues.
- 31 Whot backend tests passed during the completed backend validation.
- The current build was launched and visually checked in the iPhone simulator.
