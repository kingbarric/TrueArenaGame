#!/usr/bin/env bash
# Add test-only routes with a validated, graceful reload of the existing proxy.
set -euo pipefail
cd "$(dirname "$0")/.."
ssh -i infra/keys/truearena_deploy_key ubuntu@51.38.71.193 bash -s <<'REMOTE'
set -euo pipefail
mkdir -p ~/truearena-test/infra
docker network inspect truearena-edge -f '{{range .Containers}}{{.Name}} {{end}}' | grep -q truearena-prod-caddy-1 \
  || docker network connect truearena-edge truearena-prod-caddy-1
python3 - <<'PY'
from pathlib import Path
source = Path.home() / 'truearena/infra/Caddyfile.prod'
candidate = Path.home() / 'truearena-test/infra/Caddyfile.test-proxy'
text = source.read_text()
for suffix, old_target, test_target in [('', 'backend:8080', 'truearena-test-backend:8080'),
                                       (':8443', 'livekit:7880', 'truearena-test-livekit:7880')]:
    if test_target in text:
        continue
    old = '{$DOMAIN}' + suffix + ' {\n\treverse_proxy ' + old_target + '\n}'
    new = ('{$DOMAIN}' + suffix + ' {\n\thandle_path /test/* {\n'
           '\t\treverse_proxy ' + test_target + '\n\t}\n\thandle {\n'
           '\t\treverse_proxy ' + old_target + '\n\t}\n}')
    if text.count(old) != 1:
        raise SystemExit('Existing proxy block differs; refusing to replace production configuration')
    text = text.replace(old, new, 1)
candidate.write_text(text)
PY
candidate="$HOME/truearena-test/infra/Caddyfile.test-proxy"
current="$HOME/truearena/infra/Caddyfile.prod"
if ! cmp -s "$candidate" "$current"; then
  docker cp "$candidate" truearena-prod-caddy-1:/tmp/truearena-test-Caddyfile
  docker exec truearena-prod-caddy-1 caddy validate --config /tmp/truearena-test-Caddyfile --adapter caddyfile
  backup="$HOME/truearena-test/infra/Caddyfile.before-test.$(date +%s)"
  cp "$current" "$backup"
  # Preserve the inode of the bind-mounted file for the running container.
  cat "$candidate" > "$current"
  if ! docker exec truearena-prod-caddy-1 caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile; then
    cat "$backup" > "$current"
    docker exec truearena-prod-caddy-1 caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
    exit 1
  fi
fi
sudo ufw allow 7891/tcp comment 'PlayHuud test voice TCP'
sudo ufw allow 50100:50120/udp comment 'PlayHuud test voice media'
REMOTE
