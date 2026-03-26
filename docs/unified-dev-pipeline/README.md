# Unified CDD+PBT Migration Pipeline for NMTK

**Contract-Driven Development + Property-Based Testing** — the best of
Opus (domain contracts + agent guardrails), GPT-5.4 (declarative manifests +
automation scripts), and Gemini (polyglot framework detection), merged into
one self-contained pipeline.

---

## How It Works

```
1. Human writes contracts + properties (THE SCIENCE)
2. module.json manifests describe each module's migration state
3. Scripts generate, preview, and publish GitHub issues (topologically sorted)
4. Jules/agent picks up issues and writes ALL code
5. CI verifies code against contracts + properties
6. Auto-merge if CI passes (unless protected files changed)
```

### The Pipeline Process

The Unified Dev Pipeline is designed to automate the migration of NMTK modules to a Contract-Driven Development (CDD) and Property-Based Testing (PBT) model.

1.  **State Audit**: The `scripts/audit_workflows.py` script scans all modules to identify existing CI/CD workflows and gaps relative to the CDD+PBT requirements.
2.  **Manifest Definition**: Each module has a `module.json` manifest that defines its migration roadmap, including specific GitHub issues to be created.
3.  **Issue Generation**: The `scripts/publish_github_issues.py` script reads these manifests and creates GitHub issues with topological sorting, ensuring dependencies are addressed first.
4.  **State Tracking**: Completion status is tracked in `.issue-state.json` files within each module's directory in `docs/unified-dev-pipeline/`. This prevents duplicate issue creation and provides a clear view of progress.
5.  **Automated Implementation**: Jules (or another agent) picks up the generated issues and implements the required contracts and property tests.
6.  **Continuous Verification**: CI workflows (`contract-verification.yml`, etc.) ensure that all new code complies with the defined Pydantic contracts and passes Hypothesis property tests before being merged.

---

## What Each Source Pipeline Contributed

| Source | Contribution |
|--------|-------------|
| **Opus** | All contract code (Pydantic v2), all property tests (Hypothesis), AGENTS.md + GUARDRAILS.md, protected-file auto-merge, contract-verification.yml, PR/issue templates, golden baseline scripts |
| **GPT-5.4** | Declarative `module.json` manifests, `publish_github_issues.py` (topological sort + `.issue-state.json`), `audit_workflows.py`, `run_contract_ci.py`, reusable `workflow_call` CI template |
| **Gemini** | Framework-agnostic validation (Python Poetry / pip / Flutter auto-detection) |

---

## Directory Structure

