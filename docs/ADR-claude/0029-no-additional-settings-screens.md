# ADR-0029: No Additional Settings Screens

**Status:** Accepted  
**Date:** 2026-07-09

## Context

A suite-wide Flutter frontend audit (using the `nmtk-flutter-review` skill) inventoried every module's UI, including a review of what currently exists in Settings. The Launcher (`nmtk/neuro_toolkit`) has a single `SettingsScreen` covering: Theme (System/Light/Dark), the launcher control-API server address, a link into Setup & environments, and Logging (log level, crash logs, server logs). No other module (`Neurosense`, `neurocnl`, `Neurohub`, `Neurobench`, `Neurochip`) has its own settings screen, and there is no separate unified "suite settings" hub beyond this one Launcher screen.

The question of whether to add per-module settings screens, or a dedicated suite-wide settings hub distinct from the Launcher's, came up during this review.

## Decision

We will not build any additional settings screens at this time — neither per-module settings UIs nor a separate suite-wide settings hub. The existing Launcher `SettingsScreen` remains the suite's sole settings surface. No module currently has configuration needs that justify its own settings screen.

## Rationale

- **No demonstrated need:** nothing in the current modules requires user-facing configuration that isn't already covered by the Launcher's Theme/Server/Setup/Logging sections.
- **End-user convenience (AGENTS.md top priority):** one settings surface is easier to find and reason about than one per module; every additional screen is another place a user has to know to look.
- **Consistent with the suite's control-plane direction (ADR-0023):** the Launcher is already the suite's sole control plane; concentrating settings there rather than fragmenting them across modules follows the same logic.
- **Avoids speculative UI:** building settings screens ahead of an actual requirement risks dead/unused UI surface (the kind of speculative-generality this codebase's guidelines explicitly discourage).

## Consequences

- Any new user-configurable option should be added to the existing Launcher `SettingsScreen` (or, per AGENTS.md's convenience principle, be auto-detected/defaulted so it needs no UI at all) rather than prompting a new settings screen in a module.
- If a module later surfaces a genuinely module-specific configuration need that doesn't fit the shared screen, that should be brought as a new decision superseding this ADR — not built ad hoc.

## Status Update (2026-07-16 audit)

Low severity. `Neurohub/frontend/lib/screens/settings_screen.dart` exists as a stub `Scaffold` but is not routed or referenced anywhere in Neurohub's app code (a repo grep finds only its own test file, no route or navigation reference) — orphaned dead code rather than an active contradiction of this decision. No action needed beyond noting it for future cleanup.
