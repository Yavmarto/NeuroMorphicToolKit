# Workflow Diagnostic Summary Report

This document provides a high-level overview of all issues identified in the GitHub Actions workflows of the NeuroMorphicToolKit and its submodules.

## Issues by Category

| Category | File Count | Primary Issues | Avg. Difficulty |
| :--- | :--- | :--- | :--- |
| **Syntax Errors** | 2 | Missing `runs-on`, Misplaced `run` | Easy (1/10) |
| **Old Action Versions** | 1 | `checkout@v3`, `setup-python@v4` | Very Easy (1/10) |
| **Shellcheck Issues** | 6+ | Quoting, Subshell exit, Redirection | Easy (2/10) |
| **Expression/Context Errors** | 3 | Untrusted `head_ref`, Undefined properties | Medium (4/10) |
| **Runtime (act) Issues** | 4+ | Matrix evaluation (Invalid JSON), Missing stages | Medium (5/10) |

## Key Findings

> [!IMPORTANT]
> **Matrix Evaluation Failure** is the most critical runtime issue found. It currently blocks local testing of `unblocked-issues.yml` and likely affects those workflows in production if the dynamic matrix input is ever empty.

> [!WARNING]
> **Syntax Errors** in `Neuro-Dream-Hand` and `neurocnl` mean those specific workflows (`auto-merge-jules-prs.yml`) will **not execute at all** until the jobs are structured correctly.

## Documented Error Reports

Detailed reports for each category can be found in the `workflow-errors/` directory:

1. [Syntax Errors](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/workflow-errors/syntax-errors.md)
2. [Action Version Warnings](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/workflow-errors/action-version-warnings.md)
3. [Shellcheck Issues](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/workflow-errors/shellcheck-issues.md)
4. [Expression and Context Errors](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/workflow-errors/expression-and-context-errors.md)
5. [act Runtime and Dry-Run Errors](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/workflow-errors/act-runtime-errors.md)

## Next Steps

1. **Fix Syntax Errors**: Immediate fix for structural issues in automated merge workflows.
2. **Standardize JSON Handling**: Ensure all `fromJSON()` calls have a valid fallback string (e.g., `'[]'`).
3. **Upgrade Actions**: Minor version bumps to ensure long-term runner compatibility.
