# Jules Workspace Guide for NMTK

This guide makes Jules reliable in the NMTK mono repo plus 7 submodule repos by keeping the write target explicit.

## Setup Command

For root and integration sessions, start in the `NeuroMorphicToolKit` repository root and run:

```bash
git submodule update --init --recursive && bash scripts/jules_bootstrap_workspace.sh
```

This root repo is already the integration and control plane. Do not create a second integration repo.

## Choose the Source Repo

- Choose the target repo for code edits.
- Choose the root `NeuroMorphicToolKit` repo for launcher work, shared scripts, docs, Docker and orchestration, or suite-level integration verification.
- If a task reads across repos but writes in one place, start Jules in the repo that owns the write set and explicitly name the peer repos Jules must inspect first.
- If a task truly requires edits in multiple repos, say so explicitly in the prompt and name every writable repo.

## Routing Table

| Task type | Start Jules in |
| --- | --- |
| NeuroCNL parser, generation, backend support, deploy payload logic | `neurocnl` |
| Neurosim graph building, preview, export, simulation UX | `Neurosim` |
| Neurochip target validation, export, firmware packaging, serial flows | `Neurochip` |
| Neurobench benchmark execution and reporting | `Neurobench` |
| Neuro-Dream-Hand controller, MuJoCo, HITL, prosthetic flows | `Neuro-Dream-Hand` |
| Neurosense acquisition, encoding, presets, streaming | `Neurosense` |
| Neurohub registry, metadata, project/workflow orchestration | `Neurohub` |
| Launcher, Flutter shell, docs, root scripts, docker compose, cross-module integration tests | `NeuroMorphicToolKit` |

## Read-Before-Write Rules

Before Jules edits code, it must read the owning repo's `AGENTS.md`, the relevant ADR directories, and the owning spec file. If the change affects a cross-repo contract, Jules must also inspect the peer repo that consumes or produces that contract before writing any code.

For launcher or control-plane work in the root repo, Jules must also read `CODING_STYLE_GUIDE.md` and `nmtk/AGENTS.md`, then run:

```bash
python3 scripts/launcher_control_service.py --doctor --json
python3 -m unittest tests.test_launcher_control_service
```

If launcher doctor reports `fatalCount > 0`, treat that as a blocker unless the task is explicitly to diagnose or fix that failure. Report `preflight failed` and `degraded optional capability` separately.

Examples:

- Changing a NeuroCNL deploy payload for Teensy requires reading both `neurocnl` deploy docs and the matching `Neurochip` contract or endpoint.
- Changing a Neurosense encoding output used by NeuroCNL or Neurobench requires reading the downstream contract before editing.
- Changing a Neurohub workflow or activity payload that references suite apps requires reading the relevant upstream app contract first.

## Prompt Templates

### Single-repo task

```text
Work only in the <repo-name> repository.
Before editing, read AGENTS.md plus the relevant ADR and spec files in that repo.
Do not modify any other repository.
Run the repo-local verification commands before finishing.
Task: <task details>
Success criteria: <expected behavior>
```

### Launcher / control-plane task

```text
Work only in the NeuroMorphicToolKit root repository.
Before editing, read AGENTS.md, CODING_STYLE_GUIDE.md, and nmtk/AGENTS.md plus the relevant ADRs.
Do not modify any submodule unless the task explicitly names it.
Run:
python3 scripts/launcher_control_service.py --doctor --json
python3 -m unittest tests.test_launcher_control_service
Run python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py when launcher changes affect module contracts or suite-visible startup behavior.
Report launcher doctor results explicitly as preflight failures versus degraded optional capabilities.
Task: <task details>
Success criteria: <expected behavior>
```

### Cross-repo read plus single-repo write

```text
Work only in the <write-repo> repository.
Before editing, read AGENTS.md plus the relevant ADR and spec files in <write-repo>.
Also inspect <peer-repo-1> and <peer-repo-2> for the contracts or endpoints this task depends on.
Do not modify any repository except <write-repo>.
Run the <write-repo> local tests, and if the contract changes, run:
python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py
Task: <task details>
Success criteria: <expected behavior>
```

### Explicit multi-repo task

```text
This task requires coordinated edits in multiple repositories: <repo-a>, <repo-b>.
Read AGENTS.md plus the relevant ADR and spec files in each writable repo before editing.
Keep the change minimal and limit edits to the named repositories only.
Run local verification in each writable repo, then run:
python3 -m pytest tests/integration/test_cross_module.py tests/integration/test_teensy_e2e.py
Task: <task details>
Success criteria: <expected behavior>
```

## Do Not Do This

Do not ask Jules to change one repo while silently expecting behavior from another repo that Jules was never told to inspect.

Bad prompt pattern:

```text
Fix the Neurochip export bug.
```

This is underspecified if the bug is actually caused by a payload change coming from `neurocnl`.

Better prompt pattern:

```text
Work only in Neurochip.
Before editing, inspect the NeuroCNL deploy payload contract used by the Teensy export path.
Do not modify NeuroCNL unless you find the task cannot be completed without a coordinated change.
```

## Canonical Suite-Level Checks

When a contract change affects another module, reuse the existing root integration tests:

```bash
python3 -m pytest tests/integration/test_cross_module.py
python3 -m pytest tests/integration/test_teensy_e2e.py
```
