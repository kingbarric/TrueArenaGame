# PlayHuud release preparation — 16 October 2026

This release brings the tested application and backend onto `release`, including
public game invitations, compact online-first player selection, the 3D/grid
switch, and confirmed Cyber Agent seats with server-side head-to-head capacity.
It also includes the accumulated SlayHuud, avatar and championship changes that
were already exercised on the isolated test deployment.

## Production configuration and delivery

Production is on database version 52. All 50 applied migrations present locally
have matching Flyway checksums. The historical, absent V38 is covered by the
existing missing-migration allowance. V53–V57 are the pending schema upgrade.

The previous release workflow had no production connection environment and
assumed a GHCR image and remote checkout that the running server did not use.
The production workflow now deploys its verified runtime artifact and a limited
public configuration bundle using a forced-command SSH key. GitHub's production
environment permits only `release`. Host keys are pinned. The archive validator
rejects path traversal, private environment files, symlinks, duplicate members,
oversized archives and revision mismatches. Public website files come only from
Git-tracked files, excluding local APKs and downloaded art.

The server builds an image labelled with the exact release SHA, snapshots its
current runtime, public files, environment and database, and restarts only the
production backend. Caddy configuration is validated before reload. Health,
Redis, PostgreSQL, LiveKit and the deployed SHA are checked. A failed update
restores the preceding runtime/configuration; a database snapshot is retained
without automatically overwriting newer user data.

Production keeps its private `.env` and optional `reviewer.env` on the server.
The scoped reviewer account remains configured. Production explicitly uses its
production profile, INFO application logging and the internal LiveKit admin URL.
Test and development OTP bypass profiles remain prohibited by EnvironmentGuard.

**Existing limitation:** Brevo is not configured in either server environment;
production email-code delivery is unavailable. Google and Apple sign-in remain
configured. The reviewer account is separately scoped and has a configured expiry.
SlayHuud assets still use the existing R2 public development hostname; a custom
asset hostname remains an operational improvement.

## Validation

- Complete Flutter suite: 448 passed; analyzer has advisory infos, no errors or warnings.
- Backend unit checks: 768 tests, zero failures/errors, one optional live-storage check skipped.
- Renderer: 94 passed.
- Contract examples: full JSON-schema validation passed.
- Release archive: real bundle pack/unpack, malicious-path tests, Bash syntax and production Compose validation passed.
- Full database and six-player WebSocket contract checks: 129 passed with zero failures/errors.
- Deployment packaging preserves app-user read access even under private server staging permissions.

## Bootstrap and rollback

The administrator-installed server entry point is
`infra/ci-deploy-production-restricted.sh`, with `infra/release_bundle.py` beside
it. The dedicated public key is pinned to that command in `authorized_keys`.
Updating these trusted entry-point files requires the existing administrative
connection; the CI upload cannot replace them or access server credentials.
Rollback snapshots are private under `/home/ubuntu/truearena/backups/`.
