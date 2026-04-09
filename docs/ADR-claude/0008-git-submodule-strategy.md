# ADR 0008: Git Submodule Strategy

## Status
Accepted

## Context
The NMTK toolkit comprises 7 independently-developed modules (neurocnl, Neurosim, Neurochip, Neurobench, Neurosense, Neurohub, Neuro-Dream-Hand) plus shared infrastructure (nmtk, nmtk_ui_core, neurocli). Each module has its own repository for independent CI, issue tracking, and release cycles, but the desktop launcher needs all modules present for a full build.

## Decision
Use git submodules to compose the monorepo, with `.gitmodules` referencing sibling repositories (`../neurocnl.git`, etc.). The `push-all.sh` script orchestrates atomic commits across all submodules. CI initializes submodules with `git submodule update --init || true` to tolerate missing submodules during partial builds. `pull-all.sh` synchronizes all submodules to their latest commits.

## Consequences
- **Positive:** Each module retains its own git history, CI pipelines, and release cycle; submodule pinning ensures the parent repo always references a known-good commit of each module.
- **Negative:** Submodule workflows are notoriously complex for contributors (detached HEAD, sync issues); the `|| true` CI fallback silently masks initialization failures.
