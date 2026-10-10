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
Reconnect to a running backend is supported. Recovery of an ordinary match after
a backend process restart remains outside this implementation; see
[implementation notes](IMPLEMENTATION.md).

Repeat a test-only deployment with [deploy-test.sh](../../infra/deploy-test.sh)
and `--stack-only`. Refresh the full snapshot using
[mirror-production-to-test.sh](../../infra/mirror-production-to-test.sh), then
redeploy to migrate and start test. The workflow is documented in
[TEST_ENVIRONMENT.md](../../infra/TEST_ENVIRONMENT.md).
