# Monopoly test deployment — 10 October 2026

**Test API:** `https://vps-8030ec94.vps.ovh.net/test`  
**Test voice:** `wss://vps-8030ec94.vps.ovh.net:8443/test`

The Monopoly branch contains **remote main `b2dc34d`**, checked before deployment.
The isolated test backend image is labelled with deployed application revision
**`95abbdc0c3b1bc46ef5f148590a17dd19f754baf`**. Subsequent cache/privacy and
report changes do not change the backend image.

## Full database mirror

At the user's request, all **69 public PostgreSQL tables** were copied in a
consistent production snapshot at **22:20 UTC**. This includes **49 accounts**,
83 rooms, 123 room memberships, 5,550 recorded game events, game results,
friendships, conversations/messages, Huuds/chat, moderation and all six legacy
SlayHuud tables. Rows, relationships, sequences and existing Flyway history were
restored together. No production credentials, Redis authentication sessions,
locks or active voice connections were copied.

The previous test database is retained as `previous_20261010T222052Z` and as a
dump. Production snapshot and test backup are under
`~/truearena-test/backups/20261010T222052Z`, readable only by the deployment user.
Per-table snapshot counts are recorded there. These files remain on the VPS and
are never tracked in Git. This is a point-in-time copy; subsequent test activity
is independent of production.

Flyway applied **V46 — Huud championships**, **V48 — Monopoly** and **V49 — Blank
Huud background** to the copied database, preserving old V37/V38 tables/history.
V49 corrects the original failure: the UI offered Blank but V43's database
constraint rejected it.

Test has separate PostgreSQL/Redis volumes, JWT/LiveKit/admin credentials and
services. Real email/SMS/push delivery remains disabled. The test OTP bypass is
restricted to **`barric3g@gmail.com`**, checked on both request and verification.
Other accounts can authenticate only through their normally verified provider.

## Verification

- Full backend unit suite passed; reports contain 705 tests with no failures.
- **35 Huud PostgreSQL integration tests** passed, including every background.
- **311 Flutter tests** passed. Four Monopoly screen tests were then rerun after
  excluding private legal/trade actions from offline cache; all passed.
- Public HTTPS/WSS check: approved copied-account sign-in, rejection of
  unapproved OTP accounts, all five backdrop settings, generic public errors,
  two added Cyber Agents, admin starting as a watcher, autonomous dice/property
  decisions and turn advance, spectator-safe state. Disposable fixtures were
  removed without altering copied users' Huuds.
- Both production and test health endpoints report UP. Production application,
  PostgreSQL, Redis and LiveKit container IDs/start times match the earlier
  baseline. No production deployment, data write or service restart occurred.

The previously approved test routes and dedicated voice ports remain unchanged;
this deployment used `--stack-only`, with no shared proxy/firewall changes.

## Phone

Signed iOS release **1.0.1 (2026101061)**, compiled with
`API_BASE=https://vps-8030ec94.vps.ovh.net/test`, for **iKingbarric — iPhone 16 Pro**.
After the database refresh, sign in again using the approved email and the
private test code; real production login sessions do not transfer to test.

## Runtime limit

A database copy preserves records, not running game processes or live voice.
Monopoly now saves a private PostgreSQL checkpoint before publishing state and
restores it after a backend restart, including pause/clock, private offers and
future randomness. Matches interrupted before V50 return to setup in the same
Huud because their earlier boards were never persisted. Other games retain
their existing recovery behavior; see [implementation notes](IMPLEMENTATION.md).

Repeat a test-only deployment with [deploy-test.sh](../../infra/deploy-test.sh)
and `--stack-only`. Refresh the full snapshot using
[mirror-production-to-test.sh](../../infra/mirror-production-to-test.sh), then
redeploy to migrate and start test. The workflow is documented in
[TEST_ENVIRONMENT.md](../../infra/TEST_ENVIRONMENT.md).

## UI/music phone update — 11 October 2026

Application revision **`9ddc5a3`** enlarges the board/perimeter, removes the
separate turn banner, reuses the existing mic and pause controls, and adopts
Chess's minimisable chat. Monopoly's cinematic track is bundled for offline
playback and controlled by the existing persisted music setting. Music source,
license and preparation are recorded in the app's credits and game settings.

The signed release **1.0.1 (2026101101)** was installed on and launched on
**iKingbarric — iPhone 16 Pro**. CoreDevice verified that bundle version on the
phone. The build uses `API_BASE=https://vps-8030ec94.vps.ovh.net/test`; the bundled
music asset's SHA-256 matches the checked-in file.

Validation: **314 full Flutter tests passed**, followed by **13 Monopoly
layout/screen tests** after final label fitting; the changed components' Flutter
analysis reports no issues. Rendered phone UI was inspected, including all
40 spaces; tests cover small screens, enlarged text, keyboard chat, spectators,
offline state and the shared pause/resume transport.

Remote main remains **`b2dc34d`** and is contained in this branch. This is an
app-only release: no backend deployment, data refresh, proxy change, production
write or merge into main was performed.

## Match recovery, autoplay and quit — 11 October 2026

The recovery changes were merged into main at **`da42808`**, followed by the
server/agent pause correction **`b4740f0`**. The test backend runs `b4740f0`,
with Flyway **V50** applied. The signed **1.0.1 (2026101103)** build is installed
on iKingbarric's iPhone 16 Pro and uses the test API. Music starts with the live
match; settings provides a confirmed **Quit Game** action.

Validation: **321 Flutter tests**, **710 backend unit tests** and **37 local
PostgreSQL/Redis Huud integration tests passed**. A disposable Huud on the public
test endpoint verified start, positive-sequence reopen, an actual test-backend
restart preserving board/session/paused clock, duplicate Start, player forfeit,
agent resumption and saved results. The fixture was removed. Production's
backend, PostgreSQL, Redis, Caddy and LiveKit identities/start times were
identical before and after; `release` remains **`b2dc34d`**.

This deployment used the restricted test SSH command manually. Automatic
main deployment still needs the encrypted `TEST_DEPLOY_SSH_KEY` credential;
uploading the new restricted key awaits the user's pending approval.
