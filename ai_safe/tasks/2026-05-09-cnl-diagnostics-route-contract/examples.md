# Examples And Acceptance Tests

## Input/Output Examples

### Example 1: Parse Route Preserves Structured Diagnostics

Input:

```python
spec = "This is not valid CNL"
```

Expected behavior:

```python
{
    "code": "unsupported_sentence_family",
    "message": "The sentence does not match any supported CNL grammar.",
    "hint": "...",
    "examples": [...],
    "line": 1,
    "raw": "This is not valid CNL",
    "source": "parser",
}
```

The exact `hint` text and examples may mirror the parser contract, but the route must not strip them away.

### Example 2: Deploy-Oriented Parse Failure Returns Structured Items

Input:

```python
parse_results = [
    {
        "line": 1,
        "raw": "This is not valid CNL",
        "valid": False,
        "error_detail": {
            "code": "unsupported_sentence_family",
            "message": "The sentence does not match any supported CNL grammar.",
            "hint": "This sentence family is not in the supported CNL grammar.",
            "examples": ["The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"],
            "line": 1,
            "raw": "This is not valid CNL",
            "source": "parser",
        },
    }
]
```

Expected behavior:

```python
HTTPException(
    status_code=422,
    detail={
        "error": "parse_failed",
        "items": [
            {
                "code": "unsupported_sentence_family",
                "message": "The sentence does not match any supported CNL grammar.",
                "hint": "...",
                "examples": [...],
                "line": 1,
                "raw": "This is not valid CNL",
                "source": "parser",
            }
        ],
    },
)
```

### Example 3: Lowering Failure Keeps Category And Messages Stable

Input:

```python
try:
    ...
except LoweringError as exc:
    ...
```

Expected behavior:

```python
HTTPException(
    status_code=422,
    detail={
        "error": "lowering_failed",
        "messages": ["..."],
    },
)
```

This packet does not require adding synthetic hints to lowering errors if no honest hint is available yet.

## Edge Cases

- Multiple parse failures in a multiline spec
- Routes that currently flatten failures differently
- Validation failures that are already structured should stay structured
- Non-parse failures must not be mislabeled as parse failures

## Acceptance Checklist

- Parse diagnostics remain structured end-to-end in the targeted routes
- Existing fail-closed status codes remain intact
- Error categories stay distinguishable
- The patch does not redesign unrelated success-path behavior
