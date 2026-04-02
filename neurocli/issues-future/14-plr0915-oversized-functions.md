# Fix `PLR0915`: Break Up Oversized Functions

**Labels:** `linting`, `refactoring`, `phase-5`, `needs-review`

> ⚠️ **High architectural impact.** Do one function per PR and get a review before merging.

## Problem
Functions flagged by `PLR0915` exceed the maximum allowed number of statements, making them hard to read, test, and maintain.

## Task
For each flagged function, refactor by extracting logical sub-steps into smaller, well-named helper functions:

1. Read the function and identify natural groupings of statements (e.g. "validate inputs", "fetch data", "transform result", "write output").
2. Extract each group into a private helper (prefix with `_`).
3. Replace the original statements with a call to the helper.

```python
# Before
def process_order(order):
    # 60 lines of mixed validation, DB calls, and formatting

# After
def process_order(order):
    _validate_order(order)
    record = _fetch_order_record(order.id)
    return _format_response(record)
```

## Checklist before opening PR
- [ ] Each helper has a single, clear responsibility
- [ ] Unit tests cover the extracted helpers independently
- [ ] The original function's public behaviour is unchanged

## Verification
Zero `PLR0915` errors for the refactored function. All related tests pass.
