# Neurosense

`frontend/` in this module is deprecated, superseded by `nmtk/neuro_toolkit/`.

Neurosense captures biological and environmental signals and turns them into the spike trains neuromorphic hardware needs. It is a backend module with no user interface.

## What it does today

- **Spike encoding** — converts analog signals into rate-coded or latency-coded spike trains
- **Encoding presets** and signal-quality checks
- **NIR conversion** for encoded streams
- **Session recording and replay** — deterministic HDF5 session artifacts, when the optional hardware worker runs
- **Device streaming** from OpenBCI Cyton, Prophesee, and PYNQ edge sources, when the worker runs and the device is present

It owns the contract for reusable biosignal recordings, which `Neurobench` and `neurocnl` both consume.

## Flagship workflow: forearm EMG

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

This produces versioned HDF5 session artifacts that serve as ground truth for downstream learning and control work.

## Where it runs

**Backend.** Presets, encoding, quality, and NIR conversion run in-process in `suite_api` under `/api/neurosense`. Recording, sessions, export, devices, stream, and sense are proxied to `neurosense-hw-worker` on port 8004, including an authenticated WebSocket bridge. **That worker is behind the `neurosense` Docker profile and does not start by default** — a plain `docker compose up` brings up the in-process half only.

**Surface.** Neurosense has no UI. There is no Neurosense screen, shell adapter, or launcher nav entry in the NMTK app, and no standalone web application or Docker-served frontend. Its encoding and session artifacts reach users through other modules and through the API. See the [root README](../README.md#architecture) for what the app actually mounts.

## Limits

| Path | Status | Notes |
|---|---|---|
| Canonical HDF5 replay | `works` | Deterministic fixtures, covered by automated tests |
| Synthetic acquisition | `works` | Exercises the pipeline without physical hardware |
| Spike encoding and quality | `works` | In-process, no worker needed |
| OpenBCI Cyton EMG | `needs hardware` | Default hardware target; not yet physically validated. Requires the opt-in worker |
| Prophesee event vision | `needs hardware` | Router and source ship; Metavision SDK is bundled in the `neurosense-hw-worker` image (amd64 Ubuntu) |
| PYNQ edge node | `needs hardware` | Router and source ship; not hardware-validated |

## Develop and test

The core package is maintained at a zero-error mypy baseline, enforced in CI:

```bash
python3 -m mypy neurosense/
```

Run the suite itself from the repo root; see the [root README](../README.md#nmtk-contributors-source-build).

> The `Makefile` in this directory is dead: line 1 includes a repo-root `common.mk` that no longer exists, and its help text still advertises `frontend` targets for a directory that was removed. See [neurocnl/README.md](../neurocnl/README.md#local-development).

## Documentation

- [Flagship workflow](docs/flagship_workflow.md)
- [Session artifact contract](docs/session_artifact_contract.md)
- [Cyton acceptance runbook](docs/cyton_acceptance_runbook.md)
- [Integration guide](docs/integration_guide_neurosense_to_toolkit.md)
- [Hardware testing](docs/hardware_testing.md)

## Future / Planned

Not implemented today.

- **Any Neurosense UI.** There is no screen, adapter, or nav entry; a Flutter frontend previously existed here and was removed.
- **Physical validation of the OpenBCI Cyton path.**

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
