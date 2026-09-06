#!/usr/bin/env bash
# Phase 0.3 smoke check for the local dev stack.
set -euo pipefail

BASE="${1:-http://localhost:8080}"
fail() { echo "SMOKE FAIL: $1" >&2; exit 1; }

echo "==> backend health"
curl -fsS "$BASE/actuator/health" | grep -q '"status":"UP"' || fail "backend not UP"

echo "==> redis"
docker compose -f "$(dirname "$0")/docker-compose.yml" exec -T redis redis-cli ping | grep -q PONG || fail "redis no PONG"

echo "==> postgres"
docker compose -f "$(dirname "$0")/docker-compose.yml" exec -T postgres \
  psql -U truearena -d truearena -tAc 'select 1' | grep -q 1 || fail "postgres select failed"

echo "==> livekit signal"
curl -fsS "http://localhost:7880" >/dev/null || fail "livekit signal port closed"

echo "SMOKE OK"
