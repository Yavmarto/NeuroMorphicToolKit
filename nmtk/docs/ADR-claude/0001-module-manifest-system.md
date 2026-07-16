# ADR 0001: Module Manifest System

## Status
Accepted

## Context
The desktop launcher must manage 6+ backend services with different ports, directory structures, dependency requirements, and hardware prerequisites. Auto-discovery of services is unreliable across development and production environments.

## Decision
Define each module as a `Module` data class with 20+ fields (id, name, port, uvicornTarget, sourcePath, localDeps, version, requiresMuJoCo, etc.). The `ModuleProvider` manages module lifecycle states through an 8-state machine (notInstalled, installing, installed, starting, running, stopping, error, updating) with health polling via HTTP pings to each module's API.

## Consequences
- **Positive:** Explicit manifest provides a single source of truth for module configuration; the state machine prevents invalid transitions (e.g., starting a module that is not installed).
- **Negative:** Manifest must be manually updated when modules are added or reconfigured; 20+ fields per module increases the risk of stale or inconsistent configuration.

## Status Update (2026-07-16 audit)

Minor correction: this ADR describes an "8-state machine." Reading `nmtk/neuro_toolkit/lib/models/module.dart`'s `ModuleStatus` enum confirms it actually has 9 states: `notInstalled, installing, installed, starting, running, stopping, error, degraded, updating`. The ADR's list omits `degraded`, which sits between `error` and `updating`.
