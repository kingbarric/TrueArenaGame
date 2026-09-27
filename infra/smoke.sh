#!/usr/bin/env bash
# Phase 0.3 smoke check for the local dev stack; also used post-deploy (see
# the `deploy` job in .github/workflows/ci.yml), pointed at whichever compose
# file is actually running on that host.
set -euo pipefail

BASE="${1:-http://localhost:8080}"
COMPOSE_FILE="${2:-$(dirname "$0")/docker-compose.yml}"
[ -f "$COMPOSE_FILE" ] || COMPOSE_FILE="$(dirname "$0")/docker-compose.prod.yml"
fail() { echo "SMOKE FAIL: $1" >&2; exit 1; }

echo "==> backend health"
curl -fsS "$BASE/actuator/health" | grep -q '"status":"UP"' || fail "backend not UP"

echo "==> redis"
docker compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping | grep -q PONG || fail "redis no PONG"

echo "==> postgres"
docker compose -f "$COMPOSE_FILE" exec -T postgres \
  psql -U truearena -d truearena -tAc 'select 1' | grep -q 1 || fail "postgres select failed"

echo "==> livekit signal"
curl -fsS "http://localhost:7880" >/dev/null || fail "livekit signal port closed"

echo "SMOKE OK"
