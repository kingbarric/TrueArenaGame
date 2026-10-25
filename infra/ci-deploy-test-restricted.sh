#!/usr/bin/env bash
# Install once on the VPS, then pin in authorized_keys with restrict,command.
# Accepts one runtime jar on stdin. No arbitrary shell, forwarding, file transfer,
# proxy/firewall edits, secret replacement, or production deployment.
set -euo pipefail
[[ "${SSH_ORIGINAL_COMMAND:-}" =~ ^deploy-test\ ([0-9a-f]{40})$ ]] || {
  echo 'Only deploy-test <commit> is permitted' >&2; exit 1;
}
revision="${BASH_REMATCH[1]}"
cd /home/ubuntu/truearena-test
exec 9>ci-deploy.lock
flock -w 300 9
test -s infra/.env
context=$(mktemp -d /home/ubuntu/truearena-test/ci-runtime.XXXXXX)
trap 'rm -rf "$context"' EXIT
mkdir -p "$context/ta-app/target"
jar="$context/ta-app/target/truearena-backend.jar"
head -c 536870913 > "$jar"
[[ -s "$jar" && $(wc -c < "$jar") -le 536870912 ]] || {
  echo 'Invalid artifact size' >&2; exit 1;
}
python3 - "$jar" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert 'META-INF/MANIFEST.MF' in archive.namelist(), 'Not a runtime jar'
    assert archive.testzip() is None, 'Corrupt runtime jar'
PY
cp backend/Dockerfile.runtime "$context/Dockerfile"
cp -R backend/stockfish "$context/stockfish"
cp -R backend/scan "$context/scan"
docker build -q --label "org.opencontainers.image.revision=$revision" -t truearena-backend:test "$context"
cd infra
docker compose -f docker-compose.test.yml --env-file .env up -d --wait --wait-timeout 180
docker inspect truearena-test-test-backend-1 --format '{{.Config.Image}} {{index .Config.Labels "org.opencontainers.image.revision"}}'
echo "TEST DEPLOYED — $revision"
