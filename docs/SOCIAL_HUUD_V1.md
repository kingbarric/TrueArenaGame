# Persistent social Huuds — v1 implementation and merge handoff

Branch: `codex/social-huud-v1`, based on `8aade42`.
Worktree: `/private/tmp/TrueArena-social-huud-v1`.

The Huud is the persistent social space; each game is a temporary match. This
implementation follows `PlayHuud_Social_Huud_Platform_Updated.md`, the definitive
lifecycle rules supplied in the conversation, and the subsequent admission
clarification. The original blueprint remains in the main workspace's `docs/`.

## Admission and games

A passive viewer makes **Request to Join Huud**. The admin accepts or rejects it.
Acceptance grants participant, Huud chat, and microphone permission together.
There is no second Request Mic flow. Voice connection and self-unmuting remain
explicit choices; joining never publishes the microphone automatically.

The admin selects a game/mode, which opens game requests. Only participants can
request to play. Only the admin selects the roster and starts the match; the admin
may include or exclude themselves. Game modules supply capacities, including
Whot Tell's permitted team sizes. Each waiting stage has a version, so delayed
requests, roster edits, starts, and rematches cannot mutate a later game.

A user owns at most one active Huud. Ownership and viewing are independent.
Catalogue taps resolve the owned Huud first and only select the tapped game when
that Huud is idle. Navigation never leaves membership, ends ownership, or
interrupts a match. Viewing another Huud is allowed; voice can be switched
explicitly between sessions.

## Persistence and lifecycle

`huud_sessions`, membership, admission, viewers, chat, requests, and audit events
are durable PostgreSQL records. Each started match gets its own existing `rooms`
and `game_sessions` records, linked through `rooms.huud_session_id`. Its
`room_members` contain only the selected roster, including when the owner sits
out. The social Huud code belongs to the Huud and survives every match.

`idle → waiting → playing → results → waiting/idle` is the activity loop.
A game ending leaves Huud membership, chat, voice, audience, and code intact.
Rematch preselects eligible remaining players; selecting another game opens a
fresh request stage. No parallel games, queue, co-hosts, or ownership migration
are introduced.

App presence updates all of a user's memberships and their owned Huud,
independently of the visible screen. Viewer counts represent recent viewing and
exclude participants. Players are a subset of participants, not a fourth kind of
social membership. Leaving a screen stops its viewing heartbeat only.

Explicit Leave Huud removes social membership and voice. Explicit End Huud
invalidates the code, closes voice, cancels the current match, and ends the
session. **Implementation assumption:** ending a running Huud cancels its match
without a competitive result or rating. The optional question about waiting for
the match to finish has not been answered in the conversation.

Reconnect grace defaults to 10 minutes and inactivity timeout to 30 minutes:
`playhuud.huud.reconnect-grace` and `playhuud.huud.inactivity-timeout` accept ISO
Durations. Active members/viewers keep an absent owner's session alive. Completely
empty Huuds expire on the next lifecycle sweep. Expiry and presence share per-Huud
locks, with expiry eligibility rechecked after locking.

## Voice, chat, spectators, and safety

Voice is named `huud-{id}` and belongs to the Huud owner even if another participant
connects first. It reuses the existing LiveKit transport and persistent call UI.
Tokens require approved Huud participation. Navigation/game switching does not
reconnect voice. The admin can mute participants; users can self-mute and locally
mute others. Speaking indicators appear on game avatars and the Huud people list.
Failed moderation removals are persisted and retried every 10 seconds.

Huud chat uses the Huud REST endpoints. Word Bluff's structured interaction stays
on the match socket; its UI switches between Game Chat and Huud Chat. Huud chat
is never delivered to a game AI. Traitors retains its phase-specific/private game
interaction and uses Huud chat for social conversation. A non-playing Traitors
admin can use public moderator controls without receiving a role or secret team.

Game engines' existing public and player projections stay separate. Spectators
are authenticated against Huud privacy/block/ban rules and never get player
projections or private events. Whot's spectator projection contains public table
state and card counts, never hands or deck order. Existing sockets are revoked on
privacy changes, blocks, and removal. Removed game players must reconnect as
spectators and retain Huud membership/voice/chat. Engines use their existing
forfeit behavior; games without such behavior cancel the match without a result.

Public discovery includes block/report, contextual chat reports, admin removal
from a game or Huud, bans that prevent immediate rejoining, request/chat/report
rate limits, and durable moderation events. Private/friends access is checked on
REST, sockets, and voice. Legacy game and standalone voice discovery exclude
social Huuds; Home owns their discovery. Home starts with cards; passive game
viewers can swipe up/down through that discovered list. Membership/ownership
prevents those gestures from moving an active participant accidentally.

## Analytics

