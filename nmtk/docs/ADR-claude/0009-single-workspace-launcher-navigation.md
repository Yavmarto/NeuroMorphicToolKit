# ADR 0009: Single-Workspace Launcher Navigation

## Status
Accepted

## Supersedes
- ADR 0003: GoRouter Shell Routes
- The router-construction decision in ADR 0006: Riverpod Launcher State Management

## Context
The launcher now presents one persistent workspace. Module selection, module
sessions, server setup, and cross-module handoffs are already owned by typed
Riverpod state or local modal callbacks. The previous GoRouter table only
translated launcher paths back into that state; the app has no registered
desktop deep-link entrypoint that requires those paths.

NeuroCNL remains a nested application with its own Studio and NeuroSim canvas
locations. This decision applies only to the outer launcher.

## Decision
Mount `LauncherAppHost` directly through `MaterialApp.home`. The host owns the
startup server-setup prompt and launcher-update dialog, and always keeps
`ToolViewScreen` mounted as the base surface.

The wide launcher intentionally uses that workspace surface without an outer
`NmtkDesktopScaffold`, top bar, or navigation rail. Shared shell widgets used
by narrow layouts still receive `NmtkShellMode.command` explicitly; audits
must treat the chrome-free wide host as this ADR's deliberate exception.

Use `launcherNavigationProvider` for command-palette and module-picker intents.
The provider emits typed one-shot requests to open a module, reload the
workspace, or invoke a shell action; `ToolViewScreen` resolves those requests
against the same manifest and workspace state used by visible navigation.
Server-selection actions open the existing adaptive setup modal directly.

Legacy launcher URL aliases are removed. NeuroCNL's internal GoRouter and
module handoff contracts are unchanged.

## Consequences
- The launcher has one application surface and one navigation state model.
- Adding an outer desktop shell would duplicate navigation and violate this
  single-surface decision.
- Module commands no longer rebuild the outer application to select a module.
- Tests assert visible workspace behavior instead of synthetic route paths.
- Old launcher-only paths such as `/module/neurobench` and `/environments` are
  no longer addressable; neither had a registered desktop deep-link entrypoint.
- `go_router` remains in the dependency graph through NeuroCNL, but the launcher
  package no longer declares or imports it directly.
