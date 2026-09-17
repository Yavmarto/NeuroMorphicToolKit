---
name: nmtk-coding-guidelines
description: Coding style, module routing, and boundary rules for NeuroMorphicToolKit. Use this skill before writing any code in this repo. Covers which AGENTS.md to read per module, cross-repo contract discipline, launcher integrity requirements, and validation steps. Trigger whenever editing any file in the monorepo.
allowed-tools: Read Bash
---

# NeuroMorphicToolKit Coding Guidelines

## Before Editing Any File

1. Read `CODING_STYLE_GUIDE.md` at the repo root.
2. Identify the top-level module you're editing and read its `AGENTS.md`:

| Module path | Read before editing |
|-------------|-------------------|
| `neurocnl/**` | `neurocnl/AGENTS.md` |
| `Neurosim/**` | `Neurosim/AGENTS.md` |
| `Neurochip/**` | `Neurochip/AGENTS.md` |
| `Neurobench/**` | `Neurobench/AGENTS.md` |
| `Neuro-Dream-Hand/**` | `Neuro-Dream-Hand/AGENTS.md` |
| `Neurosense/**` | `Neurosense/AGENTS.md` |
| `Neurohub/**` | `Neurohub/AGENTS.md` |
| `nmtk/**` | `nmtk/AGENTS.md` |
| `nmtk_ui_core/**` | `nmtk_ui_core/AGENTS.md` |
| `neurocli/**` | `neurocli/AGENTS.md` |
| `docs/**`, `scripts/**`, `tests/**`, `monitoring/**`, root config | Root `AGENTS.md` + the AGENTS.md of every module whose contract you touch |

3. Default to one writable top-level module per task. If a change crosses a contract boundary, read both modules' `AGENTS.md` and both sides' spec or ADR docs first.

---

## Module Boundaries

- Each top-level module is an owned boundary. Do not change a contract, manifest, export payload, or public route shape in one module without reading the consumer/producer module and updating both test surfaces.
- Keep module metadata synchronized across `nmtk/neuro_toolkit/assets/modules.json`, launcher Dart models, root compose files, and CI/helper scripts. Never change only one copy of a module id, port, install path, or uvicorn target.
- If `nmtk/neuro_toolkit/assets/modules.json` changes, update the launcher Dart models, launcher tests, and any consuming helper scripts in the same change.
- Root `scripts/` are orchestration wrappers. Product logic belongs in the owning module package — not in ad-hoc root scripts.

---

## Launcher & Control Plane

Applies to any change under `nmtk/**`, root launcher manifests, `scripts/**`, or root `tests/**` that affects launcher behavior, module lifecycle, or suite-visible startup semantics:

```bash
# Required check
python3 scripts/launcher_control_service.py --doctor --json

# Canonical local enforcement wrapper
bash scripts/run_launcher_guardrails.sh

# Add --with-integration when module contracts or startup behavior change
bash scripts/run_launcher_guardrails.sh --with-integration
```

- `fatalCount > 0` is a blocker. Do not proceed.
- Report outcomes explicitly as `preflight failed` or `degraded optional capability` — never collapse both into a generic startup error.
- Launcher work is not complete until launcher doctor and launcher unit coverage pass.
- Keep launcher UI state changes, module manifest changes, and launcher verification updates in the same change when they describe the same behavior.
- Do not introduce a new install or startup strategy without doctor or preflight coverage.

---

## Cross-Module Changes

When editing more than one top-level module, name the write set explicitly and run:

```bash
python3 -m pytest tests/integration/test_cross_module.py
python3 -m pytest tests/integration/test_teensy_e2e.py
```

---

## Backend Endpoint Work

Use `docs/agents/nmtk-backend-smoke.md` for guidance, then run:

```bash
python3 scripts/backend_endpoint_smoke.py
```

`nmtk/neuro_toolkit/assets/modules.json` is the source of truth for module ids, ports, run paths, and uvicorn targets. Do not maintain a separate static endpoint catalog.

---

## Optional Runtimes

MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker, and report-generation dependencies must remain optional at import and startup time. Missing dependencies must degrade capability reporting — never crash the base service unless the manifest explicitly marks them required.

---

## ADRs

Accepted ADRs are append-only decision records. Add a new ADR to supersede an old decision. Never rewrite an existing ADR in place. Do not rewrite old audits in `docs/archive/**` — add a new dated document instead.

---

## Validation Defaults

- Run the owning module's local checks from its own config first.
- Run the cross-module integration tests when a suite-visible contract or integration boundary changes.
- Operator-facing launcher diagnostics must use structured logging and machine-readable reporting, not ad-hoc `print()` output.
