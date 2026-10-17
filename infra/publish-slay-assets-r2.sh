#!/usr/bin/env bash
# Uploads SlayHuud's built art (website/slay-assets, from `npm run build` in
# slay-renderer) to Cloudflare R2, bucket playhuud-assets, under slay/.
#
#   infra/publish-slay-assets-r2.sh            upload new files only
#   infra/publish-slay-assets-r2.sh --dry-run  list what would be uploaded
#
# File names carry a content hash, so a name never changes meaning: files are
# cached for a year as immutable, and existing ones are never overwritten or
# deleted (older app builds may still ask for them).
#
# Credentials come from infra/keys/cloudflare-r2.env.local (git-ignored).
set -euo pipefail

cd "$(dirname "$0")/.."
KEYS=infra/keys/cloudflare-r2.env.local
SRC=website/slay-assets
BUCKET=playhuud-assets
PREFIX=slay

[ -f "$KEYS" ] || { echo "missing $KEYS" >&2; exit 1; }
[ -d "$SRC" ] || { echo "missing $SRC — run npm run build in slay-renderer first" >&2; exit 1; }
set -a; . "$KEYS"; set +a
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" AWS_DEFAULT_REGION=auto

dry=()
[ "${1:-}" = "--dry-run" ] && dry=(--dryrun)

# --size-only: a hashed name with the same size is the same file; never re-upload it.
# GLB isn't in most MIME tables, so it goes up on its own with its type set.
common=(--endpoint-url "$R2_ENDPOINT" --size-only --no-progress
        --cache-control "public, max-age=31536000, immutable")
aws s3 sync "$SRC" "s3://$BUCKET/$PREFIX/" "${common[@]}" ${dry[@]+"${dry[@]}"} \
    --exclude "*" --include "*.glb" --content-type model/gltf-binary
aws s3 sync "$SRC" "s3://$BUCKET/$PREFIX/" "${common[@]}" ${dry[@]+"${dry[@]}"} \
    --exclude "*.glb"

echo "slay art in s3://$BUCKET/$PREFIX/ — $(ls "$SRC" | wc -l | tr -d ' ') files locally"
