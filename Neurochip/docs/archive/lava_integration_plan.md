# Integration Plan: Intel Lava / Loihi 2 Hardware Execution Backend

## 1. Overview
This document outlines the plan for integrating Intel Lava / Loihi 2 hardware execution into the Neurochip module.
Neurochip will interface with the Lava framework to compile, deploy, and execute SNN models.

## 2. New Service: `LavaBackend`
A new service class, `LavaBackend` (in `neurochip/app/services/lava_backend.py`), will be created to manage the Lava process lifecycle.

### Interface Design
- `compile(network: NetworkInput, run_config: str)`: Prepares the network for execution. Translates `NetworkInput` into Lava `Process` objects (e.g., `LIF`, `Dense`).
- `run(steps: int)`: Starts execution on the selected backend (sim or hw).
- `stop()`: Terminates execution and cleans up resources.
- `get_results()`: Retrieves spike data and formats it back to the Neurochip API response format.

### Graceful Degradation
The module will attempt to import Lava components (e.g. `Loihi2SimCfg`, `Loihi2HwCfg`, `Process`). If `lava-nc` is not installed, it will catch the `ImportError` and raise a structured `RuntimeError` or `HTTPException` stating that the Lava framework is not available, allowing the rest of Neurochip to function normally.

## 3. Network Instantiation
- Accept the serialized network via the API (similar to `NetworkInput`).
- Map neurons to Lava LIF processes and connections to Lava Dense processes.
- Connect the out ports of LIF to Dense, and Dense out to the next LIF process.
- Configure probes (e.g. Monitor processes) to record spikes.

## 4. Simulation vs. Hardware Runtime Selection
Lava supports multiple backends. The backend will choose the correct RunConfig based on the presence of hardware or user request:
- **Simulation**: Use `Loihi2SimCfg`.
- **Hardware**: Use `Loihi2HwCfg`.
The selection will be a parameter in the `compile()` or `run()` method, falling back to `Loihi2SimCfg` if `Loihi2HwCfg` is requested but no hardware is available or if execution fails.

## 5. Execution Lifecycle
1. **Instantiate**: Create Lava processes.
2. **Run**: Call `run(condition=RunSteps(num_steps=steps), run_cfg=Loihi2SimCfg())` (or equivalent).
3. **Read**: Retrieve monitored data from the `Monitor` process.
4. **Stop**: Call `stop()` to clean up.

## 6. Result Serialization
The spike data recorded by the Lava monitors will be converted into a standard JSON response format:
```json
{
  "spikes": {
    "neuron_id": [time_step1, time_step2]
  },
  "status": "success",
  "execution_time_ms": 123.4
}
```

## 7. New API Endpoints
A new router `neurochip/app/routers/lava.py` will be created:
- `POST /api/neurochip/hardware/lava/compile`: Accepts `NetworkInput`, prepares it, and returns a session ID.
- `POST /api/neurochip/hardware/lava/run`: Accepts session ID, run config (sim/hw), and `num_steps`. Returns execution results.

## 8. Dependency Changes
`pyproject.toml` will be updated to include `lava-nc` as an optional dependency or standard dependency depending on project conventions. For example:
```toml
[tool.poetry.dependencies]
lava-nc = {version = "*", optional = true}
```
