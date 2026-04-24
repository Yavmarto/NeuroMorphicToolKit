# ADR 0017: Desktop Shell Adapter Contract

## Status
Accepted

## Context

The desktop migration plan depends on package-based native module integration
instead of nested desktop applications. The suite also needs to support a mixed
migration period where some modules remain web-embedded while others move toward
desktop-native surfaces.

Without a shared adapter contract, each module lane would make local decisions
about:

- how a module registers with the shell
- how deep links are expressed
- how restoration payloads are persisted
- how capability degradation is reported

That drift would block safe parallelization and make `nmtk`, `nmtk_ui_core`,
and `neurocli` consume inconsistent module behaviors.

The launcher already distinguishes required failures from optional capability
degradation. That terminology is present in `nmtk` and related tests today, so
the desktop migration must reuse it rather than introduce a second status model.

## Decision

Adopt a single root shell adapter contract for package-based module entrypoints.

The contract standardizes:

- one adapter package per module repo
- adapter package naming as `<module>_shell_adapter`
- a canonical `ShellModuleAdapter` registration boundary
- module-owned `ModuleDeepLink` targets
- adapter-owned `ShellRestorationSnapshot` payloads
- `CapabilityReport` output using shell-facing states including
  `ready`, `preflight_failed`, and `degraded_optional_capability`

The root contract is language-agnostic and lives in root docs so both
full-workspace and single-repo agents can consume it.

The shell contract is a prerequisite gate for module migration fan-out. Module
lanes implement against it; they do not redefine it locally.

## Consequences

- **Positive:** Module lanes can build against one shared contract, which
  reduces cross-repo drift and makes single-repo cloud-agent briefs concrete.
- **Positive:** Deep-link, restoration, and degradation semantics are defined
  once and can be reused by `nmtk`, `nmtk_ui_core`, and future `neurocli`
  commands.
- **Positive:** Optional hardware/runtime gaps keep the existing launcher
  distinction between `preflight failed` and `degraded optional capability`.
- **Negative:** Adapter packages add another explicit compatibility surface that
  must be versioned and documented.
- **Negative:** Modules may need a temporary adapter wrapper around existing
  web-embedded fronts during migration instead of jumping directly to a fully
  native surface.

## Related Documents

- [Shell Adapter Contract And Package Conventions](../2026-04-24-shell-adapter-contract-and-package-conventions.md)
- [Desktop-Only Module Migration Subplans](../2026-04-24-desktop-module-migration-subplans.md)
- [Multi-Agent Desktop Migration Execution Map](../2026-04-24-multi-agent-desktop-migration-execution-map.md)

