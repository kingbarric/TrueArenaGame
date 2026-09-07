# Contract — single source of truth for the WS wire format

`envelope.schema.json` defines the envelope every WebSocket frame uses, both
directions (Architecture §3.2). `testdata/` holds golden frames used by round-trip
tests on both sides.

## Codegen (Phase 0.5 — partial)

Target: one schema → Java records in `ta-ws` and Dart classes in `app/lib/core/contract/`.

Current state:
- Schema + golden vectors: **done**.
- Java baseline types: hand-authored in `ta-ws` (`app.truearena.ws.contract`), kept in
  sync manually until the generator lands. `EnvelopeRoundTripTest` decodes every file
  in `testdata/` and re-encodes it.
- Dart baseline types: `app/lib/core/contract/envelope.dart`, with a matching test.
- `tools/check_contract.sh` validates every `testdata/*.json` against the schema
  (uses `python -m jsonschema` when available; otherwise a structural fallback).

TODO (tracked in PROJECT_PLAN.md 0.5): replace the hand-authored types with a
`generate-sources` step in `ta-ws` + a Dart `tool/gen_contract.dart`, and make
`contract-codegen-check` fail on drift.
