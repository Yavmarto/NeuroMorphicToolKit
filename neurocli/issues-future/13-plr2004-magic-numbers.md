# Fix `PLR2004`: Extract Magic Numbers into Named Constants

**Labels:** `linting`, `readability`, `phase-5`, `needs-review`

> ⚠️ **Review constant names before merging.** Poorly named constants are worse than magic numbers.

## Problem
Numeric literals are used directly in logic (`PLR2004`) instead of named constants, making intent unclear.

## Task
For each flagged magic number, extract it into an `ALL_CAPS` module-level constant with a name that explains its *meaning*, not just its value:

```python
# Before
if retries > 3:
    raise TimeoutError()

# After
MAX_RETRY_ATTEMPTS = 3

if retries > MAX_RETRY_ATTEMPTS:
    raise TimeoutError()
```

**Naming checklist before committing:**
- [ ] Does the name describe *why* this number matters, not just what it is?
- [ ] Would another developer understand it without reading surrounding code?

## Scope
Extract constants into the same module where the magic number is used. Do not create a shared constants file unless one already exists.

## Verification
Zero `PLR2004` errors. All tests pass.
