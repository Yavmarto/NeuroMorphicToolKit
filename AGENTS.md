# NMTK Jules Operating Contract

This repository is the integration and control plane for the NeuroMorphicToolKit (NMTK) suite. Use it to coordinate work across the mono repo, but do not default to editing every submodule from here.

## Default Session Selection

- Use a per-repo Jules session for code changes inside a specific submodule.
- Use the root `NeuroMorphicToolKit` repo for launcher work, Docker and orchestration changes, shared docs, cross-module integration checks, and work that truly spans multiple repos.
- Default to one writable repo per Jules session. Multi-repo edits are allowed only when the task explicitly requires coordinated changes across repos.

## Routing Table

| Task area | Start Jules in | Typical writable paths | Read first |
| --- | --- | --- | --- |
| NeuroCNL parser, generation, backend support, deploy handoff logic | `neurocnl` | `neurocnl/**` | `neurocnl/docs/ADR-Gemini/`, `neurocnl/docs/ADR-Codex/`, `neurocnl/docs/ADR-claude/`, `neurocnl/docs/support_matrix.md`, `neurocnl/docs/PRE_BETA_READINESS_REVIEW.md` |
| Neurosim graph builders, simulation bridges, canvas flows | `Neurosim` | `Neurosim/**` | `Neurosim/docs/ADR-Gemini/`, `Neurosim/docs/ADR-Codex/`, `Neurosim/docs/ADR-claude/`, `Neurosim/neurosim_spec.md` |
| Neurochip deployment endpoints, firmware/export flows, serial wrappers | `Neurochip` | `Neurochip/**` | `Neurochip/docs/ADR-Gemini/`, `Neurochip/docs/ADR-Codex/`, `Neurochip/docs/ADR-claude/`, `Neurochip/neurochip_spec.md` |
| Neurobench benchmark execution and benchmarking contracts | `Neurobench` | `Neurobench/**` | `Neurobench/docs/ADR-Gemini/`, `Neurobench/docs/ADR-Codex/`, `Neurobench/docs/ADR-claude/`, `Neurobench/neurobench_spec.md` |
| Neuro-Dream-Hand SNN controller, MuJoCo, prosthetic and HITL flows | `Neuro-Dream-Hand` | `Neuro-Dream-Hand/**` | `Neuro-Dream-Hand/docs/ADR-Gemini/`, `Neuro-Dream-Hand/docs/ADR-Codex/`, `Neuro-Dream-Hand/docs/ADR-claude/`, `Neuro-Dream-Hand/SPEC.md` |
| Neurosense acquisition, encoding, streaming, device workflows | `Neurosense` | `Neurosense/**` | `Neurosense/docs/ADR-Gemini/`, `Neurosense/docs/ADR-Codex/`, `Neurosense/docs/ADR-claude/`, `Neurosense/neurosense_spec.md` |
| Neurohub registry, metadata orchestration, project/workflow APIs | `Neurohub` | `Neurohub/**` | `Neurohub/docs/ADR-Gemini/`, `Neurohub/docs/ADR-Codex/`, `Neurohub/docs/ADR-claude/`, `Neurohub/neurohub_spec.md` |
| Launcher, Flutter shell, docker-compose, shared docs, integration tests, scripts | `NeuroMorphicToolKit` | `nmtk/**`, `nmtk_ui_core/**`, `neurocli/**`, `docs/**`, `scripts/**`, `tests/**`, root config files | `README.md`, `SETUP_GUIDE.md`, `docs/`, and the owning submodule docs for every contract touched |

## Cross-Repo Read Policy

When a task crosses repository boundaries, Jules must inspect the relevant peer repo before editing:

- Read the owning repo's ADRs and spec first.
- Read the peer repo contracts, schemas, router surface, or API docs that consume or produce the changed data.
- For fidelity-sensitive handoff paths, respect the documented boundary between `faithful`, `approximate`, and `unsupported` behavior.
- Do not infer cross-repo behavior from memory when the target contract can be inspected locally.

Typical cross-repo reads:

