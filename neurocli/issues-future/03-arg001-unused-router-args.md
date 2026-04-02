# Fix `ARG001`: Unused Arguments in FastAPI Routers

**Labels:** `linting`, `fastapi`, `phase-2`

## Problem
FastAPI rate-limiter dependencies require parameters like `request: Request` or `response: Response` in the function signature, but the arguments are never referenced in the body. The linter flags these as unused.

## Task
In all FastAPI router files, prefix the intentionally-unused arguments with an underscore:

```python
# Before
async def my_endpoint(request: Request):

# After
async def my_endpoint(_request: Request):
```

## Scope
Router files only. Do not change any business logic or argument usage.

## Verification
Zero `ARG001` errors in router files. All existing route tests pass.
