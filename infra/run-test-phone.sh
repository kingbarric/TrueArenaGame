#!/usr/bin/env bash
# Keep phone builds paired with the test backend and its invitation links.
set -euo pipefail
cd "$(dirname "$0")/../app"
exec flutter run --release \
  --dart-define=API_BASE=https://vps-8030ec94.vps.ovh.net/test \
  --dart-define=INVITE_BASE_URL=https://vps-8030ec94.vps.ovh.net/test \
  "$@"
