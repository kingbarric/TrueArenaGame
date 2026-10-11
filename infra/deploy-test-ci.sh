#!/usr/bin/env bash
# Upload only the verified jar through a forced-command, test-only SSH key.
# Server secrets, compose config and the deployment wrapper stay on the VPS.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEST_DEPLOY_HOST:?set TEST_DEPLOY_HOST}"
: "${TEST_DEPLOY_USER:?set TEST_DEPLOY_USER}"
: "${GITHUB_SHA:?set GITHUB_SHA}"
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid revision' >&2; exit 1; }
[[ "${GITHUB_REF:-}" == refs/heads/main ]] || { echo 'Test deployment requires main' >&2; exit 1; }
jar=backend/ta-app/target/truearena-backend.jar
[[ -s "$jar" ]] || { echo 'Missing verified runtime artifact' >&2; exit 1; }
ssh -i "$HOME/.ssh/test_deploy" -o BatchMode=yes -o StrictHostKeyChecking=yes "$TEST_DEPLOY_USER@$TEST_DEPLOY_HOST" "deploy-test $GITHUB_SHA" < "$jar"
for attempt in {1..30}; do
  if curl -fsS https://vps-8030ec94.vps.ovh.net/test/actuator/health | grep -q '"status":"UP"'; then
    echo "TEST OK — $GITHUB_SHA"
    exit 0
  fi
  sleep 2
done
echo 'Test health check failed' >&2
exit 1
