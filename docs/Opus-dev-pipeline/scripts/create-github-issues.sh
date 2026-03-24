#!/usr/bin/env bash
#
# create-github-issues.sh — Creates GitHub issues for the CDD+PBT migration.
#
# Each issue is self-contained with full context so Jules (or any agent)
# can pick it up from the issue alone without needing this repo's history.
#
# Usage:
#   cd NeuroMorphicToolKit
#   bash Research-Spec-driven-development/Opus-dev-pipeline/scripts/create-github-issues.sh
#
# Prerequisites:
#   - gh CLI authenticated (gh auth login)
#   - Repository set (gh repo set-default)
#
set -euo pipefail

REPO_FLAG=""
# Uncomment and set if not using default repo:
# REPO_FLAG="--repo Completed-Spoon-6/NeuroMorphicToolKit"

LABEL_MIGRATION="cdd-pbt-migration"
LABEL_CONTRACTS="contracts"
LABEL_PROPERTIES="property-tests"
LABEL_CI="ci"
LABEL_JULES="jules"
LABEL_FEATURE="feature"

echo "=== Creating labels (idempotent) ==="
gh label create "$LABEL_MIGRATION" --description "CDD+PBT pipeline migration" --color "0E8A16" $REPO_FLAG 2>/dev/null || true
gh label create "$LABEL_CONTRACTS" --description "Pydantic domain contracts" --color "1D76DB" $REPO_FLAG 2>/dev/null || true
gh label create "$LABEL_PROPERTIES" --description "Hypothesis property-based tests" --color "D93F0B" $REPO_FLAG 2>/dev/null || true
gh label create "$LABEL_CI" --description "CI/CD improvements" --color "FBCA04" $REPO_FLAG 2>/dev/null || true

echo ""
echo "=== Phase 1: Foundation (Issues 1-6) ==="

# ── Issue 1: Install dependencies ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-001: Add hypothesis and pydantic>=2.0 to all module dependencies" \
  --label "$LABEL_MIGRATION,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Context
We are migrating to a Contract-Driven Development + Property-Based Testing pipeline.
All Python modules need `hypothesis` and `pydantic>=2.0` as dev/test dependencies.

## Task
For each module, add to the appropriate dependency config:

### neurocnl (`neurocnl/pyproject.toml`)
Add to `[project.optional-dependencies]` under `dev`:
```
hypothesis>=6.90.0
pydantic>=2.0
```

### Neurochip (`Neurochip/neurochip/pyproject.toml`)
Add to `[tool.poetry.group.dev.dependencies]`:
```
hypothesis = ">=6.90.0"
pydantic = ">=2.0"
```

### Neurobench (`Neurobench/neurobench/pyproject.toml`)
Add to `[dependency-groups]` under `dev`:
```
hypothesis = ">=6.90.0"
pydantic = ">=2.0"
```

### Neurosim, Neurosense, Neurohub, Neuro-Dream-Hand (`pyproject.toml`)
Add to `[project.optional-dependencies]` under `dev`:
```
hypothesis>=6.90.0
pydantic>=2.0
```

## Acceptance Criteria
- [ ] `pip install -e ".[dev]"` works in each module
- [ ] `python -c "import hypothesis; import pydantic; print('OK')"` succeeds
- [ ] No existing tests broken by the addition
ISSUE_EOF
)"

# ── Issue 2: neurocnl contracts ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-002: Install neurocnl domain contracts (Pydantic models)" \
  --label "$LABEL_MIGRATION,$LABEL_CONTRACTS,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Context
neurocnl has 18 Layer 1 invariants in `neurocnl/layers/layer1_invariants.py` as plain
functions operating on dicts. We need to wrap these as Pydantic v2 models so that
invalid parameters are rejected at construction time with clear error messages.

## Task
1. Create `neurocnl/contracts/` directory with `__init__.py`
2. Create `neurocnl/contracts/neuron_params.py` containing:
   - `LIFNeuronContract` — fields: threshold, resting_potential, reset_potential, refractory_period, tau
     - Validators: threshold > resting, reset <= threshold, tau > 0, refractory > 0, membrane decays toward rest
   - `SynapticContract` — fields: weight, is_inhibitory, axonal_delay
     - Validators: inhibitory weight <= 0, delay in [0, 150ms]
   - `STDPContract` — fields: learning_rate, stdp_window, weight_min, weight_max, rule_type
     - Validators: lr > 0, window in (0, 100ms], valid rule type in {PES, BCM, OJA, STDP}
   - `PopulationContract` — fields: n_neurons, dimensions, radius
     - Validators: all > 0
