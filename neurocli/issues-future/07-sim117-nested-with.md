# Fix `SIM117`: Collapse Nested `with` Statements

**Labels:** `linting`, `modernization`, `phase-3`

## Problem
Nested `with` blocks are used where a single `with` statement with multiple context managers would be simpler and more readable.

## Task
Collapse all nested `with` statements into a single statement:

```python
# Before
with open(src) as f:
    with open(dst, "w") as g:
        g.write(f.read())

# After
with open(src) as f, open(dst, "w") as g:
    g.write(f.read())
```

## Scope
Only the `with` statement pairs flagged by `SIM117`. Do not restructure any surrounding logic.

## Verification
Zero `SIM117` errors from the linter. All tests pass.
