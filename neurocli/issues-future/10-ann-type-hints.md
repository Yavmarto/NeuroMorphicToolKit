# Fix `ANN*`: Add Missing Type Hints

**Labels:** `linting`, `type-hints`, `phase-4`

## Problem
Multiple functions are missing type annotations, flagged across several `ANN` codes:

| Code | Missing annotation for |
|------|----------------------|
| `ANN001` | Regular function arguments |
| `ANN002` | `*args` |
| `ANN003` | `**kwargs` |
| `ANN202` | Return type of private functions |
| `ANN204` | Return type of `__init__` / `__eq__` etc. |

## Task
Analyze each flagged function and add the correct type hints by reading the function body and call sites for context:

```python
# Before
def process(items, **kwargs):
    ...

# After
def process(items: list[str], **kwargs: Any) -> None:
    ...
```

Common patterns:
- `__init__` always returns `-> None`
- `__eq__` always returns `-> bool`
- Use `Any` from `typing` when the type is genuinely dynamic

Ensure `from typing import Any` (or other needed imports) is present where used.

## Scope
Only the functions flagged by `ANN` codes. Do not add hints to unflagged functions.

## Verification
Zero `ANN001`, `ANN002`, `ANN003`, `ANN202`, `ANN204` errors.
