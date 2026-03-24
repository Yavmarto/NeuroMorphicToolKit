# Opus-dev-pipeline: CDD+PBT Migration Kit for NMTK

Contract-Driven Development + Property-Based Testing pipeline.
Everything an AI agent needs to build NMTK code that provably satisfies
physics, biology, and hardware specifications.

---

## How It Works

```
1. Human writes contracts + properties (THE SCIENCE)
2. Script creates GitHub issues from this kit
3. Jules/agent picks up issues and writes ALL code
4. CI automatically verifies code against contracts
5. Auto-merge if CI passes (unless protected files changed)
```

---

## Directory Structure

```
Opus-dev-pipeline/
├── README.md                          ← You are here
│
├── scripts/
│   ├── create-github-issues.sh        ← Creates 13 migration issues via gh CLI
│   ├── verify-contracts-local.sh      ← Run full verification locally
│   ├── generate-golden-baselines.sh   ← Create simulation regression baselines
│   └── patch-ci-yml.sh               ← Documents CI fixes needed
│
├── .github/
│   ├── workflows/
│   │   ├── contract-verification.yml  ← NEW: Contract + PBT CI pipeline
│   │   └── auto-merge-agents.yml      ← FIXED: Auto-merge for Jules/agent PRs
│   ├── PULL_REQUEST_TEMPLATE.md       ← NEW: PR template with contract checklist
│   └── ISSUE_TEMPLATE/
│       ├── contract-migration.yml     ← NEW: Issue template for contracts
│       └── feature-with-contracts.yml ← NEW: Feature template requiring contracts
│
├── neurocnl/
│   ├── AGENTS.md                      ← Agent behavioral rules
│   ├── GUARDRAILS.md                  ← Known failure patterns
│   ├── contracts/
│   │   ├── __init__.py
│   │   ├── neuron_params.py           ← LIF, Synaptic, STDP, Population
│   │   ├── hardware_export.py         ← Loihi, SpiNNaker, Teensy, C header
│   │   └── pipeline_contracts.py      ← Parse, Validate, Simulate, Assert
│   └── properties/
│       └── test_physics_properties.py ← 12 Hypothesis property tests
│
├── neuro-dream-hand/
│   ├── AGENTS.md
│   ├── GUARDRAILS.md
│   ├── contracts/
│   │   └── hardware_contracts.py      ← Serial, EMG, Fault, Crossbar, DropTest
│   └── properties/
│       └── test_hitl_properties.py    ← 11 property tests
│
├── neurosim/
│   └── contracts/
│       └── design_contracts.py        ← Canvas, Preview, Sweep, Export
│
├── neurosense/
│   ├── contracts/
│   │   └── signal_contracts.py        ← Device, Encoding, Latency, Quality
│   └── properties/
│       └── test_encoding_properties.py
│
├── neurochip/
│   ├── contracts/
│   │   └── deployment_contracts.py    ← Target, Quantization, Fault, Power
│   └── properties/
│       └── test_deployment_properties.py
│
├── neurobench/
│   └── contracts/
│       └── benchmark_contracts.py     ← Benchmark, Regression, Robustness
│
└── neurohub/
    └── contracts/
        └── orchestration_contracts.py ← Port, Health, Project, Workflow
```

---

## Migration Steps

### Step 0: Prerequisites
```bash
# Ensure gh CLI is authenticated
gh auth status

# Ensure you're in the repo root
cd NeuroMorphicToolKit
```

### Step 1: Create GitHub Issues (2 minutes)
```bash
bash Research-Spec-driven-development/Opus-dev-pipeline/scripts/create-github-issues.sh
```
This creates 13 issues organized in 3 phases. Jules can pick them up immediately.

### Step 2: Install CI Workflows (5 minutes)
```bash
# Copy new workflows
cp Research-Spec-driven-development/Opus-dev-pipeline/.github/workflows/contract-verification.yml \
   .github/workflows/contract-verification.yml

cp Research-Spec-driven-development/Opus-dev-pipeline/.github/workflows/auto-merge-agents.yml \
   .github/workflows/auto-merge-agents.yml

# Copy PR and issue templates
cp Research-Spec-driven-development/Opus-dev-pipeline/.github/PULL_REQUEST_TEMPLATE.md \
   .github/PULL_REQUEST_TEMPLATE.md

mkdir -p .github/ISSUE_TEMPLATE
cp Research-Spec-driven-development/Opus-dev-pipeline/.github/ISSUE_TEMPLATE/*.yml \
   .github/ISSUE_TEMPLATE/

# Commit and push
git add .github/
git commit -m "ci: add contract verification workflow and templates"
git push
```

### Step 3: Fix Existing CI (10 minutes)
Read `scripts/patch-ci-yml.sh` for the 6 specific fixes needed in `ci.yml`:
1. Remove duplicate test-neurobench job
2. Standardize Python to 3.11
3. Remove neurochip ruff continue-on-error
4. Add flutter test to frontend jobs
5. Verify ci-passed needs array
6. Add contracts-passed to branch protection

