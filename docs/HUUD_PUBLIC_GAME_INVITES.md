# Public game invitations

Hosts can use **Find players** in a waiting game's roster (including its lobby).
For a private or friends Huud, the app explains that this publishes a preview
in Live Now and the For you feed while keeping Huud privacy unchanged.
**Stop invitation** withdraws that game's public invitation.

Discovery and feed cards expose `findingPlayers` and say **Join to play**;
feed game descriptions also say **Play with host**. A public request creates a
pending play request, not membership or an assigned seat. The host's approval
admits the player to the Huud and seats them in the game. Private join codes
remain hidden from viewers. Blocked and removed users cannot request a seat.

The invitation is bound to one room and host. Server reads and request endpoints
check that the Huud is live, the game is waiting, and a seat remains. Cancellation,
a different game/host, a full table, or game start disables public recruitment.
A free seat becoming available again in the same waiting game can make its
uncancelled invitation available again. Normal Huud feed shares are independent.

Database migration: `V57__huud_public_game_invites.sql`.
Endpoints under `/api/v1/huud-spaces/{id}`:

- `POST /public-invite`: publish the current game invitation (host only).
- `DELETE /public-invite`: withdraw it (host only).
- `POST /public-invite/play`: request host approval for a seat.

Validation uses Flutter host/live/feed tests and isolated PostgreSQL/Redis
integration tests for private visibility, admission, capacity, cancellation,
game changes, game start, and blocking. Deployment and phone installation are
separate from these local changes.

## Test delivery — 16 October 2026

Backend deployed to the existing `/test` environment. Public health is UP and
Flyway V57 is applied successfully. The previous test image, jar and database
snapshot are retained under the test deployment for rollback. Production health
was checked independently and its backend was not restarted.

Signed iPhone build 1.0.1 (2026101602), configured for the test API, was installed
and launched on iKingbarric. Installed version was read back from the device.
This build also carries the grid switch, compact online-first roster, bot-refresh
fix and Add Cyber Agent positioning. Local validation: 81 affected Flutter tests,
42 Huud database integration tests; final feed adjustments were rechecked with
18 feed tests and the two invitation integration tests. End-to-end interaction
between two physical phones remains a separate manual check.