3. Create `neurocnl/contracts/hardware_export.py` containing:
   - `LoihiExportContract` — weight [-10, 10], n_neurons [1, 1024], delay [0, 62ms]
   - `SpiNNakerExportContract` — weight in s16.15 range, n_neurons [1, 255]
   - `TeensyExportContract` — memory estimation, bit_width in {4, 8, 16, 32}
4. Create `neurocnl/contracts/pipeline_contracts.py` containing:
   - `CNLParseResultContract`, `ValidationResultContract`, `SimulationResultContract`
   - `SimulationSummaryContract`, `AssertionResultContract`
   - API response contracts: `ParseAPIResponse`, `ValidateAPIResponse`, `SimulateAPIResponse`

## Reference
See `Research-Spec-driven-development/Opus-dev-pipeline/neurocnl/contracts/` for
complete implementations to copy from.

## Acceptance Criteria
- [ ] All contract classes importable: `from neurocnl.contracts import LIFNeuronContract`
- [ ] Invalid physics params raise `ValidationError` with descriptive messages
- [ ] Existing layer1_invariants.py tests still pass (contracts are additive, not replacing)
- [ ] `mypy --strict neurocnl/contracts/` passes
ISSUE_EOF
)"

# ── Issue 3: neurocnl property tests ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-003: Add Hypothesis property tests for neurocnl physics" \
  --label "$LABEL_MIGRATION,$LABEL_PROPERTIES,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Context
Property-based tests auto-generate hundreds of edge cases per property.
For neurocnl, we need properties that verify physics laws hold for ALL valid inputs.

## Task
Create `neurocnl/properties/test_physics_properties.py` with these test classes:

### TestPhysicsInvariants (500 examples each)
- `test_threshold_always_above_resting` — For any valid LIFNeuronContract, threshold > resting
- `test_reset_never_above_threshold` — reset <= threshold always
- `test_membrane_decay_direction` — dv/dt sign correct for above/below rest
- `test_refractory_limits_max_firing_rate` — max rate = 1/refractory, must be < 1MHz

### TestContractRejection
- `test_threshold_at_or_below_resting_rejected` — threshold <= rest always raises
- `test_zero_or_negative_tau_rejected` — tau <= 0 always raises
- `test_zero_or_negative_refractory_rejected` — ref <= 0 always raises

### TestLoihiProperties
- `test_valid_loihi_params_accepted` — weight [-10,10] + neurons [1,1024] accepted
- `test_overweight_loihi_rejected` — weight > 10 rejected
- `test_loihi_quantization_roundtrip` — quantize→dequantize loses < 1 LSB

### TestMetamorphicProperties
- `test_larger_tau_means_slower_decay` — larger tau → smaller |dv/dt|
- `test_longer_refractory_means_lower_max_rate` — longer ref → lower max rate

### TestCNLPipelineProperties (requires neurocnl, 100 examples, 30s deadline)
- `test_valid_cnl_spec_always_passes_validation` — valid params → L1+L2 pass
- `test_negative_threshold_spec_fails_or_parses_differently` — invalid → L1 fails

## Reference
See `Research-Spec-driven-development/Opus-dev-pipeline/neurocnl/properties/` for
complete implementation.

## Acceptance Criteria
- [ ] `pytest neurocnl/properties/ -v --hypothesis-seed=0` passes
- [ ] At least 5000 total test cases generated across all properties
- [ ] No existing tests broken
ISSUE_EOF
)"

# ── Issue 4: Neuro-Dream-Hand contracts ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-004: Install Neuro-Dream-Hand hardware contracts" \
  --label "$LABEL_MIGRATION,$LABEL_CONTRACTS,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Context
Neuro-Dream-Hand SPEC.md defines precise hardware constraints for Phase 4 (HITL) and
Phase 5 (Chip Deployment). These must become Pydantic contracts.

## Task
Create `Neuro-Dream-Hand/contracts/hardware_contracts.py` with:

### Phase 4 Contracts
- `SerialBridgeContract` — grip [0,1], baud 1M, dt=0.002
- `SensorFrameContract` — force_raw [0, 4095] (12-bit ADC)
- `EMGStreamContract` — 4ch, 200Hz, bandpass 20-90Hz, nyquist guard
- `EMGSpikeOutputContract` — value [0, 1]
- `HITLLatencyContract` — median <4ms, p95 <2ms

