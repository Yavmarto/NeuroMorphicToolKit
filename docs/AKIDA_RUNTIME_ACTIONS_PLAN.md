# Akida Runtime Actions Plan

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
   - Calls the existing Akida inference endpoint.
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

- Add `POST /api/neurochip/akida/map`.
- Move or reuse the side-effectful mapping behavior from `/verify`.
- Keep `/verify` as a read/diagnostic contract or make it call the new mapping
  service explicitly.
- Return the same `AkidaRuntimeStatusContract` shape so frontend models remain
  simple.

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

## Testing Plan

Backend tests:

- Scaffold generation does not require SDK mapping.
- Mapping returns `runtime_target: hardware` when a physical device is selected.
- Mapping returns simulator/fallback states truthfully.
- Inference fails before mapping.
- Inference succeeds after mapping and returns outputs plus telemetry.

Frontend tests:

- **Run** is disabled before mapping.
- **Map to Runtime** records SDK status and runtime target.
- **Run** sends the configured input vector and renders the result.
- Success labels distinguish hardware, simulator, and degraded optional
  capability.

Launcher/control-plane tests:

- If Akida map/run routes through launcher host records, add proxy endpoint tests
  parallel to PYNQ run.
- Launcher terminal output should report the high-level action and final runtime
  target without leaking credentials.

## Recommendation

Implement **Package + Map to Runtime + Run Inference** first. Defer **Train**
until the training contract is explicit. This gives Akida useful parity with
PYNQ's runtime loop while avoiding the misleading implication that scaffold
generation is hardware deployment.