```
unified-dev-pipeline/
├── README.md                          ← You are here
│
├── scripts/
│   ├── publish_github_issues.py       ← Publish issues with dependency-aware ordering
│   ├── generate_issue_previews.py     ← Preview issues locally as markdown
│   ├── audit_workflows.py             ← Print module workflow gap matrix
│   ├── run_contract_ci.py             ← Execute CI phases from module.json
│   ├── verify-contracts-local.sh      ← Local verification (polyglot: Python + Dart)
│   └── generate-golden-baselines.sh   ← Create simulation regression baselines
│
├── .github/
│   ├── workflows/
│   │   ├── contract-verification.yml  ← Per-module contract + PBT CI (paths-filter)
│   │   ├── cdd-pbt-module-ci.yml      ← Reusable workflow_call template
│   │   ├── auto-merge-agents.yml      ← Protected-file aware auto-merge
│   │   ├── ci-failure-fix-agent.yml   ← Structured log handoff to Jules
│   │   └── issue-sync.yml            ← workflow_dispatch issue generation
│   ├── PULL_REQUEST_TEMPLATE.md       ← Contract checklist
│   └── ISSUE_TEMPLATE/
│       ├── contract-migration.yml     ← Issue template for contracts/properties
│       └── feature-with-contracts.yml ← Feature template requiring contracts
│
├── neurocnl/
│   ├── module.json                    ← Declarative migration manifest
│   ├── AGENTS.md                      ← Agent behavioral rules
│   ├── GUARDRAILS.md                  ← Known failure patterns
│   ├── contracts/                     ← Pydantic v2 domain contracts
│   │   ├── __init__.py
│   │   ├── neuron_params.py
│   │   ├── hardware_export.py
│   │   └── pipeline_contracts.py
│   └── properties/
│       └── test_physics_properties.py ← 12 Hypothesis property tests
│
├── neuro-dream-hand/
│   ├── module.json
│   ├── AGENTS.md
│   ├── GUARDRAILS.md
│   ├── contracts/
│   │   └── hardware_contracts.py
│   └── properties/
│       └── test_hitl_properties.py    ← 11 property tests
│
├── neurosim/
│   ├── module.json
│   └── contracts/
│       └── design_contracts.py
│
├── neurosense/
│   ├── module.json
│   ├── contracts/
│   │   └── signal_contracts.py
│   └── properties/
│       └── test_encoding_properties.py
│
├── neurochip/
│   ├── module.json
│   ├── contracts/
│   │   └── deployment_contracts.py
│   └── properties/
│       └── test_deployment_properties.py
│
├── neurobench/
│   ├── module.json
│   └── contracts/
│       └── benchmark_contracts.py
│
└── neurohub/
    ├── module.json
    └── contracts/
        └── orchestration_contracts.py
```

---

## Quick Start

### Step 0: Prerequisites
```bash
gh auth status          # GitHub CLI authenticated
cd NeuroMorphicToolKit  # repo root
```

### Step 1: Audit Current State
```bash
python docs/unified-dev-pipeline/scripts/audit_workflows.py
```

### Step 2: Preview Issues Locally
```bash
python docs/unified-dev-pipeline/scripts/generate_issue_previews.py
```

### Step 3: Publish Issues to GitHub (topologically sorted)
```bash
python docs/unified-dev-pipeline/scripts/publish_github_issues.py --execute
# Or dry-run first:
python docs/unified-dev-pipeline/scripts/publish_github_issues.py
```

### Step 4: Install CI Workflows
```bash
cp docs/unified-dev-pipeline/.github/workflows/*.yml .github/workflows/
cp docs/unified-dev-pipeline/.github/PULL_REQUEST_TEMPLATE.md .github/
mkdir -p .github/ISSUE_TEMPLATE
cp docs/unified-dev-pipeline/.github/ISSUE_TEMPLATE/*.yml .github/ISSUE_TEMPLATE/
git add .github/ && git commit -m "ci: add unified CDD+PBT workflows and templates"
git push
```

### Step 5: Install Contracts + Properties (Jules does this)
Jules picks up published issues and copies contracts into modules:
```bash
cp docs/unified-dev-pipeline/{module}/contracts/*.py {Module}/contracts/
cp docs/unified-dev-pipeline/{module}/properties/*.py {Module}/properties/
```

### Step 6: Verify Locally
```bash
bash docs/unified-dev-pipeline/scripts/verify-contracts-local.sh           # all
bash docs/unified-dev-pipeline/scripts/verify-contracts-local.sh neurocnl  # one
```

### Step 7: Generate Golden Baselines (after neurocnl is working)
```bash
bash docs/unified-dev-pipeline/scripts/generate-golden-baselines.sh
```

---

## CI/CD Architecture

