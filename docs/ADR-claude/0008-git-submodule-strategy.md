# ADR 0008: Git Submodule Strategy

## Status
Accepted

## Context
The NMTK toolkit comprises 7 independently-developed modules (neurocnl, Neurosim, Neurochip, Neurobench, Neurosense, Neurohub, Neuro-Dream-Hand) plus shared infrastructure (nmtk, nmtk_ui_core, neurocli). Each module has its own repository for independent CI, issue tracking, and release cycles, but the desktop launcher needs all modules present for a full build.

## Decision
Use git submodules to compose the monorepo, with `.gitmodules` referencing sibling repositories (`../neurocnl.git`, etc.). The `scripts/git/push-all.sh` script orchestrates atomic commits across all submodules. CI initializes submodules with `git submodule update --init || true` to tolerate missing submodules during partial builds. `scripts/git/pull-all.sh` synchronizes all submodules to their latest commits.

## Consequences
- **Positive:** Each module retains its own git history, CI pipelines, and release cycle; submodule pinning ensures the parent repo always references a known-good commit of each module.
- **Negative:** Submodule workflows are notoriously complex for contributors (detached HEAD, sync issues); the `|| true` CI fallback silently masks initialization failures.

## Public snapshot follow-up (CEL-347)

The public repository is a flat, allowlisted snapshot with no submodule history, so
the per-module remotes are not published. `neurocnl`, `Neurochip`, `Neurobench`,
`Neurosense`, and `Neurohub` therefore carry an empty `remoteUrl` in
`nmtk/neuro_toolkit/assets/modules.json`.

An empty `remoteUrl` is a supported state, not an error:

- `launcher_control.module_registry._resolve_remote_module_version` returns
  `None` for a missing or blank URL.
- `UpdateService.checkForModuleUpdate` returns `null` before any network call.
- A remote that is absent, unreachable, or HTTP 404 degrades to "no update"
  instead of failing. The lazily-cached `remoteVersion` keeps its last known
  value, so an offline consumer sees no spurious downgrade.

Modules ship inside the suite snapshot and update with suite releases. To make
per-module update checks work again, publish the module repository publicly and
set its `remoteUrl`; the launcher picks it up on the next manifest read.
