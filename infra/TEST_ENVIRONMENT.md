# Test server

A full copy of the production stack for trying changes before they go live. It runs
on the same VPS as production with separate storage and credentials. By user request, test now receives a full
production PostgreSQL snapshot; later changes in either environment remain independent.

| | Production | Test |
|---|---|---|
| API | `https://vps-8030ec94.vps.ovh.net` | `https://vps-8030ec94.vps.ovh.net/test` |
| LiveKit | `wss://vps-8030ec94.vps.ovh.net:8443` | `wss://vps-8030ec94.vps.ovh.net:8443/test` |
| Compose project | `truearena-prod` (`docker-compose.prod.yml`) | `truearena-test` (`docker-compose.test.yml`) |
| Folder on VPS | `~/truearena` | `~/truearena-test` |
| Backend image | `truearena-backend:prod` | `truearena-backend:test` |
| Database / Redis | `truearena-prod_pgdata` / `_redisdata` | `truearena-test_pgdata` / `_redisdata` |
| LiveKit media ports | 7881/tcp, 50000-50020/udp | 7891/tcp, 50100-50120/udp |
| Spring profile, `APP_ENV` | none, `production` | `test`, `test` |
| Secrets | `infra/keys/prod.env.local` | `infra/keys/test.env.local` |

## Push to test

```
infra/deploy-test.sh              # build this checkout's backend and restart test
infra/deploy-test.sh --reset-data # destructive test reset; removes the mirrored data
infra/deploy-test.sh --stack-only # deploy isolated containers; leave shared proxy/firewall untouched
```

The deployment writes to `~/truearena-test`, the `truearena-backend:test` image and
the `truearena-test` compose project. On first setup, `setup-test-proxy.sh` also
adds only `/test/*` routes to the existing Caddy configuration, validates it,
backs up the original under `~/truearena-test`, and performs a graceful reload.
Production routes are preserved and no production container is restarted.
Because Caddy is shared, first-time proxy setup needs explicit approval when
production changes are otherwise excluded. Existing game/voice WebSocket
connections can reconnect during the configuration reload; use `--stack-only`
to prepare and verify the isolated stack without that reload.
It opens only the dedicated test voice media ports. It prints `TEST OK` once
`/test/actuator/health` is up. Flyway runs migrations against the test database, so
**push a new migration to test first**: if it is wrong there, delete the test data
(`--reset-data`) and fix it. Once a migration has run in production it can't be edited.

## Point the app at test

The app reads its server from `API_BASE` at build time:

```
flutter run --dart-define=API_BASE=https://vps-8030ec94.vps.ovh.net/test
```

A test build uses the same bundle ID as the store app, so installing it replaces the
production app on that phone. Rebuild without the flag to go back.

## Signing in on test

The test server sends no real SMS, email or push notifications. Request a code as
normal, then enter the shared code from `TEST_OTP_BYPASS_CODE` in
`infra/keys/test.env.local`. It works only for identifiers listed in `TEST_OTP_ALLOWED_IDENTIFIERS`; currently
`barric3g@gmail.com`. The backend checks that allowlist on both request and verify.
Google/Apple sign-in still verifies each account with the provider. The
backend refuses to boot the `test` profile with `APP_ENV=production`, see
`EnvironmentGuard`.

The test profile short-circuits email delivery even if a provider key is present.
The test Compose file also leaves the email and Firebase credentials blank.

Accounts, coins, chats, Huuds, friendships, game history, moderation records and
all other tables are copied in a consistent PostgreSQL snapshot at the user's
request. This includes the existing SlayHuud tables, even where their older
migration files are absent from this branch. Flyway then applies the new test
migrations. The snapshot is a point-in-time copy, not continuous replication.

To refresh the full mirror (replaces test data, after backing it up):

```
infra/mirror-production-to-test.sh
infra/deploy-test.sh --stack-only
```

The mirror script reads production with `pg_dump`, restores into a temporary test
database first, and only switches test over after a successful restore. Existing
test data is preserved as both a dump and a renamed database for rollback.
Backups stay on the VPS under `~/truearena-test/backups/<UTC timestamp>` with
restricted permissions. It records every restored table's count and verifies
production container identities/start times did not change.

Only test's backend is stopped; deploy it after the mirror to migrate and resume.
Test Redis is cleared instead of copying production auth tokens, locks and live
presence. Test JWT/LiveKit/admin secrets remain separate. Existing account data
is mirrored, but users must sign in on test again. Running game processes and
voice connections are not database records and cannot be migrated live.
Never commit database dumps, copied personal data or environment secrets.

## How it's wired

Production's Caddy already owns ports 443 and 8443 and the TLS certificate. It
serves `/test/*` too, stripping the prefix and proxying to `truearena-test-backend`
or `truearena-test-livekit` over the `truearena-edge` Docker network. Caddy is
the only production container on that network. If the test stack is down, only
`/test` returns 502.

The test backend calls LiveKit's room API directly at `http://test-livekit:7880`
(`LIVEKIT_API_URL`), because LiveKit's server SDK drops the `/test` path prefix.

Test containers have memory caps (backend 1 GB, Postgres 512 MB, LiveKit 512 MB,
Redis 256 MB), so test can't use up production's RAM. CPU is shared, so the
backend jar is compiled on the developer machine; the VPS only packages the
runtime image. This avoids a Maven build competing with production.

## Commands on the VPS

```
cd ~/truearena-test/infra
docker compose -f docker-compose.test.yml --env-file .env ps
docker compose -f docker-compose.test.yml --env-file .env logs -f test-backend
docker compose -f docker-compose.test.yml --env-file .env exec test-postgres psql -U truearena
docker compose -f docker-compose.test.yml --env-file .env down      # stop test (keeps data)
```
