# Ordered Backlog

Status snapshot updated on `2026-04-13`.

## Active Queue

1. [teensy-studio-deployment-plan.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/teensy-studio-deployment-plan.md)
   `implemented with remaining real-board evidence`
   Contract, handoff, UI, and integration coverage are in place. The main missing proof is one recorded real-board flash plus post-flash verification result.

2. [pynq-z2-studio-deployment-plan.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/pynq-z2-studio-deployment-plan.md)
   `implemented with remaining board-ready artifact evidence`
   The export/runtime/handoff path is largely present. The remaining gap is truthful closure around real board-ready overlay artifacts versus simulator-only acceptance.

3. [akida-studio-deployment-plan.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/akida-studio-deployment-plan.md)
   `implemented with remaining SDK-backed verification`
   Shared support states, contracts, mapping, and workflow UI are present. What remains is actual BrainChip SDK-backed proof for the `sdk_deployable` path.

4. [neurosense-research-credibility-rollout.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/neurosense-research-credibility-rollout.md)
   `partially implemented`
   The artifact contract and documentation foundation are in place, but the real Cyton validation, benchmarks, UI alignment, and final demo are still open.

## Completed / No Longer Blocking

- [add-canonical-launcher-guardrails-wrapper.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/add-canonical-launcher-guardrails-wrapper.md)
  `complete`
  Verified by a passing `bash scripts/run_launcher_guardrails.sh` run with `fatalCount = 0`.

- [akida-topological-drift.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/akida-topological-drift.md)
  `complete`
  Shared topology analysis now drives both Akida validation and capability planning.

- [spinnaker-hardware-validation.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/spinnaker-hardware-validation.md)
  `complete`
  Hardware-aware validation now covers both `spinnaker` and `spinnaker2` with passing layer-level tests.
