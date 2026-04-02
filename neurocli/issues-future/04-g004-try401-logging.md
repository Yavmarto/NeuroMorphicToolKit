# Fix `G004` / `TRY401`: Logging Anti-Patterns

**Labels:** `linting`, `logging`, `phase-2`

## Problem
Two separate logging anti-patterns exist in the codebase:

- **`G004`** — f-strings inside `logger.*()` calls are evaluated eagerly even if the log level is disabled, wasting CPU.
- **`TRY401`** — passing the exception object as a string to `logger.exception()` is redundant; the method captures it automatically.

## Tasks

### G004 — Switch to lazy `%` formatting
```python
# Before
logger.info(f"Processing {item_id} for user {user}")

# After
logger.info("Processing %s for user %s", item_id, user)
```

### TRY401 — Remove redundant exception argument
```python
# Before
logger.exception(f"Failed to process: {e}")

# After
logger.exception("Failed to process")
```

## Scope
Logging call sites only. No logic changes.

## Verification
Zero `G004` and `TRY401` errors from the linter.