```
PR opened or pushed
    │
    ├──► ci.yml (existing, patched)
    │    ├── detect-changes
    │    ├── test-neurocnl-backend (pytest, ruff, mypy)
    │    ├── test-neurosim, test-neurochip, ...
    │    ├── test-neurobench (flutter analyze + test)
    │    └── ci-passed (gate)
    │
    ├──► contract-verification.yml (paths-filter per module)
    │    ├── detect-changes
    │    ├── verify-neurocnl (mypy + contracts/ + properties/)
    │    ├── verify-neurodreamhand
    │    ├── verify-other-modules (matrix)
    │    └── contracts-passed (gate)
    │
    ├──► cdd-pbt-module-ci.yml (reusable workflow_call)
    │    └── Invoked by each module's CI with module_config + python_version
    │
    ├──► auto-merge-agents.yml
    │    ├── Check: jules/* or auto/* branch?
    │    ├── Check: protected files changed?
    │    ├── Wait for CI + contracts-passed
    │    ├── No protected files → auto-approve + squash merge
    │    └── Protected files → request human review + label
    │
    └──► ci-failure-fix-agent.yml
         ├── Trigger: CI or CDD-PBT workflow fails
         ├── Download structured log URL
         └── Invoke Jules with full failure context
```

**Required status checks for branch protection:**
- `ci-passed`
- `contracts-passed`

---

## Module Migration State

Run `python scripts/audit_workflows.py` for an up-to-date matrix, or see:

| Module | Contracts | Properties | AGENTS.md | CI Status |
|--------|-----------|------------|-----------|-----------|
| neurocnl | 4 files (18+ invariants) | 2 properties | Yes | Full CI, needs CDD gate |
| Neuro-Dream-Hand | 2 files (8+ contracts) | 1 property | Yes | Full CI, needs CDD gate |
| Neurosim | 1 file | 1 property | No | Full CI, needs CDD gate |
| Neurosense | 5 files | 2 properties | No | Full CI, needs CDD gate |
| Neurochip | 5 files | 3 properties | No | Full CI, needs CDD gate |
| Neurobench | 4 files | 4 properties | No | Full CI, needs CDD gate |
| Neurohub | 4 files | 4 properties | No | Full CI, needs CDD gate |

---

## Issue Dependency Graph

```
Phase 1 — Foundation (independent, can run in parallel):
  CDD-001  Add hypothesis + pydantic deps to all modules
  CDD-002  neurocnl contracts
  CDD-003  neurocnl property tests              (depends on CDD-002)
  CDD-004  Neuro-Dream-Hand contracts
  CDD-005  Neuro-Dream-Hand property tests       (depends on CDD-004)
  CDD-006  AGENTS.md + GUARDRAILS.md

Phase 2 — Expansion (depends on Phase 1):
  CDD-007  Remaining module contracts            (depends on CDD-001)
  CDD-008  Remaining module property tests       (depends on CDD-007)

Phase 3 — CI/CD (CDD-009 is independent, rest depend on Phase 1):
  CDD-009  Fix broken CI workflow
  CDD-010  Contract verification workflow        (depends on CDD-002, CDD-004)
  CDD-011  Fix auto-merge                        (depends on CDD-009)
  CDD-012  PR template
  CDD-013  Issue templates
```

---

## How Contracts Map to Specs

| Module | Spec File | Contract File | Key Constraints |
|--------|-----------|---------------|-----------------|
| neurocnl | `neuromorphic_spec_plan.md` | `neuron_params.py`, `hardware_export.py`, `pipeline_contracts.py` | 18 physics invariants, Loihi/SpiNNaker/Teensy limits |
| Neuro-Dream-Hand | `SPEC.md` | `hardware_contracts.py` | Serial protocol, EMG Ganglion limits, fault injection, drop-test gap |
| Neurosim | `neurosim_spec.md` | `design_contracts.py` | Preview ≤500ms, sweep max 20 steps, canvas validity |
| Neurosense | `neurosense_spec.md` | `signal_contracts.py` | Display <50ms, pipeline <100ms, encoding methods |
| Neurochip | `neurochip_spec.md` | `deployment_contracts.py` | Quantization 2-32 bit, fault max 30%, latency ordering |
| Neurobench | `neurobench_spec.md` | `benchmark_contracts.py` | Regression threshold, N≥5 seeds, robustness curves |
| Neurohub | `neurohub_spec.md` | `orchestration_contracts.py` | Port assignments, health checks, workflow steps |
