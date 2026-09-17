# ADR 0002: Pluggable Hardware Backends

## Status
Accepted

## Context
Benchmarks must run against multiple hardware targets (SpiNNaker2, SynSense/Akida, PYNQ, MuJoCo) with different APIs, capabilities, and latency characteristics. The core benchmark runner should not be tightly coupled to any single backend.

## Decision
Each hardware backend gets its own FastAPI router (`spinnaker2.py`, `synsense.py`, `pynq.py`) and the `BenchmarkRunner` dispatches to target APIs via internal HTTP calls using `httpx`. Target API URLs are configured through `settings.*_api_url` environment variables. New backends can be added by implementing a router and registering the URL.

## Consequences
- **Positive:** Adding new hardware backends requires no changes to the core benchmark runner; HTTP-based dispatch enables cross-service communication in Docker networks.
- **Negative:** HTTP round-trips add latency to each benchmark step; network failures between services can cause hard-to-diagnose benchmark failures.

## Status Update (2026-07-16 audit)

The httpx-dispatch design above was only realized for two targets. `BenchmarkRunner` (`app/services/benchmark_runner.py`, ~lines 90-130) only defines `_run_neurosim` and `_run_neurochip`, both routed through a shared `_run_hardware_target` helper that does an `httpx` POST to `settings.neurosim_api_url` / `settings.neurochip_api_url`. `app/config.py` defines exactly those two per-target URL settings and no others. SpiNNaker2, SynSense, and PYNQ do not follow this pattern: `app/routers/spinnaker2.py` imports a `spinnaker2_runner` singleton from `app/runners/spinnaker2_runner.py`, `app/routers/synsense.py` instantiates `SynSenseBenchmarkRunner()` directly, and `app/routers/pynq.py` instantiates `PYNQBenchmarkRunner()` directly — all three call into hardware SDKs in-process, with no `httpx` calls and no `settings.*_api_url` entries. There is also no MuJoCo router or runner anywhere under `neurobench/app/` despite this ADR listing MuJoCo as a required pluggable target.
