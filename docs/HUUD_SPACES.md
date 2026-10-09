# Huud spaces

A Huud space is the persistent place people hang out and play one game after another. Feed = people and content; Huud = the social room; Game = the activity inside the Huud. The game (an ordinary room) comes and goes; the Huud, its code, its people, its chat and its voice room stay until the host ends it or everyone has gone.

## App

Bottom menu: **Live · Huud · Games · Friends · You** (labels under every icon).

- **Live** (`HuudScreen`): **Live now** (`LiveNowPanel`: live Huuds you can see + games to watch), **Friends** and **For you** feeds. The feed has no game-request composer any more; it shows people content (wins, challenges, tournaments) and **shared Huuds** — "Who wants to play Whot?" · Eric's Huud · Whot · 2/4 playing · Join Huud / Ask to join / Go in.
- **Huud** (`HuudHomeScreen`): the Huuds you're in, **Make a Huud**, a code box, and **Your Huuds** history with who was there and what was played.
- **Make a Huud** (`CreateHuudSheet`): name + Friends/Private/Public, then optional: a first game, and "Show it on the feed" with a short line.
- **Games**: tapping a game (signed-in accounts) opens your Huud — the game becomes the next one if nothing's on, never replacing one that is — or Make a Huud with that game picked. "Just play a quick game instead" keeps the old lobby (bots, solo). Guests and signed-out players go straight to the old lobby.
- **Friends**: tabs **Friends · Messages · Requests** (Messages is the old Chats list; Requests carries a count).
- **Inside a Huud** (`HuudSpaceScreen`): orange card (name, host, people, code), Talk/Listen · Ask mic · Invite · Leave, the host's **asking** box (join/play/mic requests with big ✓/✗), and tabs **Play · Chat · People**. Play: host picks the game; members **Ask to play**; players open their seat; others **Watch** once it starts. Chat: Huud chat, long-press a message to report. People: tap someone for mic on/off, take out (host) and **Report or block** (everyone).
- **Safety** (`showSafetySheet`): report with a reason (mean / unsafe / spam / other), "Also block" on by default, a "tell a grown-up" note for unsafe; block keeps you apart.
- **Voice**: `CallScreen` joins listen-only when the token can't publish; the mic button becomes "Ask to talk"; a host grant flips live (`setCanPublish`) and the player taps the mic when ready.
- **Watching**: anyone allowed to see a Huud (public, host's friends, invited) can look in without joining (`POST /huud-spaces/{id}/watch`, refreshed while on screen): Play and People tabs, Watch the game by room id — no chat, voice or seat. The Huud and Live cards show "N watching". Tapping a Live card opens `HuudSwipeScreen`: one Huud per screen, swipe up/down, a big Join / Ask to join / Go in.
- **Who's talking**: the minimized call bar (`PersistentHangout`, above every game screen) shows `TalkingRow` — faces with an orange glow on whoever's speaking and "Ada is talking".
- **Rematch**: after a game the host gets "Rematch — same players" (the last players still in the Huud are seated straight away) or "Play … with new players".
- **Feed text posts**: "Say something to your friends…" on the Friends tab only (`/huud/text-posts`); posts show to you and your friends, never For you; ⋯ → delete yours / report others'.
- **Push**: invites, requests to the host and the host's yes go to phones that are away (`sendToUserIfOffline`); tapping opens the Huud. On the main tabs the same events show an in-app banner with Open.
- **Startup**: only the game screen the app was closed on is reopened (`GameSocket.currentPlayerRoom` → `ta_resume_room`); a lobby you backed out of no longer pops open on launch.

## Reports (web admin)

`website/notvisible/reports/` (linked from Analytics and Broadcasts), behind the admin key: open / reviewed / all reports with reason, who reported whom, the exact chat message or feed post, the Huud, and how many reports the player has; "Mark reviewed" with a note and the reviewer's name, and "Take post down & mark reviewed" for posts (`/api/v1/admin/reports`).

## Rules (server)

`HuudSpaceService` (core), `HuudSpaceRequestService` (asks/answers/invites/mic), `HuudSpaceChatService`, `SafetyService` (`/api/v1/players/{id}/block|report`).

- One live Huud per host; Create reopens it. Guests can join but not make one.
- **Joining**: Public → anyone straight in; Friends → the host's friends straight in; everyone else, and everyone for Private, **asks** (`huud_space_requests` kind `join`) unless invited by the host or let in before. The code finds a Huud; it doesn't bypass the rules. Declined askers wait 5 minutes before asking again.
- **Joining the Huud is not joining the game.** Members ask to play (`kind=play`, tied to the current room); the host's yes seats them via `RoomService.join` (full games refuse). A new game clears the queue. The host plays by default (they create the room).
- **Mic**: members listen; the host and anyone handed the mic (`huud_space_members.can_speak`) speak. Huud voice tokens are minted with `canPublish` accordingly.
- **Game code**: only players and the host get the room code; everyone else watches by room id, so the host's roster can't be skipped.
- **Chat**: members only, 300 characters, 5 messages per 10 seconds, delivered over the inbox; blocked senders are filtered.
- **Block**: no joining or seeing each other's Huuds (Live, feed, view), chat hidden, friendship removed, removed from the blocker's live Huud. **Report**: stored in `player_reports` with the reported message's text.
- **Host succession**: host leaves or is quiet for `huud.host-grace` (5 min) → the earliest-joined person still in it (no guests, nobody already hosting).
- Members quiet for `huud.member-timeout` (10 min) are marked gone; an empty Huud ends. Ending cancels a waiting game and clears the feed share.

## Schema

- `V39__huud_spaces.sql`: `huud_spaces`, `huud_space_members`, `rooms.huud_space_id`.
- `V40__huud_space_social.sql`: feed share columns, `can_speak`, `huud_space_requests`, `huud_space_messages`, `player_blocks`, `player_reports` (named `player_*` because production carries an unused `user_blocks` from a dropped branch).
- `V41__huud_watch_posts_review.sql`: `huud_space_viewers`, `feed_posts`, report review columns + `feed_post_id`/`post_body`.
- `spring.flyway.ignore-migration-patterns: "*:missing"`: production has V37/V38 applied from that dropped branch.

## Validation

- `HuudSpaceIT` (22): watching + code hiding, rematch, text posts + report review/take-down, join rules per privacy, private ask/invite/decline, roster selection and seats, mic, chat + flood limit, block/report, feed sharing, plus lifecycle/succession/history.
- `test/huud_space_test.dart`, `test/huud_feed_test.dart`, `test/game_resume_test.dart`, `test/friends_search_test.dart`.
- `integration_test/huud_smoke_test.dart` drives the real app on a simulator against a local backend (19 screenshots):

```bash
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/huud_smoke_test.dart \
  --dart-define=API_BASE=http://localhost:8091 \
  --dart-define=SMOKE_PRIVATE_CODE=<someone else's private Huud code> -d <simulator>
```

It expects a `local`-profile backend (OTP `000000`) where `eric@huud.test` hosts a shared public Whot Huud with a pending play request, a mic request and some chat, and has friends plus one incoming friend request.
