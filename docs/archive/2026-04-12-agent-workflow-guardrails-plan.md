# Agent Workflow Guardrails Plan

## Summary

This plan defines how the NeuroMorphicToolKit root repository should prevent launcher and runtime breakage from agentic workflows. The immediate goal is to make launcher readiness checks part of the standard definition of done for root control-plane work, not an optional cleanup step after the fact.

The plan focuses on governance plus local CI enforcement:

- tighten `AGENTS.md` so launcher and control-plane work must run launcher doctor and report the result
- extend `CODING_STYLE_GUIDE.md` so startup safety, manifest synchronization, optional dependency semantics, structured diagnostics, and launcher verification are explicit quality requirements
- update contributor and bootstrap docs so human and agent workflows follow the same launcher-readiness checks
- add a local enforcement wrapper so launcher work cannot claim completion when required launcher checks or tool prerequisites fail

## What Needs To Happen

### 1. Make launcher doctor a required gate

Launcher and control-plane work in the root repo should run:

```bash
python3 scripts/launcher_control_service.py --doctor --json
```

This check should be required for changes under `nmtk/**`, root launcher manifests, `scripts/**`, or root `tests/**` when those changes affect launcher behavior, module lifecycle behavior, or suite-visible startup semantics.

Expected policy:

- `fatalCount > 0` is a blocker unless the task is explicitly to diagnose or fix that failure
- results must be reported as `preflight failed` versus `degraded optional capability`
- launcher UI state changes and module manifest changes must be updated in the same change when they represent the same behavior

### 2. Tighten launcher-specific agent rules

The root `AGENTS.md` should define the process requirements for launcher work, and `nmtk/AGENTS.md` should define launcher-specific stop conditions.

Launcher-specific rules should include:

- do not change `modules.json` without updating launcher Dart models, launcher tests, and any consuming helper scripts in the same change
- do not introduce a new install or startup strategy without adding doctor or preflight coverage
- do not treat optional hardware or framework dependencies as fatal unless the manifest explicitly marks them required
- do not mark launcher work complete without launcher doctor and launcher unit coverage

### 3. Use the coding style guide as the quality bar

The coding style guide is not a replacement for `AGENTS.md`. Instead:

- `AGENTS.md` defines what process the agent must follow
- `CODING_STYLE_GUIDE.md` defines what the implementation must look like when that process is complete

For this issue class, the style guide should explicitly require:

- startup paths fail early and actionably instead of surfacing late crashes
- launcher state, manifests, models, helper scripts, and tests stay synchronized
- optional runtimes remain optional at import and startup time
- operator-facing launcher diagnostics use structured, machine-readable reporting rather than ad-hoc shell output
- launcher and control-plane changes include launcher verification, and suite-visible changes also include root integration tests

This is how the style guide directly helps prevent repeat breakage: it turns “don’t break startup” into concrete engineering expectations around typing, synchronization, logging, and verification.

### 4. Keep human and agent prompts aligned

The root onboarding and agent bootstrap docs should all say the same thing for launcher work:

- read `AGENTS.md`
- read `CODING_STYLE_GUIDE.md`
- read `nmtk/AGENTS.md`
- run launcher doctor
- run launcher unit tests
- run root integration tests when module contracts or suite-visible startup behavior change

This guidance belongs in:

- `docs/jules/JULES_WORKSPACE_GUIDE.md`
- `scripts/jules_bootstrap_workspace.sh`
- `CONTRIBUTING.md`

### 5. Add local enforcement

The repository should provide one canonical launcher guardrails wrapper:

```bash
bash scripts/run_launcher_guardrails.sh
```

Responsibilities:

- fail clearly if required tools such as `python3` or `flutter` are missing
- run launcher doctor
- run launcher unit tests
- run launcher Flutter tests
- optionally run root integration tests for suite-visible launcher changes

This wrapper should also be callable from local CI orchestration when launcher-owned surfaces change.

## Verification Expectations

### Documentation and policy consistency

- root `AGENTS.md`, `nmtk/AGENTS.md`, and `CODING_STYLE_GUIDE.md` must not conflict on authority or required checks
- contributor docs and agent bootstrap docs must reference the same launcher commands

### Command-level checks

```bash
python3 scripts/launcher_control_service.py --doctor --json
python3 -m unittest tests.test_launcher_control_service
python3 -m pytest tests/integration/test_cross_module.py
python3 -m pytest tests/integration/test_teensy_e2e.py
```

### Scenario-level expectations

- missing `fastapi` in Neurobench is a documented fatal preflight blocker
- missing Lava in Neurochip is a documented degraded optional capability, not a fatal startup blocker
- launcher and workspace surfaces should report preflight errors directly instead of relying on connection-refused symptoms

## Defaults And Assumptions

- this is a root-governance pass; no submodule-specific `AGENTS.md` rewrites are required unless a module rule conflicts with the launcher policy
- the coding style guide remains subordinate to the nearest `AGENTS.md`, but it defines the cross-repo defaults that make launcher/runtime work safe
- future launcher/control-plane work is only done when reads are completed, launcher doctor has been run, launcher tests have been run, and any required root integration tests either passed or were explicitly reported as blocked