### Step 4: Install Contracts (Jules does this)
Jules picks up issues #2, #4, #7 and copies contract files into modules:
```bash
# For each module, the pattern is:
cp Research-Spec-driven-development/Opus-dev-pipeline/{module}/contracts/*.py \
   {Module}/contracts/
```

### Step 5: Install Property Tests (Jules does this)
Jules picks up issues #3, #5, #8 and copies property test files:
```bash
cp Research-Spec-driven-development/Opus-dev-pipeline/{module}/properties/*.py \
   {Module}/properties/
```

### Step 6: Generate Golden Baselines (5 minutes, after neurocnl works)
```bash
bash Research-Spec-driven-development/Opus-dev-pipeline/scripts/generate-golden-baselines.sh
git add neurocnl/baselines/
git commit -m "test: add golden simulation baselines for regression testing"
```

### Step 7: Verify Locally
```bash
bash Research-Spec-driven-development/Opus-dev-pipeline/scripts/verify-contracts-local.sh
```

---

## CI/CD Architecture After Migration

```
PR opened or pushed
    │
    ├──► ci.yml (existing, fixed)
    │    ├── detect-changes
    │    ├── test-neurocnl-backend (pytest, ruff, mypy)
    │    ├── test-neurosim, test-neurochip, ...
    │    ├── test-neurotoolkit (flutter analyze + test)
    │    └── ci-passed (gate)
    │
    ├──► contract-verification.yml (NEW)
    │    ├── detect-changes
    │    ├── verify-neurocnl (mypy contracts/, pytest contracts/, pytest properties/)
    │    ├── verify-neurodreamhand
    │    ├── verify-other-modules (matrix)
    │    └── contracts-passed (gate)
    │
    └──► auto-merge-agents.yml (FIXED)
         ├── Check: is this a jules/* or auto/* branch?
         ├── Check: any protected files changed?
         ├── Wait for CI + contract checks to pass
         ├── If all pass + no protected files → auto-merge
         └── If protected files changed → request human review
```

**Required status checks for branch protection:**
- `ci-passed`
- `contracts-passed`

---

## CI Fixes Applied

| Issue | Before | After |
|-------|--------|-------|
| Duplicate test-neurobench | Silent override, CI confusion | Single job definition |
| Python version inconsistency | Mix of 3.10, 3.11, 3.12 | All jobs use 3.11 |
| Neurochip ruff failure ignored | `continue-on-error: true` | Hard failure like all modules |
| Frontend jobs skip tests | Only `flutter analyze` | `flutter analyze` + `flutter test` |
| Auto-merge doesn't work | Enables auto-merge but no status checks configured | Waits for CI, checks protected files, then merges |
| No PR template | Blank PR descriptions | Contract checklist required |
| No issue templates | Freeform issues | Structured templates with contract requirements |

---

## Issue Dependency Graph

```
Phase 1 (Foundation) — All independent, can run in parallel:
  #1  Add hypothesis + pydantic deps
  #2  neurocnl contracts
  #3  neurocnl property tests          (depends on #2)
  #4  Neuro-Dream-Hand contracts
  #5  Neuro-Dream-Hand property tests   (depends on #4)
  #6  AGENTS.md + GUARDRAILS.md

Phase 2 (Expansion) — Depends on Phase 1:
  #7  Remaining module contracts         (depends on #1)
  #8  Remaining module property tests    (depends on #7)

Phase 3 (CI/CD) — #9 independent, rest depend on Phase 1:
  #9  Fix broken CI workflow             (independent)
  #10 Contract verification workflow     (depends on #2, #4)
  #11 Fix auto-merge                     (depends on #9)
  #12 PR template                        (independent)
  #13 Issue templates                    (independent)
```

---

## How Contracts Map to Existing Specs

| Module | Spec File | Contract File | Key Constraints Encoded |
|--------|-----------|---------------|------------------------|
| neurocnl | `neuromorphic_spec_plan.md` + `layer1_invariants.py` | `neuron_params.py`, `hardware_export.py`, `pipeline_contracts.py` | 18 physics invariants, Loihi/SpiNNaker/Teensy limits, pipeline data shapes |
| Neuro-Dream-Hand | `SPEC.md` | `hardware_contracts.py` | Serial protocol, EMG Ganglion limits, fault injection bounds, drop-test gap |
| Neurosim | `neurosim_spec.md` | `design_contracts.py` | Preview <=500ms, sweep max 20 steps, canvas graph validity |
| Neurosense | `neurosense_spec.md` | `signal_contracts.py` | Display <50ms, pipeline <100ms, 1-8 channels, encoding methods |
| Neurochip | `neurochip_spec.md` | `deployment_contracts.py` | Quantization 2-32 bit, fault max 30%, latency ordering |
| Neurobench | `neurobench_spec.md` | `benchmark_contracts.py` | Regression threshold, N>=5 seeds, robustness curves |
| Neurohub | `neurohub_spec.md` | `orchestration_contracts.py` | Port assignments, health checks, workflow steps |
