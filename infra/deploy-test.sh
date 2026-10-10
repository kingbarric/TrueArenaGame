#!/usr/bin/env bash
# Deploys this checkout's backend to the TEST server — never production.
# See infra/TEST_ENVIRONMENT.md.
#
#   infra/deploy-test.sh              build + restart the test backend
#   infra/deploy-test.sh --reset-data also wipe the test database and redis first
#
# Everything lands under ~/truearena-test on the VPS (production lives in
# ~/truearena and is never written to). The image is truearena-backend:test, the
# compose project is truearena-test. The one shared piece is the truearena-edge
# network, which production's caddy joins so it can serve /test.
set -euo pipefail

cd "$(dirname "$0")/.."
HOST=ubuntu@51.38.71.193
KEY=infra/keys/truearena_deploy_key
ENV_FILE=infra/keys/test.env.local
PUBLIC=https://vps-8030ec94.vps.ovh.net/test
SSH=(ssh -i "$KEY" "$HOST")
COMPOSE="docker compose -f docker-compose.test.yml --env-file .env"

reset=false
[ "${1:-}" = "--reset-data" ] && reset=true

[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE (test secrets) — see infra/TEST_ENVIRONMENT.md" >&2; exit 1; }

echo "==> building this checkout's backend locally"
./backend/mvnw -B -q -DskipTests -f backend/pom.xml -pl ta-app -am package

echo "==> preparing ~/truearena-test and the truearena-edge network"
"${SSH[@]}" 'set -e
  mkdir -p ~/truearena-test/backend ~/truearena-test/infra
  docker network inspect truearena-edge >/dev/null 2>&1 || docker network create truearena-edge >/dev/null
  # Attaching a running container to a network is live — caddy keeps serving.
  docker network inspect truearena-edge -f "{{range .Containers}}{{.Name}} {{end}}" | grep -q truearena-prod-caddy-1 \
    || docker network connect truearena-edge truearena-prod-caddy-1'

echo "==> syncing backend source and test config"
rsync -az --delete --exclude=target --exclude=.git -e "ssh -i $KEY" backend/ "$HOST:~/truearena-test/backend/"
rsync -az -e "ssh -i $KEY" infra/docker-compose.test.yml infra/livekit.test.yaml "$HOST:~/truearena-test/infra/"
rsync -az --chmod=F600 -e "ssh -i $KEY" "$ENV_FILE" "$HOST:~/truearena-test/infra/.env"
"${SSH[@]}" 'mkdir -p ~/truearena-test/backend/ta-app/target'
rsync -az -e "ssh -i $KEY" backend/ta-app/target/truearena-backend.jar "$HOST:~/truearena-test/backend/ta-app/target/"

echo "==> packaging truearena-backend:test (no Maven compilation on the VPS)"
revision=$(git rev-parse HEAD)
"${SSH[@]}" "cd ~/truearena-test/backend && docker build -q --label org.opencontainers.image.revision=$revision -f Dockerfile.runtime -t truearena-backend:test ."

if $reset; then
  echo "==> wiping test data (truearena-test volumes only)"
  "${SSH[@]}" "cd ~/truearena-test/infra && $COMPOSE down -v"
fi

echo "==> starting the test stack"
"${SSH[@]}" "cd ~/truearena-test/infra && $COMPOSE up -d --wait --wait-timeout 180"

echo "==> ensuring test-only proxy routes and voice ports"
bash infra/setup-test-proxy.sh

echo "==> waiting for $PUBLIC/actuator/health"
for _ in $(seq 1 60); do
  if curl -fsS "$PUBLIC/actuator/health" 2>/dev/null | grep -q '"status":"UP"'; then
    echo "TEST OK — $PUBLIC"
    exit 0
  fi
  sleep 3
done
echo "test backend did not come up; logs:" >&2
"${SSH[@]}" "cd ~/truearena-test/infra && $COMPOSE logs --tail=80 test-backend" >&2
exit 1
