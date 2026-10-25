# Multiple Huuds per person — agreed plan

Status: agreed 24 October 2026; built on `feature/multi-huud` (25 October 2026).

Today each person owns one Huud (`huud_spaces_one_per_owner`, V44). One Huud mixes family, friends and strangers, so people get up to five, one per circle.

## Rules

1. **Up to 5 Huuds per person.** Each keeps its own name, privacy (private, friends or public), code, members, chat and championships. Guests still can't create one.
2. **One of your Huuds Live at a time.** Going Live in a second one asks once ("End Family Huud and go Live here?"), then ends the first and starts the second.
3. **Join unlimited Huuds, present in one.** Present means in the Live hangout (`live_at`: voice and games). Viewing another Huud's page and chat stays free.
4. **Entering a Huud takes you out of the one you're in**, after a "Leave Family Huud?" prompt. While you're in a game there, the move is blocked until the game ends, so nobody forfeits by accident.
5. **Acting hosts hand on.** Someone who stepped in as host elsewhere passes the role to the next person in line, as when leaving today.
6. **Delete frees a slot.** It's permanent, and members lose that Huud's chat. An archive that doesn't count toward 5 can follow if people ask for it.

## Changes

**Server (small)**
- Migration: drop `huud_spaces_one_per_owner`. No data changes; everyone has 0 or 1 Huud.
- Create: enforce the cap of 5 under the existing `huud-space-owner` lock.
- Go Live: end the owner's other Live Huud, after the client confirms.
- Enter Live: clear `live_at` in every other Huud, hand on any acting-host role, and refuse while the person is in a game.

**App (medium)**
- Home: a "Your Huuds (2/5)" list replaces the single own-Huud card (`huud_home_screen.dart`).
- Create sheet: makes a new Huud. At 5 it points to delete.
- Games tab (`openHuudForGame`): asks which Huud to start the game in.
- Prompts for switching Huuds and for the mid-game block.

**Older app versions.** `POST /huud-spaces` currently means "open my Huud, or make one". Older apps keep that meaning and get the newest Huud back, and `/huud-spaces/current` returns the Live one, otherwise the newest. Making a new Huud uses a new option, so older apps can't create extras by accident.

**Tests:** the cap, one Live at a time, one place at a time, host handoff, the mid-game block and the older-app behaviour.

Build on its own branch, test and commit, then ask before any install or deploy.

## As built

- **Migration V61** drops `huud_spaces_one_per_owner` and adds two unique indexes: one Live Huud per owner, and one Live hangout per person (`huud_space_members.live_at`). Anyone in several hangouts keeps the one they entered last.
- **`POST /huud-spaces`** takes `another: true` to make a new Huud (at most 5) and `switchLive: true` to end the owner's other Live Huud. Without `another` it opens your Huud, which `/current` also returns: the Live one, otherwise the newest. A second Huud without a name gets a number ("Ama's Huud 2").
- **`POST /huud-spaces/{id}/live`** takes `switchLive: true`. Without it, while another of your Huuds is Live, it answers 409.
- **Walking in** goes through `enterLive(id, user, move)`.
  - Joining, going Live and making a Huud move you from your other hangout. If you were covering as host there, the next person takes over. If you're in a game there, the request answers 409.
  - Opening a Huud page never moves you. Instead the view carries `elsewhere {id, name, playing}`.
- **App:**
  - Huud tab: "Your Huuds n/5", with New Huud until the fifth.
  - Create sheet: from the second Huud, a name is required, with quick-pick chips.
  - "One Live at a time" confirmation before Go Live, and before making a Huud while another is Live.
  - Games tab: asks which Huud when you have several.
  - Huud page: a "You're in X right now" banner with Come in here (or "finish your game first"). Voice stays where you are until you come in.
