# Node Source Inspector and Reusable Custom Nodes

Status: implemented and focused verification complete.

NeuroSim's model-canvas inspector now opens Python source for built-in and
custom nodes. Built-ins generate a reusable `CustomNode` definition and can
only be saved as a new custom node, while existing custom nodes support
revision-safe in-place saves and Save As.

The shared `nmtk_sdk` contract carries stable custom IDs plus optional
`base_component_id` and `base_nir_type` delegation metadata. The backend
validates source statically, writes atomically, rejects stale revisions,
refreshes the component registry, and the Flutter palette refreshes without
requiring an app restart.

Verification completed:

- Focused Flutter API and widget tests
- Flutter analyzer
- Python Ruff formatting and linting
- Python SDK, FastAPI route, source, persistence, and runtime tests
- Cross-module integration collection (skipped because external services were absent)
- Open Brain identity and base-delegation invariant entries

Environment-level blockers observed:

- The web build is blocked by existing `nmtk_ui_core` native `dart:ffi`
  imports and unrelated native file-picker symbols.
- Launcher doctor reports a preflight failure because the Flutter cache is not
  writable and the configured suite API is unreachable.
- The running local suite API returns 404 for the smoke script's `/health`
  probe and 500 for `/openapi.json`; the in-process OpenAPI contract test passes.
- The broad Flutter suite contains unrelated baseline failures; all focused
  custom-node tests pass.