### Phase 5 Contracts
- `FaultInjectionContract` — dead/stuck/noise all [0, 0.30]
- `CrossbarExportContract` — g_min < g_max, g_min > 0
- `DropTestContract` — sim-to-real gap <= 15 pct points

## Reference
See `Research-Spec-driven-development/Opus-dev-pipeline/neuro-dream-hand/contracts/`

## Acceptance Criteria
- [ ] All contracts importable
- [ ] Out-of-range grip (>1.0, <0.0) raises ValidationError
- [ ] ADC values > 4095 raise ValidationError
- [ ] Fault fractions > 30% raise ValidationError
ISSUE_EOF
)"

# ── Issue 5: Neuro-Dream-Hand property tests ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-005: Add property tests for Neuro-Dream-Hand" \
  --label "$LABEL_MIGRATION,$LABEL_PROPERTIES,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Task
Create `Neuro-Dream-Hand/properties/test_hitl_properties.py` with:

- TestSerialProtocolProperties: grip range, uint16 roundtrip
- TestSensorFrameProperties: ADC range enforcement
- TestEMGProperties: output range enforcement
- TestFaultInjectionProperties: fraction range enforcement
- TestCrossbarProperties: conductance range validity
- TestDropTestProperties: sim-to-real gap acceptance

## Reference
See `Research-Spec-driven-development/Opus-dev-pipeline/neuro-dream-hand/properties/`

## Acceptance Criteria
- [ ] `pytest Neuro-Dream-Hand/properties/ -v --hypothesis-seed=0` passes
- [ ] All boundary conditions tested
ISSUE_EOF
)"

# ── Issue 6: AGENTS.md and GUARDRAILS.md ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-006: Add AGENTS.md and GUARDRAILS.md to neurocnl and Neuro-Dream-Hand" \
  --label "$LABEL_MIGRATION,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Task
Copy the following files into the module roots:

1. `Research-Spec-driven-development/Opus-dev-pipeline/neurocnl/AGENTS.md` → `neurocnl/AGENTS.md`
2. `Research-Spec-driven-development/Opus-dev-pipeline/neurocnl/GUARDRAILS.md` → `neurocnl/GUARDRAILS.md`
3. `Research-Spec-driven-development/Opus-dev-pipeline/neuro-dream-hand/AGENTS.md` → `Neuro-Dream-Hand/AGENTS.md`
4. `Research-Spec-driven-development/Opus-dev-pipeline/neuro-dream-hand/GUARDRAILS.md` → `Neuro-Dream-Hand/GUARDRAILS.md`

These files govern AI agent behavior and capture known failure patterns.

## Acceptance Criteria
- [ ] All 4 files exist in module roots
- [ ] AGENTS.md contains non-negotiable rules and stop-and-ask conditions
- [ ] GUARDRAILS.md contains at least 3 initial failure patterns per module
ISSUE_EOF
)"


echo ""
echo "=== Phase 2: Expansion (Issues 7-11) ==="

# ── Issue 7: Remaining module contracts ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-007: Install contracts for Neurosim, Neurosense, Neurochip, Neurobench, Neurohub" \
  --label "$LABEL_MIGRATION,$LABEL_CONTRACTS,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Task
Create Pydantic contract files for the remaining 5 modules. Each module's contracts
are derived from its spec file.

### Neurosim → `Neurosim/contracts/design_contracts.py`
From neurosim_spec.md: ComponentBlockContract, ConnectionContract, CanvasGraphContract,
PreviewContract (<=500ms), ParameterSweepContract (max 20 steps), ExportFormatContract

### Neurosense → `Neurosense/contracts/signal_contracts.py`
From neurosense_spec.md: DeviceContract (1-8 ch), EncodingConfigContract,
SignalQualityContract, ApplicationPresetContract, DisplayLatencyContract (<50ms),
PipelineLatencyContract (<100ms), RecordingSessionContract

### Neurochip → `Neurochip/contracts/deployment_contracts.py`
From neurochip_spec.md: HardwareTargetContract, QuantizationContract (2-32 bit),
FaultSweepContract (max 30%), PowerEstimateContract, LatencyEstimateContract
(best<=typical<=worst), TeensyFirmwareContract

