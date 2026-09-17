# ADR 0004: File-Based Storage

## Status
Accepted

## Context
Neurochip manages two categories of persistent data: hardware target definitions (version-controlled configuration) and deployment records (runtime state). Each has different consistency and querying requirements, and introducing a full database server would add unnecessary infrastructure complexity.

## Decision
Store hardware target profiles as read-only JSON files in `neurochip/targets/` (version-controlled with the codebase) and deployment records in SQLite via `deployment_store.py` with `CREATE TABLE IF NOT EXISTS` auto-initialization. This dual-storage strategy matches the lifecycle of each data type.

## Consequences
- **Positive:** Target profiles are diffable and reviewable in PRs; SQLite handles concurrent deployment writes reliably without external database infrastructure.
- **Negative:** No schema migration tooling for the SQLite store; JSON files lack referential integrity checks against the database.
