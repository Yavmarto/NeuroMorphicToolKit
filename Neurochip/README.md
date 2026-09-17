# Neurochip

`frontend/` in this module is deprecated, superseded by `nmtk/neuro_toolkit/`.

Neurochip turns a validated NIR graph into a target-specific deployment artifact and, where the hardware and its vendor SDK are present on the server, talks to the device.

## What it does today

- Consumes a target context selected in NeuroStudio and prepares a deployment payload
- Generates deployment artifacts: Python scripts, C headers, ZIP overlays, quantized bundles
- Validates a graph against a target's constraints before deployment is attempted
- Estimates power and latency analytically from hardware target profiles
- Flashes Teensy boards over a serial bridge, where a device is attached to the server
- Reports fault-injection and quantization analysis

## How the handoff works

1. **NeuroStudio** defines the model and selects the target.
2. **Neurochip** consumes that target context and prepares the artifact.
3. The user monitors progress in the Studio's `deployHardware` step.

The authoritative contract is [ADR 0021](../docs/ADR-claude/0021-studio-neurochip-handoff-contract.md).

## Where it runs

**Backend.** Analysis, deployments, estimation, export, faults, quantization, and target metadata run in-process in `suite_api` under `/api/neurochip`. Five prefixes are proxied to `neurochip-hw-worker` on port 8002 — `akida`, `hardware/lava`, `hardware/speck`, `hardware/pynq`, and `serial`. They return HTTP 503 when that worker is not running. Note that the PYNQ routes sit at `/hardware/pynq/*`, at the API root rather than under `/api/neurochip`.

**Surface.** There is no Neurochip application. Neurochip's UI is the `deployHardware` step of NeuroStudio (`nmtk/neuro_toolkit/lib/features/studio/shared/presentation/deploy_hardware_step.dart`, with the deploy workflow under `nmtk/neuro_toolkit/lib/features/studio/deployment/`), which holds the Akida, PYNQ, Lava, and SC-NeuroCore workspaces. This repository provides the FastAPI backend, hardware contracts, artifact generation, and runtime-facing diagnostics only.

See [neurocnl/README.md](../neurocnl/README.md#the-studio-pipeline) for the pipeline, and the [root README](../README.md#architecture) for the app shell.

## Limits

**The hardware worker image installs no vendor SDKs.** `workers/neurochip_hw/Dockerfile` runs `pip install /repo/Neurochip` with no extras, so the `akida` and `pynq` extras declared in that worker's `pyproject.toml` are never selected. Of the five proxied prefixes, only `serial` has its dependency (`pyserial`) present in the shipped image.

| Target | Status | Notes |
|---|---|---|
| **Teensy 4.1** | `needs hardware` | Serial-bridge flashing works with a device attached. Feedforward LIF only — no recurrent connections, no axonal delays, no learning rules. No compose file configures device passthrough, so this needs a manually configured host. |
| **PYNQ Z2** | `needs hardware` | Bitstream and overlay packaging work. The FINN compilation stage refuses to run unless `NEUROCHIP_PYNQ_FINN_COMPILE_CMD` is set, and no compose file sets it — it is a placeholder. The overlay ZIP is loaded manually. |
| **BrainChip Akida** | `needs hardware` | Routes and artifact generation exist; MetaTF, CNN2SNN, and QuantizeML are not installed. Exportability is not SDK deployability. The `akida` package does not support macOS. |
| **SynSense Speck** | `needs hardware` | Routes exist; `sinabs`/`samna` are not installed in the worker image. |
| **Intel Lava** | `not implemented` | The Lava runtime ships in the dedicated `lava-backend` worker (`Dockerfile.lava`, `python:3.10-slim`, `workers/lava_backend/requirements.txt`) because `lava-nc` only supports Python `<3.11` and cannot be a `lava` extra of this `>=3.11` project. |
| **Intel Loihi** | `not implemented` | Export script generation only; there is no Loihi runner. |

**Power and latency figures are estimates, not measurements.** They come from a static analytic model that reads a JSON target profile and assumes a fixed average spike rate. Nothing here measures a physical chip, and there is no throughput telemetry. Do not cite these numbers as hardware results.

## Develop and test

The backend is a standard FastAPI app. Run the suite from the repo root (see the [root README](../README.md#nmtk-contributors-source-build)); this module is not started on its own in the shipped stack.

> The `Makefile` in this directory is dead: line 1 includes a repo-root `common.mk` that no longer exists. See [neurocnl/README.md](../neurocnl/README.md#local-development).

## Documentation

- [ADR 0021: Studio-Neurochip handoff contract](../docs/ADR-claude/0021-studio-neurochip-handoff-contract.md)
- [PYNQ Z2 deployment guide](./docs/neurochip/pynq_z2_deployment_guide.md)
- [User guide](./docs/neurochip/user_guide.md)
- [Developer guide](./docs/neurochip/developer_guide.md)
- [Quantization guide](./docs/neurochip/quantization_guide.md)
- [API reference](./docs/neurochip/api_reference.md)
- [Hardware testing guide](./HARDWARE_TESTING.md)
- Suite-wide hardware support: [neurocnl support matrix](../neurocnl/docs/support_matrix.md)

## Future / Planned

Not implemented today.

- **Vendor SDKs in the worker image** — installing the Akida and Speck extras so those targets work out of the box.
- **A Lava-capable worker image** — needs a `python<3.11` base or an upstream fix to the `lava` pin.
- **The PYNQ FINN compilation stage** — currently a configured-only placeholder.
- **Serial device passthrough in compose** — Teensy flashing needs a hand-configured host until then.
- **Real power and throughput telemetry** to replace the analytic estimate.

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
