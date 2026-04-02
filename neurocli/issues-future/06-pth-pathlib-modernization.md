# Fix `PTH107` / `PTH110`: Modernize `os.path` Calls to `pathlib`

**Labels:** `linting`, `modernization`, `phase-3`

## Problem
Legacy `os.path` calls are used where `pathlib.Path` equivalents are cleaner and more idiomatic in modern Python.

## Task
Replace the following patterns across the codebase:

| Old | New |
|-----|-----|
| `os.path.exists(p)` | `Path(p).exists()` |
| `os.remove(p)` | `Path(p).unlink()` |

Ensure `from pathlib import Path` is imported in any file that doesn't already have it.

## Scope
Only the specific call sites flagged by `PTH107` and `PTH110`. Do not refactor other `os.path` usages not covered by these rules.

## Verification
Zero `PTH107` and `PTH110` errors from the linter.
