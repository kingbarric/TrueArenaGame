# PlayHuud Championships — Draughts launch specification

> Status: launch implementation added to the backend, Flutter app, and invitation website. Apply migration V27 and deploy the matching services and app builds together.

## Implemented decisions

- The championship creator is the admin who can end a pairing when both reconnect allowances have expired.
- Invitations let a human PlayHuud user join immediately while slots remain; Cyber Agents are rejected. Guests may enter, while creation requires an account.
- Editing or cancelling a championship after creation is not offered in the launch flow.
- The app links to a limited public invitation preview and a code-based join screen. Tournament matches reuse the Draughts room engine; the bracket, results, actions, and champion badge are stored in PostgreSQL.

## Purpose

Championships let PlayHuud users organize competitive Draughts tournaments and invite others. A championship is also a way to bring a community into PlayHuud: the organizer can share an invitation with friends, WhatsApp groups, and other communities, and entrants can join to compete.

Draughts is the first game to use Championships. The tournament service should be reusable by other PlayHuud games later.

## Launch scope

The launch release delivers this complete path:

```text
Create championship → invite human players → fill the roster → generate a knockout bracket
→ play each round's Draughts matches simultaneously → advance winners automatically → finish the final
→ name the champion → retain the history and champion badge
```

### Create and invite

The Draughts area has a **Create Championship** action. The creator chooses:

| Setting | Launch behavior |
| --- | --- |
| Name | A name for the championship, such as “Eric’s Saturday Draughts Cup”. |
| Size | Exactly 4, 8, 16, or 32 players. |
| Visibility | Public championships are discoverable and watchable by any PlayHuud user. Private championships are absent from public discovery and visible only to their participants. |
| Start | A scheduled date and time, displayed in each viewer’s local time zone. Once all slots are filled, the creator may start earlier. |
| Match rule | One Draughts game decides a pairing. If it draws, the same two players replay until one wins. There is no series score or match-format choice. |
| Invitation | A join code and shareable link that can be sent outside PlayHuud through the phone’s share sheet. |

An invitation shows the championship name, game, knockout format, scheduled start, capacity, number joined, and a **Join Championship** action. Opening an invite should lead an existing user to the championship and give a new user a route into PlayHuud before joining. A private invitation may show this limited join preview to someone holding its code/link; it does not expose the private bracket or live matches until that person joins. Cyber Agents cannot enter championships.

### Pre-start lobby

The lobby shows the name, joined/required count, countdown to start, participant list, and an **Invite Friends** action. It updates as players join. For example:

```text
Saturday Draughts Cup
18/32 players joined
Starts in 02:14:32

Eric  ·  Ada  ·  James  ·  Tobi  ·  …

[Invite Friends]
```

The championship starts automatically once **both** conditions are met: its scheduled start time has arrived and every player slot is filled by a human PlayHuud user. Once the roster is full, the creator may press **Start now** to begin earlier. If the start time arrives with empty slots, the lobby stays open and the championship waits for the full roster. The initial bracket has no byes; an admin-ended pairing with no winner can create a bye in a later round.

### Knockout play

The launch tournament format is **single elimination**. Each bracket pairing creates a Draughts match for its two players. **All matches in the same round begin together.** A completed match advances its winner into the next round's pairing, but the next round waits until every match in the current round has a result. A player who finishes early can watch another match in the current round or wait to learn their next opponent.

### Game and draw rule

Each pairing plays one Draughts game. A win decides the pairing and advances that player. A **draw** leaves the pairing undecided: start another game between the same two players and repeat until a game has a winner. The next bracket round still waits for all current-round pairings to finish. There is no First to 2 Wins format or series score.

For eight entrants, Round 1 has four simultaneous games and advances four winners. The semi-finals have two simultaneous games and advance two winners. The final has one game; its winner becomes champion.

### Disconnects, forfeits, and byes

If a player disconnects or does not appear when their game starts, they have **3 minutes** to return. The server preserves the complete game, board, turn, and clock while a player is away. The normal game clock pauses during the reconnect wait so it cannot decide the game before the grace period ends. The opponent sees the remaining reconnect time. Returning within the allowance resumes the **same** game and pairing. Repeated disconnect/reconnect cycles cannot restart or extend the allowance; the server accounts for time already used during that pairing.

- **One player remains absent:** after that player's 3 minutes expire, they forfeit. The opponent wins the pairing and advances.
- **Both players remain absent:** preserve the game and track each player's allowance independently. Once both are absent beyond their allowances, an authorized tournament admin can end that pairing with **no winner**. Neither absent player advances. This is an admin action, not an automatic selection of a winner.
- **Empty next-round slot:** when an admin-ended pairing leaves another player without an opponent in the next knockout round, that player receives a **bye** and advances automatically. Byes arise from prior results, not from an incomplete initial roster.

If the final is ended with no winner because both players are absent, the tournament records that outcome without inventing a champion.

All game state, disconnect clocks, forfeits, admin decisions, results, byes, and bracket advancement are determined and stored **server-side**. The client displays the authoritative state and cannot decide results or advancement. The server verifies an admin's permission before accepting a no-winner decision. Result processing must be safe to receive more than once without advancing a player twice.

For 8 entrants:

```text
Round 1 → Semi-finals → Final → Champion
8 players    4 players   2 players    1
4 games      2 games     1 game
```

