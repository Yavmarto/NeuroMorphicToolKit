---
title: "Add Canonical Launcher Guardrails Wrapper for Local Enforcement"
labels: ["launcher", "scripts", "ci", "verification"]
---

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
- [ ] One documented wrapper exists for launcher guardrails execution.
- [ ] The wrapper fails clearly when required tools are unavailable.
- [ ] The wrapper runs launcher doctor plus launcher-specific unit and Flutter tests.
- [ ] The wrapper supports root integration checks for suite-visible launcher changes.
- [ ] Failure output is clear enough for both local developer use and CI orchestration.

# Depends On
- [launcher-doctor-required-gate.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/launcher-doctor-required-gate.md)
- [launcher-quality-bar-in-coding-style-guide.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/launcher-quality-bar-in-coding-style-guide.md)
