# Fix `PLC0415`: Move Inline Imports to Top of File (Circular Import Aware)

**Labels:** `linting`, `imports`, `phase-5`, `needs-review`

> ⚠️ **Proceed carefully.** Moving imports can introduce circular import errors. Review each case individually before committing.

## Problem
Imports inside function bodies are flagged by `PLC0415`. While sometimes done intentionally to avoid circular imports, they should be at the module top level where possible.

## Task
For each `PLC0415` occurrence, evaluate whether moving the import is safe:

1. **If moving the import to the top does NOT cause a circular dependency** → move it.
2. **If moving it WOULD cause a circular import** → leave it in place and add a suppression comment:
   ```python
   from mymodule import MyClass  # noqa: PLC0415
   ```

## How to check for circular imports
After moving an import, run:
```bash
python -c "import <your_module>"
```
or run the full test suite. A circular import will raise an `ImportError` immediately.

## Scope
One file at a time. Do not batch these across files in a single PR.

## Verification
Zero `PLC0415` errors for any imports that were safely moved. App starts without `ImportError`.
