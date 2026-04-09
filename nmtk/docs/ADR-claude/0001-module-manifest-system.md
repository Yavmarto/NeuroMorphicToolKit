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
