# docs

`docs` is the shared documentation and governance layer for the whole NMTK workspace.

## What It Should Do

Based on the files already in this folder, `docs` is not a single manual or API reference. It serves three different roles:

1. user and operator documentation
2. engineering process and CI/CD documentation
3. agent/pipeline governance for automated development workflows

## What Is Already Here

### User and operations docs

These files describe how to use, deploy, and troubleshoot the suite:

- [`user/installation.md`](./user/installation.md)
- [`user/troubleshooting.md`](./user/troubleshooting.md)
- [`PRODUCTION_PLAYBOOK.md`](./PRODUCTION_PLAYBOOK.md)
- [`CI_OVERVIEW.md`](./CI_OVERVIEW.md)

### Audit and status artifacts

The archive files under [`archive/`](./archive/) show that this folder is also the canonical home for cross-repo status audits and historical readiness reports.

### Agentic development pipeline

The strongest signal in this folder is [`unified-dev-pipeline/README.md`](./unified-dev-pipeline/README.md), which describes a full contract-driven and property-based migration pipeline for all modules. That subfolder includes:

- per-module `module.json` manifests
- `.issue-state.json` tracking
- issue generation scripts
- workflow-audit scripts
- verification scripts
- agent guardrails and templates

This makes `docs` the place where the team defines how the repository should evolve, not just how it should be used.

## Why This Fits The Rest Of NMTK

NMTK is a multi-module workspace with:

- several Python and Flutter submodules
- a root Docker Compose stack
- agent-driven workflows
- recurring audit reports

Because of that, the root repo needs a place for cross-cutting knowledge that does not belong to any one product module. This folder fills that role.

In practice, `docs` should act as the shared source for:

- onboarding
- deployment and recovery guidance
- CI/CD inventory
- audit prompts and reporting conventions
- contract-migration governance
- future architecture documentation

## Current State

This folder is active, but uneven.

What is clearly established:

- production and troubleshooting docs exist
- audit/reporting conventions exist
- a substantial unified development pipeline already exists

What still looks incomplete:

- there is no single root overview README for the folder until now
- there is overlap between active pipeline docs and archived pipeline variants
- some historical docs appear duplicated or superseded

## Practical Mental Model

If the product modules are the "apps," then `docs` is the workspace handbook plus engineering control plane.

- Users should land here for installation, troubleshooting, and deployment guidance.
- Contributors should land here for CI, process, and migration rules.
- Agents should land here for prompts, manifests, and automation contracts.
