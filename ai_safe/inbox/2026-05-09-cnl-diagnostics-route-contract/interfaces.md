# Interfaces

Document only signatures, types, schemas, and stub bodies here.

## Target Surface 1: Structured Parse Error Shape

```python
from typing import TypedDict


class ErrorDetail(TypedDict, total=False):
    code: str
    message: str
    hint: str
    examples: list[str]
    line: int
    raw: str
    source: str
    field: str
    value: float | int | str | list[int] | None
    lines: list[int]
    name: str
    reason: str
    check: str
    detail: str
    result: bool
    description: str
```

## Target Surface 2: Parse Result Producer

```python
class ParseError(Exception):
    detail: ErrorDetail


def parse_spec_text(spec_text: str) -> list[dict]:
    """
    Returns one dict per non-empty line with:
    - line
    - raw
    - parsed
    - valid
    - error
    - error_detail
    """
    raise NotImplementedError
```

## Target Surface 3: Route-Level Error Builders

Representative route patterns today:

```python
from fastapi import HTTPException


def handle_parse_results(parse_results: list[dict]) -> None:
    parse_errors = [r["error_detail"] for r in parse_results if not r["valid"]]
    if parse_errors:
        msgs = [e["message"] for e in parse_errors if e is not None]
        raise HTTPException(
            status_code=422,
            detail={"error": "parse_failed", "messages": msgs},
        )


def handle_lowering_failure(exc: Exception) -> None:
    raise HTTPException(
        status_code=422,
        detail={"error": "lowering_failed", "messages": [str(exc)]},
    )
```

## Target Files

The intended implementation area is a narrow set of backend routes and shared helpers similar to:

- `backend/app/services/neurocnl_bridge.py`
- `backend/app/routers/generate.py`
- `backend/app/routers/export.py`
- `backend/app/routers/deploy.py`
- `backend/app/routers/simulate.py`
- optionally one shared helper module if that reduces repetition without broadening scope

# Reference Notes

- The parser already preserves better structure than the route layer.
- The strongest value in this slice is preserving structure rather than inventing new diagnostics.
- A small helper such as `build_parse_failure_detail(...)` or `build_cnl_error_payload(...)` is acceptable if it keeps route behavior consistent.

