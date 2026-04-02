# Fix `D417`: Add Missing Parameter Descriptions to Docstrings

**Labels:** `linting`, `documentation`, `phase-4`

## Problem
Docstrings exist but are missing `Args:` entries for one or more parameters, as flagged by `D417`.

## Task
For each flagged function, add the missing parameter description(s) to the docstring's `Args` section:

```python
# Before
def create_user(name: str, role: str) -> User:
    """Create a new user.

    Args:
        name: The display name of the user.
    """

# After
def create_user(name: str, role: str) -> User:
    """Create a new user.

    Args:
        name: The display name of the user.
        role: The permission role assigned to the user.
    """
```

Infer the description from the argument name, type hint, and function body.

## Scope
Only the docstrings flagged by `D417`. Do not rewrite or reformat existing docstring content.

## Verification
Zero `D417` errors from the linter.
