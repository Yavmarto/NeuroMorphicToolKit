# Akida Runtime Actions Plan

## Progress Update

Updated May 7, 2026.

Completed in this slice:

- Added `POST /api/neurochip/akida/map` in Neurochip as an explicit runtime
  mapping action.
- Kept the response shape aligned with `AkidaRuntimeStatusContract` so existing
  frontend/runtime status models can consume the new action without a contract
  fork.
- Refactored the router so `/map` and `/verify` share the same model
  construction and mapping status path.
- Added backend router tests for successful explicit mapping and structured
  model-construction failure handling.
- Updated Studio so package generation and runtime mapping are separate user
  actions instead of one deploy-plus-verify bundle.
- Wired Studio's mapping action to call the explicit `/api/neurochip/akida/map`
  route.
- Updated Studio copy from generic deploy/verification wording to
  `Generate Package`, `Map Runtime`, and runtime-target-specific mapping
  outcomes.
- Added frontend tests for package-only behavior, explicit mapping behavior, and
  the new target-registry map request.
- Added Studio run-inference controls with a default input vector seeded from
  the first mapped population.
- Wired Studio inference runs to `/api/neurochip/akida/inference` and surfaced
  outputs, telemetry, and runtime target in the deploy workspace.
- Added frontend tests for explicit Akida inference requests and provider run
  behavior after mapping.
- Added launcher host proxy actions for Akida runtime mapping and inference:
  `POST /api/launcher/akida/hosts/{id}/map` and
  `POST /api/launcher/akida/hosts/{id}/run`.
- Wired selected-host Studio Akida flows to call launcher-managed host routes
  for map and run instead of talking directly to the remote Neurochip runtime.
- Added launcher proxy tests for Akida map/run payload forwarding and runtime
  target passthrough.
- Added Studio target-registry tests for launcher-backed Akida map/run calls.

Still pending:

- Remove the last product and test assumptions that treat `/verify` as the
  primary Akida mapping action.
- Lock the long-term contract boundary for remote-host package generation and
  document the chosen behavior explicitly.
- Add follow-on launcher integration and end-to-end coverage once the broader
  launcher guardrail suite is back to green.

## Decisions Locked By This Plan

1. `/verify` should remain temporarily backward-compatible but should no longer
   be the canonical mapping action.
   - Canonical write path: `POST /api/neurochip/akida/map`
   - Compatibility path: `POST /api/neurochip/akida/verify` may still accept a
     body during the migration window.
   - Long-term target: `/verify` becomes a pure diagnostic/status-style
     contract and any side effect is removed after Studio, launcher, and tests
     stop depending on request-body mapping.

2. Remote-host package generation should remain a direct runtime download path
   for the next slice.
   - Reason: package generation returns a ZIP artifact, while launcher host
     records currently add the most value for stateful runtime actions such as
     host readiness, mapping, and run logging.
   - This keeps the launcher focused on control-plane orchestration instead of
     becoming a binary download proxy prematurely.
   - Revisit only if operators need launcher-audited package downloads,
     centralized credentials, or remote artifact persistence.

3. Launcher-backed map and run are the required control-plane boundary for a
   selected remote Akida host.
   - When a host is selected, success/failure messaging, host readiness state,
     and terminal logging should come from launcher-managed actions.
   - Direct runtime calls remain valid only for local or non-launcher Akida
     flows.

## Context

The PYNQ workflow has a real runtime **Run** action. In Studio, it sends
`input_spikes` and `timesteps` through the launcher to the paired board:

```text
neurocnl frontend
  -> /api/launcher/pynq/boards/{id}/run
  -> /hardware/pynq/run
```

That call requires the PYNQ overlay to already be deployed and configured. The
backend then runs the payload through DMA or the simulator and returns
`output_spikes`, `timesteps`, and `execution_time_us`.

The current Akida workflow is different. The visible deploy path mostly
generates a scaffold package, while runtime verification performs the actual
SDK model construction and mapping check. This makes the UI feel like it is
deploying to hardware even when the backend is only creating a ZIP or mapping a
small model quickly.

## Recommended Akida Mental Model

Akida should use explicit runtime actions instead of borrowing PYNQ labels too
literally:

- **Package**: Generate the scaffold ZIP offline. This does not prove hardware
  execution.
- **Map / Load**: Construct the Akida SDK model and map it to the selected
  runtime target, either physical hardware or simulator.
