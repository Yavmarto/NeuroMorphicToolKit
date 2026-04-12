# NeuroMorphicToolKit Coding Style Guide

This guide only covers cross-repo defaults that are not already enforced by the nearest module config. The authority order is: nearest `AGENTS.md`, then module config files such as `pyproject.toml`, `pubspec.yaml`, `analysis_options.yaml`, and `.pre-commit-config.yaml`, then this document.

## Audited module map

- `neurocnl`: Python + Dart. See `neurocnl/pyproject.toml`, `neurocnl/frontend/pubspec.yaml`, `neurocnl/frontend/analysis_options.yaml`, `neurocnl/.pre-commit-config.yaml`.
- `Neurosim`: Python + Dart. See `Neurosim/pyproject.toml`, `Neurosim/frontend/pubspec.yaml`, `Neurosim/frontend/analysis_options.yaml`, `Neurosim/.pre-commit-config.yaml`.
- `Neurochip`: Python + Dart. See `Neurochip/pyproject.toml`, `Neurochip/frontend/pubspec.yaml`, `Neurochip/frontend/analysis_options.yaml`.
- `Neurobench`: Python + Dart. See `Neurobench/neurobench/pyproject.toml`, `Neurobench/frontend/pubspec.yaml`, `Neurobench/frontend/analysis_options.yaml`.
- `Neuro-Dream-Hand`: Python. See `Neuro-Dream-Hand/pyproject.toml`.
- `Neurosense`: Python + Dart. See `Neurosense/pyproject.toml`, `Neurosense/frontend/pubspec.yaml`, `Neurosense/frontend/analysis_options.yaml`, `Neurosense/.pre-commit-config.yaml`.
- `Neurohub`: Python + Dart. See `Neurohub/pyproject.toml`, `Neurohub/frontend/pubspec.yaml`, `Neurohub/frontend/analysis_options.yaml`, `Neurohub/.pre-commit-config.yaml`.
- `nmtk`: Dart + Python helpers. See `nmtk/neuro_toolkit/pubspec.yaml`, `nmtk/neuro_toolkit/analysis_options.yaml`.
- `nmtk_ui_core`: Dart. See `nmtk_ui_core/pubspec.yaml`, `nmtk_ui_core/analysis_options.yaml`.
- `neurocli`: Markdown-only planning at present; if implementation starts, it must share launcher manifest semantics from `nmtk/neuro_toolkit/assets/modules.json`.

## Cross-repo defaults

- Treat each top-level module as an owned boundary. Do not change a contract, manifest, export payload, or public route shape in one module without reading the consumer or producer module and updating both test surfaces.
- Keep module metadata synchronized across `nmtk/neuro_toolkit/assets/modules.json`, launcher Dart models, root compose files, and CI or helper scripts. Never change only one copy of a module id, port, install path, or uvicorn target.
- Keep optional runtimes optional. Do not move MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker, or report-generation dependencies into unconditional startup paths.
- Root `tests/` exist for suite contracts and launcher-control behavior. New unit or feature tests belong in the owning module unless the behavior is intentionally cross-module.
- Root `scripts/` are orchestration wrappers. Product logic belongs in the owning module package, not in an ad-hoc root script.
- Accepted ADRs are append-only decision records. Add a new ADR to supersede an old decision instead of rewriting the old file in place.
- `docs/archive/**` is historical record. Do not rewrite old audits to match current state; add a new dated document instead.

## Validation defaults

- Run the owning module's local checks from its own config first.
- Also run `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py` when a suite-visible contract or integration boundary changes.
