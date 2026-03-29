# GPT-5.4 Dev Pipeline

This folder contains the migration tooling for moving the neuromorphic modules from
spec-only development to a contract-driven, property-tested, agent-executable
pipeline.

The migration flow is:

1. Read the current module specification.
2. Map the specification to contract targets and property targets.
3. Generate GitHub issue payloads that an agent runner such as Jules can pick up.
4. Publish those issues to GitHub with dependency links using `blocked-by: #NNN`.
5. Run baseline CI plus contract/property validation in a reusable workflow.
6. Enable agent PR auto-merge only after required checks pass.

## What Is Here

- `Neurobench/`, `Neurochip/`, `Neurohub/`, `Neurosense/`, `Neurosim/`, `neurocnl/`, `Neuro-Dream-Hand/`
  - Module manifests describing current specs, migration targets, workflow gaps, and issue plans.
- `scripts/generate_issue_previews.py`
  - Renders local markdown previews from the module manifests.
- `scripts/publish_github_issues.py`
  - Creates GitHub issues from the manifests and writes dependency-aware state files.
- `scripts/run_contract_ci.py`
  - Executes setup, baseline, and migration commands for a module from its manifest.
- `scripts/audit_workflows.py`
  - Prints the current workflow gap matrix from the manifests.
- `workflows/cdd-pbt-module-ci.yml`
  - Reusable workflow template for baseline plus CDD-PBT validation.
- `workflows/issue-sync.yml`
  - Manual workflow template for creating GitHub issues from manifests.
- `workflows/ci-failure-fix-agent.yml`
  - Improved CI failure handoff template for Jules.
- `workflows/auto-merge-agent-prs.yml`
  - Improved auto-merge template for `jules/*` pull requests.

## Usage

Generate local previews:

```bash
python Research-Spec-driven-development/gpt5.4-dev-pipeline/scripts/generate_issue_previews.py
```

Audit workflow gaps:

```bash
python Research-Spec-driven-development/gpt5.4-dev-pipeline/scripts/audit_workflows.py
```

Publish issues to GitHub for one module:

```bash
python Research-Spec-driven-development/gpt5.4-dev-pipeline/scripts/publish_github_issues.py \
  --module Neurosim \
  --execute
```

Run migration CI locally for one module:

```bash
python Research-Spec-driven-development/gpt5.4-dev-pipeline/scripts/run_contract_ci.py \
  --config Research-Spec-driven-development/gpt5.4-dev-pipeline/Neurosim/module.json \
  --phase all
```

## Current Workflow Findings Embedded In The Manifests

- `Neurosim` is missing the full Jules automation suite.
- `Neurohub` has `ci-failure-fix.yml` but no `ci.yml`.
- Auto-merge templates only react on PR open/reopen, which misses later readiness states.
- CI failure handoff does not pass structured context about failed logs into Jules.
- No module currently enforces property tests in CI.

The manifests and workflow templates in this folder are written to close those gaps.