- **Run**: Send an input vector to the mapped runtime and display outputs plus
  telemetry.
- **Train**: Defer until there is a concrete training contract. Training may be
  offline, dataset-backed, Neurobench-backed, or SDK-specific; it should not be
  added as a fake action.

Avoid a literal **Flash** button for Akida unless the runtime gains a durable
artifact installation step equivalent to flashing a board. For the current
architecture, **Map to Hardware** or **Load Runtime** is more truthful.

## Proposed Product Flow

1. **Generate Package**
   - Calls the existing scaffold package path.
   - UI copy should make clear that this is offline package generation.
   - The result should show ZIP size, target Akida version, topology summary,
     and whether SDK mapping has also been performed.

2. **Map to Runtime**
   - Calls an explicit mapping action instead of hiding mapping inside
     verification.
   - Returns `sdk_status`, `runtime_target`, `device_info`, `state`, and
     `environment_checks`.
   - Distinguishes physical hardware from `akd1000_simulator` and
     `software_fallback`.

3. **Run Inference**
   - Enabled only after mapping succeeds.
   - Accepts a numeric input vector sized from the first mapped population, with
     a safe default such as `[1, 0, 0, ...]`.
   - Calls the existing Akida inference endpoint directly for local flows and
     through launcher host routes for selected remote Akida hosts.
   - Displays outputs, telemetry, execution time when available, and the runtime
     target used for the run.

4. **Benchmark**
   - Keep as a separate optional workflow.
   - It should be gated on successful mapping or simulator availability,
     depending on benchmark mode.

5. **Train**
   - Keep out of the first implementation.
   - Define the training source first: dataset upload, synthetic CNL-generated
     data, Neurobench task, imported model, or Akida SDK workflow.

## Backend Shape

The backend already has most of the primitives:

- `POST /api/neurochip/akida/deploy/mapped` generates scaffold packages.
- `POST /api/neurochip/akida/verify` currently constructs and maps a model as a
  side effect.
- `POST /api/neurochip/akida/inference` runs inference on the mapped model.
- `GET /api/neurochip/akida/status` reports runtime state and SDK diagnostics.

Recommended backend change:

- Add `POST /api/neurochip/akida/map`. Completed in Neurochip backend.
- Move or reuse the side-effectful mapping behavior from `/verify`.
- Keep `/verify` as a read/diagnostic contract or make it call the new mapping
  service explicitly.
- Return the same `AkidaRuntimeStatusContract` shape so frontend models remain
  simple.
- Add launcher control-plane proxy routes for remote-host `map` and `run`.
  Completed in launcher backend.

Recommended backend follow-on:

- Mark `/map` as the primary action in router docstrings, OpenAPI-facing docs,
  and any helper scripts or examples that still lead operators toward
  side-effectful `/verify`.
- Keep `/verify` body support only as a compatibility bridge until the last
  caller migrates.
- Once all callers migrate, split `/verify` into one of these truthful shapes:
  - `GET /api/neurochip/akida/status` for current backend state.
  - `POST /api/neurochip/akida/verify` only if a future diagnostic workflow
    needs explicit stimulus-based validation that is distinct from mapping.
- Preserve `AkidaRuntimeStatusContract` as the shared status payload for
  `status`, `map`, and any compatibility `verify` response during the
  migration.

## Frontend Shape

Studio should mirror the PYNQ separation but use Akida-specific language:

- Add provider state for mapped runtime status and run result.
- Add input-vector controls for run inference.
- Disable **Run** until mapping succeeds.
- Show `runtime_target` everywhere success is claimed.
- Replace generic success messages like "Akida deploy completed" with specific
  messages:
  - "Package generated."
  - "Mapped to physical Akida hardware."
  - "Mapped to AKD1000 simulator."
  - "Run completed on physical Akida hardware."
- When a paired Akida host is selected, Studio should drive map/run via launcher
  host records so host identity, readiness, and runtime logging stay under the
  same control plane.
- Package-generation copy should stay explicit that the action creates a ZIP
  artifact and does not prove runtime availability.

Recommended frontend follow-on:

- Remove leftover "verify to map" language from provider state names, helper
  methods, button text, and test descriptions where it now obscures the
  Package -> Map -> Run mental model.
- Keep the current direct package download path for remote-host selections, but
  label the result as an artifact export rather than a launcher-managed deploy.
