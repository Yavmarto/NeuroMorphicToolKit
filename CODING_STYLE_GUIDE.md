# NeuroMorphicToolKit Coding Style Guide

This guide only covers cross-repo defaults that are not already enforced by the nearest module config. The authority order is: nearest `AGENTS.md`, then module config files such as `pyproject.toml`, `pubspec.yaml`, `analysis_options.yaml`, and `.pre-commit-config.yaml`, then this document.

## Audited module map

- `neurocnl`: Python + Dart. See `neurocnl/pyproject.toml`, `neurocnl/frontend/pubspec.yaml`, `neurocnl/frontend/analysis_options.yaml`, `neurocnl/.pre-commit-config.yaml`.
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

## Flutter UI design system

### Border radius

All Flutter widgets must use one of the five sanctioned radius values from `NmtkShellTokens` and `NmtkDesignTokens`. Do not use any other radius value.

| Token | Value | Use where |
|-------|-------|-----------|
| `NmtkShellTokens.radiusSm` | 12 px | Inline chips, tags, input fields, text fields |
| `NmtkShellTokens.radiusMd` | 16 px | Buttons, small cards, search fields |
| `NmtkShellTokens.radiusLg` | 22 px | Section cards, summary tiles, large containers |
| `NmtkShellTokens.chipRadius` (999) | 999 px | Pill-shaped status badges, info chips |
| `NmtkDesignTokens.dialogShape` | 28 px | Dialogs only — matches Material 3 default |

Non-token radius values currently in production (8, 10, 14, 18) must be eliminated on sight and replaced with the nearest token from this table. `radiusMd` (16) replaces 18; `radiusSm` (12) replaces 8, 10, and 14.

### Shell mode

Each module must pass its assigned `NmtkShellMode` to `NmtkDesktopScaffold` (or `NmtkTopAppBar` when running embedded in the launcher WebView). The correct mode for each module is documented in the module's own `AGENTS.md`. The three modes and their accent palette intent:

| Mode | Accent | Intended for |
|------|--------|-------------|
| `NmtkShellMode.command` | Navy / default | Launcher, NeuroHub, NeuroBench |
| `NmtkShellMode.studio` | Violet | neurocnl (CNL Studio + NeuroStudio canvas) |
| `NmtkShellMode.instrument` | Cyan | NeuroSense, NeuroChip |

Never leave the mode at the default when the module should be in a non-command mode — the three-mode design exists specifically to give each module a distinct visual identity in the shared shell.

### Status colour semantics

Suite-wide status signals (pipeline states, health badges, run buttons, toasts) must always use the `NmtkShellTokens` semantic palette:

| Semantic | Token | Hex |
|----------|-------|-----|
| Healthy / success | `NmtkShellTokens.healthyColor` | `0xFF22C55E` |
| Error | `NmtkShellTokens.errorColor` | `0xFFEF4444` |
| Warning / degraded | `NmtkShellTokens.warningColor` / `.degradedColor` | `0xFFF59E0B` |
| Running | `NmtkShellTokens.runningColor` | `0xFF38BDF8` |
| Live / recording | `NmtkShellTokens.liveColor` | `0xFFE11D48` |

`NmtkNeurocnlTokens.success / .error / .warning` are **CNL syntax-diagnostic colours only**. Do not use them for any UI status outside the CNL editor's syntax highlighting and diagnostics layer.

## Validation defaults

- Run the owning module's local checks from its own config first.
- Also run `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py` when a suite-visible contract or integration boundary changes.

## Launcher and runtime integrity

- `AGENTS.md` defines the required workflow steps. This style guide defines the quality bar the resulting change must satisfy. For launcher and runtime work, both documents apply together.
- Environment integrity is a code-quality concern, not just an operational concern. Startup paths must fail early, actionably, and deterministically when required dependencies or manifests are invalid.
- Keep launcher runtime semantics typed and synchronized across the manifest, Dart models, launcher state, helper scripts, and verification surfaces. If a launcher field changes in one surface, update the other consumers in the same change.
- Optional runtimes must remain optional at import and startup time. Missing MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker, or report-generation dependencies must degrade capability reporting rather than crash the base service unless the manifest explicitly marks them required.
- Operator-facing launcher diagnostics should use structured logging and machine-readable reporting rather than ad-hoc `print()` output where the code path is part of the supported orchestration surface.
- Launcher and control-plane changes should include a readiness check, currently `python3 scripts/launcher_control_service.py --doctor --json`, plus launcher test coverage for new install, startup, preflight, or manifest behavior.
- Suite-visible launcher changes still require the root integration checks in addition to owning tests; launcher-only changes without contract impact can stop at launcher-local verification, but they must say that explicitly in the change summary.
