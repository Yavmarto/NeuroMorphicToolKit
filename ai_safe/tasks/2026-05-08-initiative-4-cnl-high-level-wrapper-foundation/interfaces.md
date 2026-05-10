# Interfaces

Document only signatures, types, schemas, and stub bodies here.

## Target Surface 1: `high_level_api.py`

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class CompileSummary:
    ok: bool
    overall_pass: bool
    error: str | None
    backend_support: dict[str, Any] | None
    validation_summary: dict[str, Any] | None


@dataclass(frozen=True, slots=True)
class EvaluateSummary:
    ok: bool
    overall_pass: bool
    error: str | None
    simulation_summary: dict[str, Any] | None
    assertion_summary: dict[str, Any] | None


class NeuroCnlFacade:
    def compile(self, spec_path: str) -> CompileSummary:
        """Run the unified pipeline for a compile-oriented flow."""
        raise NotImplementedError

    def evaluate(self, spec_path: str) -> EvaluateSummary:
        """Run the unified pipeline for an evaluation-oriented flow."""
        raise NotImplementedError
```

## Target Surface 2: underlying pipeline entrypoint

Assume there is an existing pipeline function that returns a dict-like or object-like result containing at least:

- success or pass/fail information
- optional error text
- optional backend-support information
- optional validation summary
- optional simulation summary

The wrapper should adapt that output, not replace it semantically.

## Target Surface 3: tests or example-oriented checks

Expected test themes:

- compile wrapper delegates to the pipeline
- evaluate wrapper delegates to the pipeline
- failure in the pipeline becomes failure in the wrapper summary
- convenience shaping preserves the truth of the underlying result

# Reference Notes

- This slice is about wrapper ergonomics, not new execution semantics.
- The exact internal pipeline return type may vary; the wrapper may use a small normalization helper if needed.
