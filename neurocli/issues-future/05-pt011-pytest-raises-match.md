# Fix `PT011`: Add `match` to Broad `pytest.raises` Calls

**Labels:** `linting`, `testing`, `phase-2`

## Problem
`pytest.raises(ValueError)` without a `match` parameter will pass for *any* `ValueError`, potentially hiding a different error being raised for the wrong reason.

## Task
For every `PT011` error in test files, add a `match` parameter with a substring of the expected error message:

```python
# Before
with pytest.raises(ValueError):
    do_thing()

# After
with pytest.raises(ValueError, match="expected substring"):
    do_thing()
```

Read the surrounding test context to choose an appropriate match string.

## Scope
Test files only. No production code changes.

## Verification
Zero `PT011` errors. All updated tests still pass.
