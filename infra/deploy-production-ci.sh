#!/usr/bin/env bash
# Send the CI-verified runtime and public config through a production-only key.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PROD_DEPLOY_HOST:?set PROD_DEPLOY_HOST}"
: "${PROD_DEPLOY_USER:?set PROD_DEPLOY_USER}"
: "${GITHUB_SHA:?set GITHUB_SHA}"
[[ ${GITHUB_REF:-} == refs/heads/release ]] || { echo 'Production requires release' >&2; exit 1; }
bundle=$(mktemp)
trap 'rm -f "$bundle"' EXIT
python3 infra/release_bundle.py pack "$PWD" "$bundle" "$GITHUB_SHA"
ssh -i "$HOME/.ssh/production_deploy" -o BatchMode=yes -o StrictHostKeyChecking=yes \
  "$PROD_DEPLOY_USER@$PROD_DEPLOY_HOST" "deploy-production $GITHUB_SHA" < "$bundle"
curl --retry 8 --retry-delay 3 --retry-all-errors -fsS \
  https://vps-8030ec94.vps.ovh.net/actuator/health | grep -q '"status":"UP"'
echo "PRODUCTION VERIFIED — $GITHUB_SHA"
