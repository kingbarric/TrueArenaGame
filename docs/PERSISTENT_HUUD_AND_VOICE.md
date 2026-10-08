# Persistent Huuds and social voice

Waiting game rooms belong to their creator until explicitly cancelled. Leaving a lobby closes its socket, not the room. Opening the same game first checks `/rooms/pending/{gameType}` and resumes the saved roster/code/rules through `JoinedRoomScreen`. Creating a room is also serialized by a Postgres advisory transaction lock and reuses the creator’s pending ordinary room. Championship rooms are excluded. Cancellation refunds stakes, retires the code, and notifies connected lobby members.

Voice membership is stored in `voice_sessions`, `voice_session_participants`, and `voice_session_invites` (Flyway V36). Games optionally reference a voice session through `rooms.voice_session_id` and `game_sessions.voice_session_id`. Starting/ending a game changes its optional link; ending a game never terminates voice membership.

`HangoutState` and the app-level `PersistentHangout` own the mounted call independently of routes. `CallScreen` retains the existing LiveKit, ringing, E2EE, and reconnect implementation. Back/minimize leaves it running with a call bar; call bar actions can show people, mute, start another game, or leave. All game mic controls use this shared connection and show speaking activity. Profile avatars are fetched with session participants and game room rosters.

Only the host is the call admin. They can mute/remove participants, change privacy/invite permissions, transfer host control, or end the call for everyone. Participants can leave individually and locally mute another person. A host leaving with others present selects the next host. Server authorization checks enforce these roles. Removed participants require a new invitation/approval to rejoin.

The Huud header has Hangouts discovery. Public/friends hangouts support join requests with host approval. Joining does not create friendships. Encrypted direct calls retain invite-only/private privacy and their existing encrypted invitation flow. Existing DM/group friend and membership checks remain in use; the repository currently has no separate block/report service to integrate.

A partial unique index enforces one active durable membership per user. Rejoins preserve mute state and joinedAt. Voice heartbeats run independently of game sockets. Explicit leave clears membership; ten minutes without a heartbeat expires it, closes empty sessions, and transfers an absent host to a remaining participant. LiveKit reconnect uses the existing two-minute recovery window and refreshed tokens.

## Validation

`VoiceSessionIT` exercises the database migration, creator/code recovery, cancellation and new code, concurrent creation, direct/group voice with games, game switching, spectators, independent leave, mute/rejoin, switching calls, host transfer, host removal/end, privacy approval, and absence of friendship side effects. `persistent_hangout_test.dart` checks route changes/results and explicit call switching without starting native audio in a widget test. Existing backend and Flutter suites cover the game and call infrastructure.

Release backend V36 before shipping the updated client. Real microphone audio, E2EE invitation audio, and network handoff still need a two-device smoke test; automated navigation/database tests cannot verify SFU audio delivery.
