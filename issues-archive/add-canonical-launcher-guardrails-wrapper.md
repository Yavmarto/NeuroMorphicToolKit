---
title: "Add Canonical Launcher Guardrails Wrapper for Local Enforcement"
labels: ["launcher", "scripts", "ci", "verification"]
---

## Audit Status

Status as of 2026-04-13: `complete`

What is already landed:
- `scripts/run_launcher_guardrails.sh` exists and is the canonical wrapper.
- The wrapper checks for required tools, runs launcher doctor first, then launcher Python and Flutter tests, and supports `--with-integration`.
- Root workflow docs and agent guidance point contributors at the wrapper consistently.
- `python3 -m unittest tests.test_launcher_control_service` now passes cleanly.
- `bash scripts/run_launcher_guardrails.sh` now passes cleanly in the current repo state.

What is still open:
- No wrapper-specific implementation work remains.
- Current launcher doctor output is `fatalCount = 0` with one degraded optional capability (`lava` unavailable in `Neurochip`), which is not a blocker for this issue.

## Continuation Order

Queue position: `completed foundation`

## Next Action To Continue

- No direct follow-up is required here.
- If launcher behavior changes later, re-run `bash scripts/run_launcher_guardrails.sh` and only reopen this issue if the wrapper itself regresses.

# Goal
Add `scripts/run_launcher_guardrails.sh` as the canonical local enforcement wrapper for launcher-owned changes.

# Scope
- fail clearly when required tools such as `python3` or `flutter` are missing
- run `python3 scripts/launcher_control_service.py --doctor --json`
- run launcher unit tests
- run launcher Flutter tests
- optionally run `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py` for suite-visible launcher changes
- make the wrapper usable both by humans and by local CI orchestration

# Deliverables
- canonical `scripts/run_launcher_guardrails.sh` wrapper
- documented prerequisite checks and failure modes
- support for optional root integration checks when launcher changes are suite-visible

# Acceptance Criteria
- [x] One documented wrapper exists for launcher guardrails execution.
- [x] The wrapper fails clearly when required tools are unavailable.
- [x] The wrapper runs launcher doctor plus launcher-specific unit and Flutter tests.
- [x] The wrapper supports root integration checks for suite-visible launcher changes.
- [x] Failure output is clear enough for both local developer use and CI orchestration.

# Depends On
- [launcher-doctor-required-gate.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues-archive/launcher-doctor-required-gate.md)
- [launcher-quality-bar-in-coding-style-guide.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues-archive/launcher-quality-bar-in-coding-style-guide.md)
