# Huud spaces

A Huud is a permanent room — one per owner. Feed = people and content; Huud = the social room; **Live** = a hangout inside it; Game = the activity during Live. The Huud's name, members, chat, privacy, background, code and owner stay for good; the owner taps **Go Live** to open a hangout and **End Live** to close it, which resets the game, roster, play/mic requests, watchers and voice but keeps everything else. The owner can delete the Huud in settings. The app never says "session".

## App

Bottom menu: **Live · Huud · Games · Friends · You** (labels under every icon).

- **Live** (`HuudScreen`): **Live now** (`LiveNowPanel`: live Huuds you can see + games to watch), **Friends** and **For you** feeds. The feed has no game-request composer any more; it shows people content (wins, challenges, tournaments) and **shared Huuds** — "Who wants to play Whot?" · Eric's Huud · Whot · 2/4 playing · Join Huud / Ask to join / Go in.
- **Huud** (`HuudHomeScreen`, `GET /huud-spaces/mine`): your Huud on top — Live ("Live now · 8 in Huud · Playing Whot", Go in) or Offline ("Offline · 4 members", **Go Live** / Open) — or **Make your Huud**; a code box; **Huuds you're in** (Live ones highlighted, 🔕 on muted ones).
- **Go Live** (`goLive`, `go_live_sheet.dart`): the owner chooses who's told — all members (inbox + push, except who muted it), only members online now, or nobody — then `POST /huud-spaces/{id}/live {notify: all|online|none}`. A Games tab tap on an offline Huud goes through Go Live first.
- **Offline Huud**: Chat and People tabs only; the owner sees "Your Huud is offline" + Go Live, members "Not Live right now — you'll get a notification". Members have a bell (`POST …/mute {muted}`) to mute that Huud. Leave Huud (members only) ends membership and notifications; the owner can't leave, only delete (settings → Delete Huud → confirm, `DELETE /huud-spaces/{id}`).
- **Make a Huud** (`CreateHuudSheet`): name + Friends/Private/Public, then optional: a first game, and "Show it on the feed" with a short line.
- **Games**: tapping a game (signed-in accounts) opens your Huud — the game becomes the next one if nothing's on, never replacing one that is — or Make a Huud with that game picked. "Just play a quick game instead" keeps the old lobby (bots, solo). Guests and signed-out players go straight to the old lobby.
- **Friends**: tabs **Friends · Messages · Requests** (Messages is the old Chats list; Requests carries a count).
- **Inside a Huud** (`HuudSpaceScreen`): orange card (Live/Offline, name, host, "N in Huud · M members", code), End Live (host) in the top bar, Talk/Listen · Ask mic · Invite · Leave (not for the owner), the host's **asking** box (join/play/mic requests with big ✓/✗), and tabs **Play · Chat · People**. Play: host picks the game; members **Ask to play**; players open their seat; others **Watch** once it starts. Chat: Huud chat, long-press a message to report. People: tap someone for mic on/off, take out (host) and **Report or block** (everyone).
- **Safety** (`showSafetySheet`): report with a reason (mean / unsafe / spam / other), "Also block" on by default, a "tell a grown-up" note for unsafe; block keeps you apart.
- **Voice**: `CallScreen` joins listen-only when the token can't publish; the mic button becomes "Ask to talk"; a host grant flips live (`setCanPublish`) and the player taps the mic when ready.
- **Watching**: anyone allowed to see a Huud (public, host's friends, invited) can look in without joining (`POST /huud-spaces/{id}/watch`, refreshed while on screen): Play and People tabs, Watch the game by room id — no chat, voice or seat. The Huud and Live cards show "N watching". Tapping a Live card opens `HuudSwipeScreen`: one Huud per screen, swipe up/down, a big Join / Ask to join / Go in.
- **Who's talking**: the minimized call bar (`PersistentHangout`, above every game screen) shows `TalkingRow` — faces with an orange glow on whoever's speaking and "Ada is talking".
- **Choosing players**: when a game is on in a Huud, its Play card and the game's own lobby list everyone in the Huud (`HuudRoster`). The host taps people to seat them or let them watch, up to the seats; seated players show ✅ Ready / ⏳ Not ready yet; Add Cyber Agent is the only button (`/rooms/{id}/bots`). Picked players get a push/banner, open the game and Ready up; the host Starts; everyone else watches and chats. The lobby of a Huud game doesn't show the room code.
- **Reactions**: ❤️ 👍 😂 😮 🔥 👏 on text posts — one each, the same one again takes it back, counts on the post (`POST /huud/text-posts/{id}/reaction`, V42).
- **Rematch**: after a game the host gets "Rematch — same players" (the last players still in the Huud are seated straight away) or "Play … with new players".
- **Feed text posts**: "Say something to your friends…" on the Friends tab only (`/huud/text-posts`); posts show to you and your friends, never For you; ⋯ → delete yours / report others'.
- **Push**: invites, requests to the host and the host's yes go to phones that are away (`sendToUserIfOffline`); tapping opens the Huud. On the main tabs the same events show an in-app banner with Open.
- **Backgrounds**: the host picks Default (none), Lounge, Poolside or Club in Huud settings (`PATCH … {background}`, V43); `HuudBackdrop` shows it under the Huud screen and the swipe page with a page-coloured wash so cards stay readable. Pictures in `assets/images/huud_backgrounds/`.
- **Huud icon**: `assets/images/branding/huud_icon.png` (`huudIcon`) on the Huud tab, Huud headers, Make a Huud and Huud banners.
- **Startup**: a notification that opened the app counts once and only while it's under an hour old (iOS can replay an old "Your turn" on every launch); only the game screen the app was closed on is reopened (`GameSocket.currentPlayerRoom` → `ta_resume_room`); a lobby you backed out of no longer pops open on launch.

## Reports (web admin)

`website/notvisible/reports/` (linked from Analytics and Broadcasts), behind the admin key: open / reviewed / all reports with reason, who reported whom, the exact chat message or feed post, the Huud, and how many reports the player has; "Mark reviewed" with a note and the reviewer's name, and "Take post down & mark reviewed" for posts (`/api/v1/admin/reports`).

## Rules (server)

`HuudSpaceService` (core), `HuudSpaceRequestService` (asks/answers/invites/mic), `HuudSpaceChatService`, `SafetyService` (`/api/v1/players/{id}/block|report`).

- One Huud per owner (`created_by`, unique while `status='active'`); Create reopens it. `owner_id` is whoever is hosting right now. Guests can join but not make one.
- **Live**: `live_since` set while Live. Members in the hangout have `live_at`; opening a Live Huud you belong to puts you in it. Being away only clears `live_at` — membership ends only on Leave or being taken out (`left_at`). People can join (become members) while the Huud is offline. Play/mic asks, watching, voice and the feed share need Live.
- **Joining**: Public → anyone straight in; Friends → the host's friends straight in; everyone else, and everyone for Private, **asks** (`huud_space_requests` kind `join`) unless invited by the host or let in before. The code finds a Huud; it doesn't bypass the rules. Declined askers wait 5 minutes before asking again.
- **Joining the Huud is not joining the game.** Members ask to play (`kind=play`, tied to the current room); the host's yes seats them via `RoomService.join` (full games refuse). A new game clears the queue. The host plays by default (they create the room).
- **Mic**: members listen; the host and anyone handed the mic (`huud_space_members.can_speak`) speak. Huud voice tokens are minted with `canPublish` accordingly.
- **Game code**: only players and the host get the room code; everyone else watches by room id, so the host's roster can't be skipped.
- **Chat**: members only, 300 characters, 5 messages per 10 seconds, delivered over the inbox; blocked senders are filtered.
- **Block**: no joining or seeing each other's Huuds (Live, feed, view), chat hidden, friendship removed, removed from the blocker's live Huud. **Report**: stored in `player_reports` with the reported message's text.
- **Host cover during Live**: if the host leaves the hangout or is quiet for `huud.host-grace` (5 min), the next person in the hangout (by `live_at`, no guests) runs that Live only; ownership never moves, and the owner takes over again when they come back.
- Members quiet for `huud.member-timeout` (10 min) step out of the hangout; Live ends by itself when nobody is in it. Ending Live cancels a waiting game and clears the feed share. Events: `live`, `live-ended`, `deleted`, `member`, `away`, `host`.

## Schema

- `V39__huud_spaces.sql`: `huud_spaces`, `huud_space_members`, `rooms.huud_space_id`.
- `V40__huud_space_social.sql`: feed share columns, `can_speak`, `huud_space_requests`, `huud_space_messages`, `player_blocks`, `player_reports` (named `player_*` because production carries an unused `user_blocks` from a dropped branch).
- `V41__huud_watch_posts_review.sql`: `huud_space_viewers`, `feed_posts`, report review columns + `feed_post_id`/`post_body`.
- `V42__feed_post_reactions.sql`: `feed_post_reactions`.
- `V43__huud_background.sql`: `huud_spaces.background`.
- `V44__persistent_huuds.sql`: `huud_spaces.live_since`, `huud_space_members.live_at` / `muted`, one active Huud per `created_by`. Existing data: Huuds on at the time become Live; everyone else's latest ended Huud comes back offline with its members (a fresh code if its old one is taken); older ended Huuds stay gone.
- `spring.flyway.ignore-migration-patterns: "*:missing"`: production has V37/V38 applied from that dropped branch.

## Validation

- `HuudSpaceIT` (25): watching + code hiding, rematch, text posts + report review/take-down, join rules per privacy, private ask/invite/decline, roster selection and seats, mic, chat + flood limit, block/report, feed sharing, plus Go Live notify choices + mute, End Live keeping the Huud, joining offline, away vs Leave, host cover and owner takeover, delete.
- `test/huud_space_test.dart`, `test/huud_feed_test.dart`, `test/game_resume_test.dart`, `test/friends_search_test.dart`.
- `integration_test/huud_live_test.dart` walks your Huud offline → Go Live → End Live and a muted member Huud, dark and light (seed: Eric owns an offline Huud with members and chat, is a member of a friend's Live Huud and of an offline one he muted).
- `integration_test/huud_smoke_test.dart` drives the real app on a simulator against a local backend (19 screenshots):

```bash
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/huud_smoke_test.dart \
  --dart-define=API_BASE=http://localhost:8091 \
  --dart-define=SMOKE_PRIVATE_CODE=<someone else's private Huud code> -d <simulator>
```

It expects a `local`-profile backend (OTP `000000`) where `eric@huud.test` hosts a shared public Whot Huud with a pending play request, a mic request and some chat, and has friends plus one incoming friend request.
