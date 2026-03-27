# CI/CD Workflow Overview

This document provides an inventory and description of the active GitHub Actions workflows in the NeuroMorphicToolkit repository.

## Core Workflows

- **`ci.yml`**: The primary CI pipeline. Detects changes across all modules and runs tests, linting, and type checking for affected components (both backends and frontends).
- **`contract-verification.yml`**: Runs Contract-Driven Development (CDD) and Property-Based Testing (PBT) verification using Pydantic and Hypothesis.
- **`integration-test.yml`**: Spins up all HTTP modules via Docker to verify inter-module communication and health.
- **`health-check.yml`**: Validates that all modules expose a standard `/health` endpoint and audits API contract consistency.

## Agent Orchestration (Jules)

- **`auto-merge-agents.yml`**: Automatically merges PRs from Jules/agent branches if CI passes and no protected files (contracts, workflows, etc.) are modified.
- **`ci-failure-fix-agent.yml`**: Triggered when CI fails. It collects structured failure logs and invokes Jules to attempt an automated fix.
- **`bug-fixer.yml`**: Invoked when an issue is labeled as `bug`. Spawns Jules to diagnose and fix the reported issue.
- **`feature-builder.yml`**: Invoked when an issue is labeled as `feature` or `agent`. Spawns Jules to implement the requested capability.
- **`scaffold-module.yml`**: Manual workflow to have Jules generate a new module skeleton following NMTK conventions.
- **`unblocked-issues.yml`**: Detects when an issue's dependencies are resolved and triggers Jules to begin implementation.
- **`merge-conflict-resolver.yml`**: Triggered by the `merge-conflict` label or on push to `main` to have Jules resolve conflicts in agent-owned PRs.
- **`guardrails-updater.yml`**: Analyzes rejected agent PRs to extract lessons and update `GUARDRAILS.md`.

## Management & Automation

- **`idle-capacity-triage.yml`**: Periodically triages unlabeled issues and assigns them to the agent queue if capacity is available.
- **`morning-standup.yml`**: Posts a daily morning summary of the agent's task queue and work-in-flight to the standup log.
- **`eod-report.yml`**: Posts a daily end-of-day summary of merged PRs, failures, and triage activity.
- **`pr-labeler.yml`**: Automatically applies module-specific labels to PRs based on changed file paths.
- **`submodule-sync.yml`**: Periodically checks for updates in submodule `dev` branches and opens PRs to sync the parent repository.
- **`release-promote.yml`**: Manual workflow to promote `dev` branches to `main` across the parent repo and all submodules, including tagging.
- **`stale-branches.yml`**: Weekly cleanup of merged `jules/*` and `auto/*` branches.
- **`issue-sync.yml`**: Manual workflow to generate and sync CDD-PBT migration issues from module manifests.

## Reusable Workflows

- **`cdd-pbt-module-ci.yml`**: Standardized template for module-level baseline and migration CI.
- **`sdd-context-bridge.yml`**: Collects SPEC, AGENTS, and GUARDRAILS context for injection into agent prompts.
- **`reusable-bug-fixer.yml`**: Reusable logic for the bug-fixing agent.
- **`reusable-feature-builder.yml`**: Reusable logic for the feature-building agent.
- **`reusable-unblocked-issues.yml`**: Reusable logic for processing unblocked issues.
