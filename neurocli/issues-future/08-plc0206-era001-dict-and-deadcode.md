# Fix `PLC0206` / `ERA001`: Dict Iteration & Commented-Out Code

**Labels:** `linting`, `cleanup`, `phase-3`

## Problem
Two unrelated but equally mechanical issues:

- **`PLC0206`** — Iterating over `dict.keys()` and then indexing back into the dict, when `.items()` should be used instead.
- **`ERA001`** — Commented-out code left in the codebase.

## Tasks

### PLC0206 — Use `.items()` for dict iteration
```python
# Before
for key in my_dict.keys():
    value = my_dict[key]

# After
for key, value in my_dict.items():
```

### ERA001 — Delete commented-out code
Remove all blocks of code that are commented out and flagged by `ERA001`. If any commented block looks intentional (e.g. a `# TODO` or documented workaround), leave it and add `# noqa: ERA001` with a brief explanation.

## Verification
Zero `PLC0206` and `ERA001` errors from the linter.
