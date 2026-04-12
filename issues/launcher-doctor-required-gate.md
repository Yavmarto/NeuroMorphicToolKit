---
title: "Make Launcher Doctor a Required Gate for Root Control-Plane Work"
labels: ["launcher", "guardrails", "verification", "root"]
---

# Goal
Require `python3 scripts/launcher_control_service.py --doctor --json` for root launcher and control-plane changes that affect launcher behavior, module lifecycle behavior, or suite-visible startup semantics.

# Scope
- define when the gate applies for `nmtk/**`, root launcher manifests, `scripts/**`, and root `tests/**`
- treat `fatalCount > 0` as a blocker unless the task is explicitly to diagnose or fix that failure
- require reporting to distinguish `preflight failed` from `degraded optional capability`
- require launcher UI state changes and module manifest changes to land in the same change when they describe the same behavior

# Acceptance Criteria
- [ ] The required launcher doctor command and its applicability boundaries are documented in root workflow policy.
- [ ] Blocker semantics for `fatalCount > 0` are explicit and do not allow launcher work to claim completion when the doctor reports a fatal preflight failure.
- [ ] Guidance explicitly separates fatal preflight failures from degraded optional capabilities in operator-facing status reporting.
- [ ] Launcher UI state and manifest synchronization requirements are documented for same-behavior changes.
- [ ] Scenario expectations are captured for at least one fatal blocker case and one degraded optional capability case.

# Depends On
None.
