#!/usr/bin/env bash
# Validate every contract test vector against envelope.schema.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$ROOT/shared/contract/envelope.schema.json"
DATA_DIR="$ROOT/shared/contract/testdata"

if python3 -c "import jsonschema" 2>/dev/null; then
  for f in "$DATA_DIR"/*.json; do
    echo "validate $(basename "$f")"
    python3 - "$SCHEMA" "$f" <<'PY'
import json, sys
from jsonschema import validate
schema = json.load(open(sys.argv[1]))
validate(instance=json.load(open(sys.argv[2])), schema=schema)
PY
  done
  echo "contract OK (jsonschema)"
else
  echo "jsonschema not installed — running structural fallback"
  types=$(python3 -c "import json,sys; print('\n'.join(json.load(open('$SCHEMA'))['\$defs']['messageType']['enum']))")
  for f in "$DATA_DIR"/*.json; do
    python3 - "$f" "$types" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
allowed = set(sys.argv[2].split())
assert d.get("v") == 1, f"{sys.argv[1]}: v must be 1"
assert d.get("type") in allowed, f"{sys.argv[1]}: bad type {d.get('type')}"
assert isinstance(d.get("ts"), int), f"{sys.argv[1]}: ts must be int"
print(f"ok {sys.argv[1]}")
PY
  done
  echo "contract OK (fallback)"
fi