### Neurobench → `Neurobench/contracts/benchmark_contracts.py`
From neurobench_spec.md: BenchmarkDefinitionContract, BenchmarkResultContract,
RegressionCheckContract, RobustnessCurveContract (N>=5 seeds),
CrossTargetComparisonContract

### Neurohub → `Neurohub/contracts/orchestration_contracts.py`
From neurohub_spec.md: SuitePortContract (no conflicts), HealthCheckContract,
ProjectContract, WorkflowStepContract, WorkflowTemplateContract,
MemberRoleContract, ActivityEntryContract

## Reference
See `Research-Spec-driven-development/Opus-dev-pipeline/{module}/contracts/`

## Acceptance Criteria
- [ ] Each module has a `contracts/` directory with typed Pydantic models
- [ ] All validators enforce spec constraints with descriptive error messages
- [ ] `mypy` passes on all contract files
ISSUE_EOF
)"

# ── Issue 8: Remaining module property tests ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-008: Add property tests for Neurosense, Neurochip, Neurobench" \
  --label "$LABEL_MIGRATION,$LABEL_PROPERTIES,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Task
Create Hypothesis property test files for modules with numerical/hardware constraints:

### Neurosense → `Neurosense/properties/test_encoding_properties.py`
- Encoding method validity, device channel limits, latency bounds, bandpass validation, quality classification

### Neurochip → `Neurochip/properties/test_deployment_properties.py`
- Quantization bit-width validity, latency ordering, fault rate bounds

### Neurobench (optional — lower priority)
- Regression detection accuracy, robustness curve consistency

## Reference
See `Research-Spec-driven-development/Opus-dev-pipeline/{module}/properties/`

## Acceptance Criteria
- [ ] `pytest {module}/properties/ -v --hypothesis-seed=0` passes for each module
ISSUE_EOF
)"

echo ""
echo "=== Phase 3: CI/CD (Issues 9-13) ==="

# ── Issue 9: Fix CI workflow ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-009: Fix broken CI workflow (duplicate jobs, missing needs, inconsistencies)" \
  --label "$LABEL_CI,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Problem
The current `.github/workflows/ci.yml` has several bugs:

1. **Duplicate test-neurobench job** — Lines ~205-222 and ~256-281 define the same job twice.
   The second definition silently overrides the first, and `ci-passed` references both.
   Fix: Remove the duplicate job block.

2. **Inconsistent Python versions** — neurochip uses 3.12 while others use 3.11.
   Fix: Standardize on 3.11 for all modules (match pyproject.toml requirements).

3. **Neurochip ruff allows failure** — `continue-on-error: true` on ruff means
   linting failures are silently ignored. All other modules hard-fail.
   Fix: Remove `continue-on-error: true` from neurochip ruff step.

4. **Missing flutter test steps** — neurochip-frontend, neurohub-frontend,
   neurosense-frontend, neurobench-frontend only run `flutter analyze`, no `flutter test`.
   Fix: Add `flutter test` step (or skip with comment if no tests exist yet).

5. **ci-passed needs array may be incomplete** — verify all test jobs are listed.

## Task
Fix all 5 issues in `.github/workflows/ci.yml`.

## Acceptance Criteria
- [ ] No duplicate job definitions
- [ ] All Python modules use Python 3.11
- [ ] Ruff failures are hard failures for all modules
- [ ] CI workflow passes on a clean PR
ISSUE_EOF
)"

# ── Issue 10: Add contract verification to CI ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-010: Add contract and property-based test verification to CI pipeline" \
  --label "$LABEL_CI,$LABEL_MIGRATION,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Task
Add a new workflow `.github/workflows/contract-verification.yml` that runs on PRs
and pushes to main/dev. This workflow verifies contracts and property-based tests.

### Jobs

1. **verify-neurocnl-contracts**
   - Trigger: changes in neurocnl/
   - Steps: install deps, mypy --strict contracts/, pytest contracts/, pytest properties/

2. **verify-neurodreamhand-contracts**
   - Trigger: changes in Neuro-Dream-Hand/
   - Steps: same pattern

3. **verify-other-contracts** (matrix: [Neurosim, Neurosense, Neurochip, Neurobench, Neurohub])
   - Trigger: changes in respective module
   - Steps: same pattern

4. **contracts-passed** — summary gate job

### Configuration
- Hypothesis settings: `--hypothesis-seed=0 -x` (deterministic, fail-fast)
- Max examples in CI: 200 (vs 500 locally) for speed
- Timeout: 10 minutes per job

