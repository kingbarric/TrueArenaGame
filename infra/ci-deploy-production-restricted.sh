#!/usr/bin/env bash
# Server entry point pinned to a restricted SSH key. Install by an administrator.
set -euo pipefail
[[ ${SSH_ORIGINAL_COMMAND:-} =~ ^deploy-production\ ([0-9a-f]{40})$ ]] || {
  echo 'Only deploy-production <commit> is permitted' >&2; exit 1;
}
revision=${BASH_REMATCH[1]}
root=/home/ubuntu/truearena
cd "$root"
umask 077
exec 9>production-deploy.lock
flock -w 300 9
test -s infra/.env
context=$(mktemp -d "$root/production-runtime.XXXXXX")
trap 'rm -rf "$context"' EXIT
head -c 268435457 > "$context/bundle.tar.gz"
[[ $(wc -c < "$context/bundle.tar.gz") -le 268435456 ]] || { echo 'Oversized release' >&2; exit 1; }
python3 infra/release_bundle.py unpack "$context/bundle.tar.gz" "$context/release" "$revision"
release="$context/release"
mkdir -p "$context/image/ta-app/target"
cp "$release/backend.jar" "$context/image/ta-app/target/truearena-backend.jar"
cp "$release/Dockerfile.runtime" "$context/image/Dockerfile"
image="truearena-backend:release-$revision"
docker build -q --label "org.opencontainers.image.revision=$revision" -t "$image" "$context/image"
backup="$root/backups/production-$(date -u +%Y%m%dT%H%M%SZ)-${revision:0:12}"
mkdir -p "$backup/files"
cp infra/.env "$backup/environment"
docker inspect --format '{{.Image}}' truearena-prod-backend-1 > "$backup/image"
docker exec truearena-prod-postgres-1 pg_dump -U truearena -d truearena -Fc > "$backup/database.dump"
test -s "$backup/database.dump"
# Snapshot only public files this release will replace; credentials stay in place.
python3 - "$root" "$release" "$backup" <<'PY'
import pathlib,sys,json,shutil
root,release,backup=map(pathlib.Path,sys.argv[1:])
files=[p.relative_to(release) for folder in ['infra','website'] for p in (release/folder).rglob('*') if p.is_file()]
missing=[]
for name in files:
 target=root/name
 if target.exists():
  dest=backup/'files'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(target,dest)
 else: missing.append(str(name))
(backup/'missing.json').write_text(json.dumps(missing))
PY
rollback() {
  echo 'Production deployment failed; restoring the previous runtime and public configuration' >&2
  python3 - "$root" "$backup" <<'PY'
import pathlib,sys,json,shutil
root,backup=map(pathlib.Path,sys.argv[1:])
for p in (backup/'files').rglob('*'):
 if p.is_file(): shutil.copy2(p,root/p.relative_to(backup/'files'))
for name in json.loads((backup/'missing.json').read_text()): (root/name).unlink(missing_ok=True)
shutil.copy2(backup/'environment',root/'infra/.env')
PY
  previous=$(cat "$backup/image")
  printf 'services:\n  backend:\n    image: %s\n    environment:\n      SPRING_FLYWAY_ENABLED: "false"\n' "$previous" > "$context/rollback.yml"
  docker compose --env-file infra/.env -f infra/docker-compose.prod.yml -f "$context/rollback.yml" up -d --no-deps --wait --wait-timeout 180 backend || true
  docker exec truearena-prod-caddy-1 caddy reload --config /etc/caddy/Caddyfile || true
  echo "Database snapshot retained at $backup; no automatic database restore was performed" >&2
}
trap 'rollback; exit 1' ERR
python3 - "$root" "$release" "$image" <<'PY'
import pathlib,sys,shutil
root,release=map(pathlib.Path,sys.argv[1:3]);image=sys.argv[3]
for folder in ['infra','website']:
 for p in (release/folder).rglob('*'):
  if p.is_file():
   target=root/p.relative_to(release);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target);target.chmod(0o644)
env=root/'infra/.env';lines=[x for x in env.read_text().splitlines() if not x.startswith('BACKEND_IMAGE=')]
lines.append('BACKEND_IMAGE='+image);env.write_text('\n'.join(lines)+'\n');env.chmod(0o600)
PY
docker compose --env-file infra/.env -f infra/docker-compose.prod.yml config --quiet
docker compose --env-file infra/.env -f infra/docker-compose.prod.yml up -d --no-deps --wait --wait-timeout 180 backend
docker exec truearena-prod-caddy-1 caddy validate --config /etc/caddy/Caddyfile
docker exec truearena-prod-caddy-1 caddy reload --config /etc/caddy/Caddyfile
bash infra/smoke.sh http://localhost:8080 infra/docker-compose.prod.yml
actual=$(docker inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' truearena-prod-backend-1)
[[ "$actual" == "$revision" ]]
printf '%s\n' "$revision" > production-revision
trap - ERR
echo "PRODUCTION DEPLOYED — $revision; rollback snapshot: $backup"
