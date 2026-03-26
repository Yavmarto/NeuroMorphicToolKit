# Create ARCHITECTURE.md

**Priority:** P3-Low
**Effort:** 1 day
**Labels:** documentation
**Scope:** Cross-cutting (root level)

## Problem

No single document describes the system architecture, inter-module dependencies, data flow, or communication patterns. Understanding how the 7 modules interact requires reading dozens of files.

## Acceptance Criteria

- [ ] ARCHITECTURE.md exists at root
- [ ] Describes launcher → backend → frontend architecture
- [ ] Documents API contracts between modules
- [ ] Shared libraries and their consumers
- [ ] Module lifecycle (install → start → health → stop)
- [ ] Data flow diagram (CNL spec → simulation → benchmark → deploy)
- [ ] Inter-module communication patterns (Neurohub polling, etc.)

## Notes

Maps to POC-100-TASKS.md T5-4.
