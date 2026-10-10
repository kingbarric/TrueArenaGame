#!/usr/bin/env bash
# User-authorized full database snapshot. Production is read only throughout.
set -euo pipefail
cd "$(dirname "$0")/.."
ssh -i infra/keys/truearena_deploy_key -o StrictHostKeyChecking=accept-new ubuntu@51.38.71.193 'bash -s' <<'REMOTE'
set -euo pipefail
umask 077
prod_db=truearena-prod-postgres-1
test_db=truearena-test-test-postgres-1
test_backend=truearena-test-test-backend-1
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="$HOME/truearena-test/backups/$stamp"
mkdir -p "$backup_dir"
# Preserve production container identities/start times for the final comparison.
docker inspect truearena-prod-backend-1 "$prod_db" truearena-prod-redis-1 truearena-prod-livekit-1 --format '{{.Name}} {{.Id}} {{.State.StartedAt}}' > "$backup_dir/production-before.txt"
docker exec "$test_db" pg_dump -U truearena -d truearena --format=custom --no-owner --no-acl > "$backup_dir/test-before.dump"
# pg_dump uses a consistent read-only snapshot, including every schema/table.
docker exec "$prod_db" pg_dump -U truearena -d truearena --format=custom --no-owner --no-acl > "$backup_dir/production-snapshot.dump"
restore_db="mirror_$stamp"
docker exec "$test_db" createdb -U truearena "$restore_db"
if ! docker exec -i "$test_db" pg_restore -U truearena -d "$restore_db" --no-owner --no-acl --exit-on-error < "$backup_dir/production-snapshot.dump"; then
  docker exec "$test_db" dropdb -U truearena "$restore_db"
  echo 'Snapshot restore failed; original test database is still active.' >&2
  exit 1
fi
# Capture restored table counts before migrations or background jobs can change them.
docker exec "$test_db" psql -U truearena -d "$restore_db" -At -c "SELECT format('SELECT %L, count(*) FROM %I.%I;', tablename, schemaname, tablename) FROM pg_tables WHERE schemaname='public' ORDER BY tablename" > "$backup_dir/counts.sql"
docker exec -i "$test_db" psql -U truearena -d "$restore_db" -At < "$backup_dir/counts.sql" > "$backup_dir/restored-table-counts.txt"
docker stop "$test_backend" >/dev/null
# Retain the previous database as a second rollback copy, in addition to its dump.
previous_db="previous_$stamp"
docker exec "$test_db" psql -U truearena -d postgres -v ON_ERROR_STOP=1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='truearena' AND pid<>pg_backend_pid()" >/dev/null
docker exec "$test_db" psql -U truearena -d postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE truearena RENAME TO \"$previous_db\"" >/dev/null
if ! docker exec "$test_db" psql -U truearena -d postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE \"$restore_db\" RENAME TO truearena" >/dev/null; then
  docker exec "$test_db" psql -U truearena -d postgres -c "ALTER DATABASE \"$previous_db\" RENAME TO truearena"
  docker start "$test_backend" >/dev/null
  exit 1
fi
# Deliberately do not copy production Redis tokens/locks/presence or live voice.
docker exec truearena-test-test-redis-1 redis-cli FLUSHALL >/dev/null
docker inspect truearena-prod-backend-1 "$prod_db" truearena-prod-redis-1 truearena-prod-livekit-1 --format '{{.Name}} {{.Id}} {{.State.StartedAt}}' > "$backup_dir/production-after.txt"
cmp "$backup_dir/production-before.txt" "$backup_dir/production-after.txt"
printf 'DATABASE MIRRORED; backup: %s; previous test DB: %s\n' "$backup_dir" "$previous_db"
cat "$backup_dir/restored-table-counts.txt"
echo 'Test backend remains stopped. Deploy --stack-only to apply migrations and start it.'
REMOTE
