# Fix `NPY002`: Replace Legacy NumPy Random API

**Labels:** `linting`, `modernization`, `phase-3`

## Problem
`np.random.seed()` and related legacy `np.random.*` calls are deprecated in favour of NumPy's modern Generator API, which is reproducible, thread-safe, and more flexible.

## Task
Replace legacy calls with the `default_rng()` generator:

```python
# Before
np.random.seed(42)
values = np.random.uniform(0, 1, size=100)

# After
rng = np.random.default_rng(42)
values = rng.uniform(0, 1, size=100)
```

Declare the `rng` object at the narrowest appropriate scope (top of function, or module-level if shared).

## Scope
Only the call sites flagged by `NPY002`.

## Verification
Zero `NPY002` errors. Any tests that check for deterministic random output should still pass with the same seed value.