- Surface `runtime_target` and selected-host identity together in the run
  result panel so operators can tell whether execution happened on physical
  hardware, simulator, or fallback.

## Testing Plan

Backend tests:

- Scaffold generation does not require SDK mapping.
- Mapping returns `runtime_target: hardware` when a physical device is selected.
- Mapping returns simulator/fallback states truthfully.
- Inference fails before mapping.
- Inference succeeds after mapping and returns outputs plus telemetry.

Backend test progress:

- Added router coverage for `POST /api/neurochip/akida/map` success and
  model-construction failure handling.
- Existing Akida router/backend/contract tests still pass after the new route
  was introduced.

Frontend tests:

- **Run** is disabled before mapping.
- **Map to Runtime** records SDK status and runtime target.
- **Run** sends the configured input vector and renders the result.
- Success labels distinguish hardware, simulator, and degraded optional
  capability.

Launcher/control-plane tests:

- If Akida map/run routes through launcher host records, add proxy endpoint tests
  parallel to PYNQ run. Completed for launcher state proxy methods and Studio
  launcher request wiring.
- Launcher terminal output should report the high-level action and final runtime
  target without leaking credentials.

## Remaining Execution Slices

### Slice 1: Contract Cleanup

- Update remaining docs, helper comments, and tests to treat `/map` as the
  primary runtime action.
- Keep `/verify` request-body support only where compatibility is still needed.
- Add an explicit deprecation note in the Akida router and any user-facing docs
  that still mention verification-driven mapping.

### Slice 2: Studio Messaging and State Polish

- Rename or normalize any remaining provider/service terminology that implies
  "verification" when the user is actually mapping.
- Ensure all success, warning, and error states distinguish:
  - offline package generation
  - successful runtime mapping
  - successful inference run
  - degraded optional capability versus preflight failure
- Confirm remote-host flows show launcher ownership of map/run actions while
  package generation remains an artifact export.

### Slice 3: Launcher and Cross-Module Verification

- Add or restore launcher guardrail coverage for Akida host map/run flows once
  the broader suite is green enough for stable enforcement.
- Run backend endpoint smoke checks against the changed routes and confirm
  OpenAPI exposes the canonical mapping action correctly.
- Run cross-module integration coverage for the Studio -> launcher ->
  Neurochip Akida path if any contract shape changes in the cleanup slice.

### Slice 4: Operator Docs

- Document the final Akida operator story in one place:
  - generate package for offline artifact export
  - map runtime to hardware or simulator
  - run inference against the mapped runtime
  - understand when launcher participates and when it does not
- Record the `/verify` compatibility window and the future intention to make it
  diagnostic-only.

## Exit Criteria

This plan is complete when all of the following are true:

- Studio exposes Akida as `Generate Package`, `Map to Runtime`, and
  `Run Inference` without fallback wording that implies scaffold generation is a
  hardware deploy.
- `POST /api/neurochip/akida/map` is the documented canonical mapping action.
- Any remaining `/verify` side effect is explicitly treated as temporary
  compatibility behavior, not product intent.
- Remote-host Akida map/run actions always go through launcher host records.
- Package generation behavior for remote hosts is documented as a direct
  runtime artifact export, not an unresolved control-plane decision.
- Tests cover the local path and the launcher-host path for map/run behavior.
- Required launcher verification reports `preflight failed` separately from
  `degraded optional capability`.

## Verification Checklist

- `rtk python3 scripts/backend_endpoint_smoke.py health --module neurochip`
- `rtk python3 scripts/backend_endpoint_smoke.py openapi --module neurochip`
- `rtk python3 scripts/backend_endpoint_smoke.py call --module neurochip --method POST --path /api/neurochip/akida/map --json '<mapped-network-payload>'`
- `rtk bash scripts/run_launcher_guardrails.sh`
- `rtk python3 -m pytest tests/integration/test_cross_module.py`
- `rtk python3 -m pytest tests/integration/test_teensy_e2e.py`

Use `rtk bash scripts/run_launcher_guardrails.sh --with-integration` instead of
the shorter guardrail command if the cleanup changes launcher-visible contract
behavior or suite startup semantics.

## Recommendation

Implement **Package + Map to Runtime + Run Inference** first. Defer **Train**
until the training contract is explicit. This gives Akida useful parity with
PYNQ's runtime loop while avoiding the misleading implication that scaffold
generation is hardware deployment.
