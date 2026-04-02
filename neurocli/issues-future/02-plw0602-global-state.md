# Refactor `PLW0602`/`PLW0603`: Remove Global State in `components.py`

**Labels:** `bug`, `architecture`, `phase-1`

## Problem
`components.py` uses the `global` keyword to manage `_component_cache` and `_observer`. This pattern makes state hard to reason about and test.

## Task
Refactor the global variable usage in `components.py` by replacing the `global` keyword pattern with **one** of:

- A module-level dictionary that is mutated in place (no `global` declaration needed)
- A simple Singleton class that owns the state

## Scope
Changes are isolated to `components.py`. No other files should require modification.

## Verification
Zero `PLW0602` and `PLW0603` errors from the linter. Existing tests for `components.py` must still pass.
