# Neurohub

`frontend/` in this module is deprecated, superseded by `nmtk/neuro_toolkit/`.

Neurohub is the registry and metadata layer for neuromorphic artifacts: it tracks what exists and where it came from, while other modules handle execution.

## What it does today

Neurohub is a **metadata fabric**, not a runtime control plane. It stores and versions:

- **Models** — trained weights and architectural definitions
- **Specs** — validated Controlled Natural Language templates
- **Datasets** — HDF5 sensory recordings from `Neurosense`
- **Baselines** — validated benchmark results from `Neurobench`

It also holds curated hardware profiles and encoding presets, and tracks cross-module references and workflow history without interfering with execution.

## Where it runs

**Backend.** Fully in-process in `suite_api`; there is no Neurohub worker or container. Routes are mounted under two prefixes:

- `/api/neurohub` — module routes
- `/api/v1` — **the registry itself**, which is Neurohub's headline feature. `neurocli`'s `neuro hub login|push|pull|search` talks to `/api/v1`.

**Surface.** A modal inside NeuroStudio (`nmtk/neuro_toolkit/lib/features/neurocnl/screens/hub_popup.dart`, backed by `nmtk/neuro_toolkit/lib/features/neurocnl/screens/hub/`), opened from the Studio's Setup and Review steps. There is no standalone Neurohub screen, and no launcher nav entry.

This module has no application of its own — see [neurocnl/README.md](../neurocnl/README.md#the-studio-pipeline). For the app shell itself, see the [root README](../README.md#architecture).

## Relationship to NMTK

- **nmtk** owns launcher behaviour, installation state, and runtime health.
- **Neurohub** owns the *content* and *metadata* of the artifacts being managed.

This split is specified in [ADR 0023](../docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md).

## Documentation

- [Neurohub specification](neurohub_spec.md)
- [User guide](docs/neurohub/user_guide.md)
- [Developer guide](docs/neurohub/developer_guide.md)
- [ADR 0023: NMTK sole control plane](../docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md)

## Future / Planned

Not implemented today.

- **A hosted, public community registry.** The registry runs locally inside whatever `suite_api` instance you point at; there is no shared public instance to publish to or discover from.

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
