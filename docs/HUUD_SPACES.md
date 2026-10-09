# Huud spaces

A Huud space is the persistent place people hang out and play one game after another. The game (an ordinary room) comes and goes; the Huud, its code, its people and its voice room stay until the host ends it or everyone has gone.

## App

- **Live tab** (`HuudScreen`): three tabs on one page — **Live now** (`LiveNowPanel`: live Huuds you can see, plus games to watch from `/rooms/discoverable`), **Friends** and **For you** (the existing feed). The old Watch tab is folded into Live now.
- **Huud tab** (`HuudHomeScreen`): the Huuds you're in right now, **Make a Huud** (name + privacy only — Friends · Private · Public, Friends by default), a 6-letter code box (falls back to a game code), and **Your Huuds**: past Huuds with who was there and what was played, filterable by Made by me / Joined.
- **Inside a Huud** (`HuudSpaceScreen`): orange card with name, host, people and code; Talk / Invite / People / Leave; **Play** (host picks from the game grid, members join the game; after a game: play again or pick another) and **People** (host crown, here/away, host can take someone out). Back and End are pinned at the top.
- Styling lives in `huud_kit.dart` and `theme/huud_colors.dart`: orange fills always carry dark ink, deeper `orangeText` for words on the page, 52pt+ tap targets, every button has an icon and a word, solid bottom sheets, friendly confirmations before Leave / End / take out. The nav pill shows a label under every icon.
- The app heartbeats `POST /huud-spaces/heartbeat` every 45s while in the foreground (stopped in the background), and `HUUD_SPACE` inbox events refresh open screens.

## Rules (server, `HuudSpaceService`)

- One live Huud per host (`huud_spaces_one_owned`); Create returns the existing one. Guests can join but not make one.
- Privacy decides discovery: Public → everyone, Friends → the host's friends. The code always works (it is the invitation) and is only shown to people inside.
- **Host succession**: when the host leaves, or their app is quiet for `huud.host-grace` (default 5 min), the Huud goes to the earliest-joined person still in it — skipping guests and anyone already hosting a live Huud. Someone who left and came back rejoins the end of the line. No eligible person → leaving ends the Huud.
- Members quiet for `huud.member-timeout` (default 10 min) are marked gone; a Huud with nobody left ends. Expiry runs every 30s.
- One game at a time: a waiting or playing game must finish or be put away (a waiting one is cancelled with stakes refunded) before another is picked.
- Removed people can't rejoin, see it on Live, use its voice room (`huud-<id>`, authorized in `CallRingService.canJoin` via `HuudSpaceAccess`) or see it in history.
- History leaves out finished Huuds that nobody else joined and nothing was played in.

## Schema

`V39__huud_spaces.sql`: `huud_spaces`, `huud_space_members` (rows outlive the Huud for history), `rooms.huud_space_id`. Numbered 39 because 37 (`slayhuud`) and 38 (`social_huud_sessions`) exist on other branches; Flyway here does not run out of order, so those must be applied before this one on any shared database.

## Validation

- `HuudSpaceIT` (12 tests): defaults and reopen, guests, privacy vs code, host hand-off on leave and on silence, rejoin order, expiry and ending, removal, history, one game at a time.
- `test/huud_space_test.dart`: create sheet (no description, Friends default), Huud tab and history, code join, host/member/preview views, leave confirmation, People tab, Live now.
- `integration_test/huud_smoke_test.dart` drives the real app on a simulator against a local backend and saves screenshots:

```bash
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/huud_smoke_test.dart \
  --dart-define=API_BASE=http://localhost:8091 -d <simulator>
```

It expects a `local`-profile backend (OTP `000000`) with `eric@huud.test` seeded, a past Huud named "Saturday Whot", and a live public Huud whose name contains "Zara".