## Reference
See `Research-Spec-driven-development/Opus-dev-pipeline/.github/workflows/contract-verification.yml`

## Acceptance Criteria
- [ ] Workflow triggers on PRs and pushes to main/dev
- [ ] Path-based filtering only runs relevant module checks
- [ ] Property tests use deterministic seed
- [ ] contracts-passed is required for merge
ISSUE_EOF
)"

# ── Issue 11: Fix auto-merge for Jules PRs ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-011: Fix auto-merge workflow for Jules and agent PRs" \
  --label "$LABEL_CI,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Problem
The current `auto-merge-jules-prs.yml` enables GitHub auto-merge but:
1. Auto-merge requires branch protection with required status checks — if these aren't configured, auto-merge does nothing.
2. The workflow only handles Jules branches (jules/*) but not other agent branches.
3. There's no verification that CI actually passed before merge.

## Task
Replace with a workflow that:
1. Triggers on `pull_request` opened/reopened AND `check_suite` completed
2. For PRs from branches matching `jules/*` or `auto/*`:
   a. Wait for all required CI checks to pass
   b. If all checks pass, approve the PR (using GITHUB_TOKEN)
   c. Enable auto-merge with squash strategy
3. Add a safety check: if the PR modifies any of these files, do NOT auto-merge:
   - `**/layer1_invariants.py`
   - `**/contracts/**`
   - `**/properties/**`
   - `**/AGENTS.md`
   - `**/GUARDRAILS.md`
   - `.github/workflows/**`

## Acceptance Criteria
- [ ] Jules PRs that pass CI are automatically merged
- [ ] Jules PRs that modify protected files require human review
- [ ] Failed CI blocks auto-merge
- [ ] Works with both `jules/*` and `auto/*` branch prefixes
ISSUE_EOF
)"

# ── Issue 12: Add PR template ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-012: Add pull request template with contract checklist" \
  --label "$LABEL_CI,$LABEL_MIGRATION,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Task
Create `.github/PULL_REQUEST_TEMPLATE.md` with:

```markdown
## Summary
<!-- One sentence describing what this PR does -->

## Module(s) Changed
<!-- Check all that apply -->
- [ ] neurocnl
- [ ] Neuro-Dream-Hand
- [ ] Neurosim
- [ ] Neurosense
- [ ] Neurochip
- [ ] Neurobench
- [ ] Neurohub
- [ ] neuro_toolkit
- [ ] CI/CD

## Contract Checklist
- [ ] No physics invariants were modified without human approval
- [ ] All new parameters use Pydantic contract models
- [ ] Property tests pass locally (pytest properties/ --hypothesis-seed=0)
- [ ] No existing tests were weakened or deleted
- [ ] GUARDRAILS.md updated if a new failure pattern was discovered
- [ ] AGENTS.md consulted before implementation

## Test Evidence
<!-- Paste pytest output or link to CI run -->
```

## Acceptance Criteria
- [ ] Template appears on all new PRs
- [ ] Checklist includes contract verification items
ISSUE_EOF
)"

# ── Issue 13: Add issue templates ──
gh issue create $REPO_FLAG \
  --title "CDD-PBT-013: Add GitHub issue templates for contracts and features" \
  --label "$LABEL_CI,$LABEL_JULES,$LABEL_FEATURE" \
  --body "$(cat <<'ISSUE_EOF'
## Task
Create `.github/ISSUE_TEMPLATE/` with two templates:

### 1. `contract-migration.yml`
Fields: module (dropdown), contract_type (new contract / extend existing / property test),
description, acceptance criteria, spec_reference

### 2. `feature-request.yml`
Fields: module (dropdown), description, contracts_needed (which contracts must be
created/updated BEFORE implementation), acceptance_criteria

## Acceptance Criteria
- [ ] Issue creation shows template chooser
- [ ] Contract migration template includes spec reference field
- [ ] Feature template requires contracts_needed field
ISSUE_EOF
)"

echo ""
echo "=== Done! Created 13 issues for CDD+PBT migration ==="
echo ""
echo "Issues are ordered by dependency:"
echo "  Phase 1 (Foundation): #1-6 — can be worked in parallel"
echo "  Phase 2 (Expansion):  #7-8 — depends on Phase 1"
echo "  Phase 3 (CI/CD):      #9-13 — #9 is independent, #10-13 depend on Phase 1"
