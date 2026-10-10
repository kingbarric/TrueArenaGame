# Monopoly test deployment — 10 October 2026

**Test API:** `https://vps-8030ec94.vps.ovh.net/test`  
**Test voice:** `wss://vps-8030ec94.vps.ovh.net:8443/test`

The Monopoly branch contains **remote main `b2dc34d`**, checked again before
deployment. The isolated test backend image is labelled with deployed application
revision **`bb0309c4e69e04d7bd5bdd63ef76c247355661d0`**. Later documentation changes
do not change that application image.

**Deployment:** separate `truearena-test` PostgreSQL, Redis, LiveKit and backend
containers and volumes. Migration **V48 — Monopoly** applied successfully. The
Java application was compiled on this Mac and packaged on the VPS, avoiding a
Maven compilation competing with production's CPU.

**Verified through both a private SSH tunnel and public HTTPS/WSS:** email code
request and test sign-in; two-player admin-selected roster and start; all 40 board
spaces; authoritative server dice; spectator state without private offers or
future randomness; persistent Huud chat; WebSocket reconnect; default microphone
permission for selected players. The disposable verification Huuds were removed.
Test voice signaling answers successfully over TLS.

**Production:** application, database, Redis and LiveKit container IDs and start
times match the pre-deployment snapshot. Production health remains UP. The user
explicitly approved adding the test-only routes to shared Caddy, attaching Caddy
to the test network, and opening voice ports **7891/TCP** and **50100–50120/UDP**.
The candidate proxy configuration passed Caddy validation, the previous file was
backed up under `~/truearena-test/infra`, and the proxy was reloaded without a
container restart. Production code and user data were not deployed or copied.

**Phone artifact:** signed iOS release build **1.0.1 (2026101054)**, compiled with
`API_BASE=https://vps-8030ec94.vps.ovh.net/test`. Installed and launched on
**iKingbarric — iPhone 16 Pro**; `devicectl` confirmed the installed bundle version.
Test accounts are separate from
production. Request a sign-in code normally and use the private
`TEST_OTP_BYPASS_CODE` from `infra/keys/test.env.local`; no email is sent.

**Runtime limit:** reconnect to a running backend is supported. Full ordinary
game recovery after a server-process restart remains a release prerequisite,
as recorded in [the implementation notes](IMPLEMENTATION.md).

Repeat a test-only deployment from this branch with [the deployment script](../../infra/deploy-test.sh).
Use `--stack-only` to leave the shared proxy/firewall unchanged.