`huud_events` records creation, viewer entry, admission, requests, selections,
game starts/completions, and moderation. `huud_game_audience` captures participants
and viewers separately at match completion and samples presence after at least
30 seconds (the minute sweep may run later). `social_huud_metrics.sql` supplies
read-only definitions for multi-game rate, games per Huud, post-game retention,
viewer-to-player conversion, request acceptance, duration, and returning users.
These are operational queries, not a new analytics dashboard.

## SlayHuud merge

The SlayHuud game implementation remains on its separate branch. Its exact
committed V37 migration (from `8213d54`) is included here for schema ordering
on the shared backend; no SlayHuud engine or UI is integrated. Seven existing engines use this
contract now; SlayHuud must be connected after its branch is ready to merge.

- The backend ships SlayHuud **V37** followed by social Huud **V38**, so a later
  SlayHuud merge retains the same migration checksum and order. V38 uses `CREATE TABLE IF NOT EXISTS
  user_blocks`, with the same blocker/blocked key and cascading user references
  as the current SlayHuud V37 schema. Huud reports retain their social context.
- Keep SlayHuud's catalogue/hub/studio/daily/cup additions when resolving
  `GameSelectScreen` and `HomeScreen`. Live Huud game actions should resolve the
  owned Huud rather than creating another social session. Studio/daily activities
  do not have to be live Huud matches.
- `HuudGameCatalog` is the game-capacity/config adapter. SlayHuud currently has a
  separate competition service rather than a `GameModule`; add a narrow adapter
  there and in `HuudGameBridge` for its live modes, using the approved selected
  roster and phase-safe spectator projection.
- Merge shared `RoomService` and `GameOrchestrator` changes deliberately: preserve
  SlayHuud's event/start hooks alongside Huud privacy checks, host independence,
  cancellation, and locked roster rules. Preserve the Slay result/placement
  schema. Do not force studio/content state into the generic game engine.
- App startup and notification recovery resolve linked matches to their social
  Huud; keep the corresponding Slay room routing for unlinked activities.
- After integration, test SlayHuud → another game in one Huud, voice/chat/audience
  persistence, selected contestants, phase-safe looks, and blind voter identity.

## Validation

Automated validation includes the complete Draughts → results → Whot loop with a
non-playing host; one admission granting mic but no seat; private/friends access;
concurrent creation/starts; stale game versions; rematch; public-state secrecy;
privacy revocation; reconnect/inactivity; removal vs forfeit; voice-control
outages; rate limiting/contextual reports; and retention sampling.

The Java tests use a dedicated PostgreSQL/Redis pair, not the other agent's
services. The Flutter suite also covers admission vs game requests, optional host
selection, capacity-derived controls, public default creation, and narrow phone
layout. LiveKit administration is mocked in integration tests: real two-device
microphone/audio/background behavior still needs a device playtest. Existing
ordinary game runtime recovery behavior is preserved; this change does not add
durable recovery for an engine process restart.

Validation on this branch: 639 backend unit tests, 57 integration tests (including
17 Huud tests), and 222 Flutter tests passed. The analytics SQL executes against
the migrated test database. Flutter analysis reports no errors or warnings; 40
existing informational lint findings remain in legacy code. Run the
backend verification with `./backend/mvnw -f backend/pom.xml -pl ta-app -am verify`
and select `SocialHuudIT` plus existing integration suites as appropriate. Their
external-service properties are `it.r2dbc.url`, `it.jdbc.url`, `it.db.user`,
`it.db.password`, and `it.redis.port`. In `app/`, run `flutter test --no-pub` and
`flutter analyze --no-pub` after resolving Flutter dependencies.

## Phone release and offline pages

The 2026-10-09 phone release targets the existing HTTPS backend at
`https://vps-8030ec94.vps.ovh.net`, using the existing iOS bundle identifier.
Only the connected iPhone is installed; this is not an App Store or TestFlight release.

Home, activity feeds, Friends, conversation lists/messages, Profile statistics,
and Huud details/chat use account- and server-scoped persisted snapshots. Pages
hydrate from local storage immediately and refresh in the background. Saved
identity and tab selection also survive restarts. Session validation and game
recovery run after the app opens; temporary network failure preserves the login
and saved game reference. Failed session validation retries after 15 seconds and
on foreground resume. Fonts are bundled, with runtime font downloads disabled.

Snapshots expire after seven days and are bounded to 40 entries, 256 KiB per
entry and 2 MiB total. Signing out clears the account's page snapshots. HTTP
401/403/404/410 evicts the affected snapshot; transport failures and server
outages can fall back to saved content. Credentials, voice tokens and private
match state are excluded. Offline state has a small indicator; actions fail
visibly and are never queued for replay. Cached Huud data cannot automatically
launch a live match. Live games, sending messages and voice require connectivity.

Backend deployment keeps a private pre-migration database backup and previous
Docker image on the VPS. V37 is the exact SlayHuud migration from `8213d54`, so
V37 and V38 apply in order and a later SlayHuud merge retains the checksum.