- `neurocnl` changes that affect simulation or generated graphs must read `Neurosim`.
- `neurocnl` or `Neurochip` changes that affect deploy payloads must read both sides before editing.
- `Neurosense` changes that affect encoded outputs consumed elsewhere must read the downstream consumer contracts.
- `Neurobench` or `Neurohub` changes that reference suite-wide artefacts must read the relevant producer repo contracts first.
- `Neuro-Dream-Hand` handoff work that depends on NeuroCNL or Neurochip must inspect those repos before changing the local boundary.

## Cross-Repo Write Policy

- One repo per Jules session is the default.
- Use the root repo as the writable target only for integration-control-plane work or for documentation that spans the suite.
- If a task truly needs edits in multiple repos, make that explicit in the prompt and keep the write set minimal and named.
- Do not hide cross-repo decisions inside a single-repo task. If a second repo must change, say so in the task statement.

## Verification Matrix

Run the owning repo's local checks first. Run the root integration tests whenever a change affects a contract or behavior consumed by another module.

| Writable repo | Local verification | Also run root integration tests when |
| --- | --- | --- |
| `neurocnl` | `cd neurocnl && PYTHONPATH=. pytest neurocnl/tests/`<br>`cd neurocnl && ruff check .`<br>`cd neurocnl && mypy .` | parser output, generated graphs, deploy payloads, backend support verdicts, or shared CNL behavior changes |
| `Neurosim` | `cd Neurosim && PYTHONPATH=. python -m pytest neurosim/tests/`<br>`cd Neurosim && python -m mypy neurosim`<br>`cd Neurosim/frontend && flutter test` | graph import/export, preview API, project/workflow payloads, or shared design contracts change |
| `Neurochip` | `cd Neurochip/neurochip && PYTHONPATH=.. poetry run pytest tests/`<br>`cd Neurochip/neurochip && poetry run ruff check .`<br>`cd Neurochip/neurochip && poetry run mypy .` | deployment validation, export payloads, serial flash contracts, or downstream deploy handoff changes |
| `Neurobench` | `cd Neurobench/neurobench && poetry run pytest -v --cov=app tests/`<br>`cd Neurobench/neurobench && poetry run ruff check .`<br>`cd Neurobench/neurobench && poetry run mypy --strict .`<br>`cd Neurobench/frontend && flutter test` | benchmark result schemas, run endpoints, or shared asset references change |
| `Neuro-Dream-Hand` | `cd Neuro-Dream-Hand && pytest`<br>`cd Neuro-Dream-Hand && python3 -m mypy --strict neurodreamhand/core/ neurodreamhand/experiments/ neurodreamhand/hardware/ neurodreamhand/learning/ neurodreamhand/contracts/` | NeuroCNL handoff behavior, Neurochip flash/verify boundaries, or suite-visible prosthetic contracts change |
| `Neurosense` | `cd Neurosense && PYTHONPATH=neurosense pytest neurosense/tests/`<br>`cd Neurosense/frontend && flutter test` | encoded output contracts, stream payloads, preset imports, or downstream consumer behavior changes |
| `Neurohub` | `cd Neurohub && PYTHONPATH=. pytest neurohub/tests/`<br>`cd Neurohub && ruff check neurohub/`<br>`cd Neurohub && mypy neurohub/`<br>`cd Neurohub/frontend && flutter test` | orchestration contracts, project/workflow payloads, or suite-level asset metadata change |
| `NeuroMorphicToolKit` | `cd nmtk/neuro_toolkit && flutter test`<br>`python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py` | docker/service wiring, launcher routing, shared scripts/docs, or any intentional cross-module integration change |

## Root Integration Checks

These are the canonical suite-level checks. Reuse them instead of inventing a second integration repo:

- `python3 -m pytest tests/integration/test_cross_module.py`
- `python3 -m pytest tests/integration/test_teensy_e2e.py`

## Jules Bootstrap

For root or integration sessions, start from the repository root and run:

```bash
git submodule update --init --recursive && bash scripts/jules_bootstrap_workspace.sh
```

See `docs/jules/JULES_WORKSPACE_GUIDE.md` for source-repo selection, routing rules, and prompt templates.
