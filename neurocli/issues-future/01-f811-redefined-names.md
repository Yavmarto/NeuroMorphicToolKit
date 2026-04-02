# Fix `F811`: Redefinition of Unused Imported Names

**Labels:** `bug`, `linting`, `phase-1`

## Problem
Names like `SweepRequest` or `ValidationResult` are imported at the top of a file and then redefined as a new class further down. This causes a runtime shadow and makes the import dead code.

## Task
Find all `F811` redefinition errors and resolve the naming conflicts using **one** of these strategies:

- Rename the local class definition to avoid the clash (e.g. prefix with the file's domain: `CanvasSweepRequest`)
- Remove the conflicting import if it is genuinely unused

## Verification
Running the linter should produce zero `F811` errors after this change. No other files should need to be touched.