At any time, a participant can reopen the championship page and see the participants, current bracket, active matches, completed results, upcoming pairings, eliminated players, and final result when available. The bracket and history must persist independently of a single live game connection.

### Watching matches and visibility

Launch includes a read-only live view of tournament matches so a player who has finished can watch the other matches in their round. Any PlayHuud user may discover and watch a **public** championship and its live matches. A **private** championship, its bracket, and its matches are visible only to joined participants. Viewers cannot make moves or affect results.

### Completion and identity

When the final has a winner, that player becomes the champion. The completed championship remains visible in PlayHuud history, and the winner receives a permanent achievement such as **🏆 Saturday Draughts Cup Champion**. The creator and participants can revisit the final bracket and results. A final ended by the admin with no winner has no champion.

The launch release includes tournament history and the champion badge. A fuller profile record—championships entered and won, runner-up finishes, match wins/losses, win rate, and badge collection—is a later profile enhancement unless needed to present the launch badge.

## Platform boundary

The tournament service owns tournament records, participants, invitations, bracket generation, pairings, disconnect/forfeit policy, admin no-winner decisions, byes, advancement, final standings, history, and awards. A game integration owns its game rules and reports each authoritative game result. Draughts is the first integration. All decisions are made on the server.

```text
Draughts game concludes
    → Draughts reports its authoritative game result
    → If drawn, the same pairing plays again
    → If won, the tournament service advances the winner
    → Next bracket match becomes available
```

Design the service so later game integrations can supply participants and results without copying the bracket engine. Qualification, rankings, and seasons may eventually use completed tournament records, but are outside the launch flow.

## Launch acceptance criteria

1. A user can create a 4, 8, 16, or 32 player Draughts championship with the launch settings and obtain a shareable code/link.
2. Human PlayHuud users can join an eligible championship through the invitation; Cyber Agents cannot join. The lobby shows the current roster and start countdown.
3. The championship starts automatically at the scheduled time once the roster is full, or earlier when the creator presses Start now with a full roster. It creates one correct single elimination bracket with each entrant appearing once in the first round.
4. All pairings in a round become playable together. The next round begins when all current-round matches have results.
5. Each pairing plays a Draughts game. A draw starts another game between the same players; only a win decides who advances.
6. The server preserves a disconnected player's board and game state for a 3-minute reconnect allowance and displays the time remaining. Reconnecting resumes the same game without resetting the allowance. A no-show also receives 3 minutes from the game start.
7. The server applies a one-player forfeit after the allowance expires. If both players remain absent, an authorized tournament admin can end the pairing with no winner. An unopposed player in the next round advances by bye.
8. A decided pairing records exactly one bracket result and advances only the valid winner. The client cannot submit its own authoritative result or advance a bracket slot.
9. Early finishers can watch another live match or wait for their next opponent. Any PlayHuud user can discover and watch public championships; only joined participants can see private brackets and matches.
10. The championship page shows participants, current and completed matches, upcoming pairings, eliminated players, and the bracket as it changes.
11. A final with a winner produces one champion. The completed bracket and result remain available in tournament history; a champion keeps a badge. An admin-ended final with no winner awards no champion.
12. Tournament, game, and match state survive app closure and reconnect, and users reopen the latest server state.

## Future phases — outside launch scope

### Group stage and knockout

Larger championships may later use World Cup style groups followed by a knockout bracket. One possible scoring model is 3 points for a win, 1 for a draw, and 0 for a loss. PlayHuud would determine qualifiers and create the knockout stage. This is **not required for launch**.

### Community and official championships

Community championships are created by ordinary users for friends, universities, offices, estates, and local groups. Official PlayHuud championships are organized by the platform. A possible long-term path is community events → qualification rankings → country or regional events → a PlayHuud World Championship.

Official titles should identify the platform, for example **PlayHuud World Draughts Champion**, rather than implying a title across all Draughts competition.

### Seasonal qualification

One small community win should not automatically qualify someone for a major event. A future season could count a limited number of a player’s best eligible performances, with a Qualification Score based on event size, placement, match wins, win rate, opponent strength, and undefeated runs. Speed may contribute, but should be secondary. For example, a September–November season could count the best five eligible performances and qualify the top 32 players. The cutoff should be visible to competitors.

### Expanded spectator experience

The launch read-only match view can later grow into a major-event experience with large viewer counts, commentary, and moderated spectator chat. Those enhancements are **not launch requirements**.

### Other games

Whot, Chess, Ludo, and other competitive games may later use the same tournament service through their own match integrations. Cross-game tournaments are **not launch requirements**.

## Decisions to settle before implementation

These details are not specified by the brief and should be decided when turning it into implementation tasks:

1. Who has tournament-admin permission to end a both-absent pairing: only its creator, or a designated admin as well?
2. Can a creator edit or cancel a championship after invitations have been shared, and until what point?
3. Does a private invitation let its holder join immediately, or must the creator approve them first? In either case, nonparticipants get only the limited invitation preview.

## Explicit launch exclusions

Do not delay the launch championship path for world or country events, qualification scores, seasons, Elo/Glicko, group stages, commentary, moderated spectator chat, or cross-game tournaments. The basic live match viewing described above **is** part of launch. Keep the tournament service reusable so later features can be added.
