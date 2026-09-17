# Neurosim

Neurosim is the visual graph, preview, sweep, export, and project workspace for spiking-network design. It is a surface of NeuroStudio, not a separate application.

## What it does today

- Canvas-native editing of a spiking network's topology
- Topology inspection and simulation preview
- Parameter sweeps and export-oriented refinement
- Project workspace persistence

It is **not** the canonical owner of CNL semantics (that is `neurocnl`), and **not** the owner of deployment target selection (that is the Studio's `deployHardware` step).

## Where it runs

**Backend.** Twelve routers, all in-process in `suite_api` under `/api/neurosim`. There is no Neurosim worker, container, or port of its own. The Python package lives at `neurocnl/neurosim/` — that is the only copy, and it is what executes.

**Surface.** The `defineModel` step of the Studio pipeline, plus the app's `/canvas`, `/canvas/projects`, `/canvas/sweep`, and `/canvas/export` routes — all of them routes of the *same* Flutter app. Neurosim does not appear in `nmtk/neuro_toolkit/assets/modules.json` and has no launcher entry of its own. The "handoff to NeuroSim" action re-enters the same surface with `moduleId: 'neurocnl'`.

This module has no application of its own — see [neurocnl/README.md](../neurocnl/README.md#the-studio-pipeline). For the app shell itself, see the [root README](../README.md#architecture).

## Supported simulation scope

NeuroSim's NeuroCNL-backed preview currently supports one canonical graph topology: a two-population sensory -> motor reflex arc with a single static synapse. Any other graph topology, including multiple populations, recurrent connections, or non-static synapses, is outside the active support boundary and should return a structured unsupported verdict.

Broad visual SNN simulation, arbitrary graph topologies, and hardware targets beyond explicitly implemented behavior are not active support. Historical claims in `neurosim_spec.md` about a wider standalone product shape should not be treated as current implementation truth.

> Known gap: the preview support assessment does not currently enforce the boundary described above — multi-population and recurrent graphs are reported as supported rather than rejected. Treat the paragraph above as the intended contract, not as validated behaviour.

## Workflow ownership

- Enter the canvas from the Studio for editing, topology inspection, preview, sweeps, or export refinement.
- Return to the Studio's `deployHardware` step to choose a deployment target.
- Neurochip receives the imported target context from there.

The authoritative cross-module handoff contract is [ADR 0021](../docs/ADR-claude/0021-studio-neurochip-handoff-contract.md).

## Develop and test

Neurosim's code lives in `neurocnl/neurosim/`, so develop it from the `neurocnl/` checkout:

```bash
uvicorn backend.app.main:app --reload --port 8000
```

Run that from `neurocnl/` with the repo root on `PYTHONPATH`. This directory holds the module's `pyproject.toml`, docs, and specification; it no longer contains a Python package.

> The `Makefile` in this directory is dead: line 1 includes a repo-root `common.mk` that no longer exists. See [neurocnl/README.md](../neurocnl/README.md#local-development).

## Documentation

- [Neurosim specification](neurosim_spec.md) — historical; see the scope note above
- [ADR 0021: Studio-Neurochip handoff contract](../docs/ADR-claude/0021-studio-neurochip-handoff-contract.md)

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
