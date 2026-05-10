# Examples And Acceptance Tests

## Input/Output Examples

### Example 1: Compile Wrapper Success

Input:

```python
facade = NeuroCnlFacade()
summary = facade.compile("example_spec.cnl")
```

Assume underlying pipeline success equivalent to:

```python
{
    "overall_pass": True,
    "error": None,
    "backend_support": {"loihi": {"verdict": "approximate"}},
    "validation_summary": {"errors": 0, "warnings": 1},
}
```

Expected output:

```python
summary.ok is True
summary.overall_pass is True
summary.error is None
summary.backend_support == {"loihi": {"verdict": "approximate"}}
summary.validation_summary == {"errors": 0, "warnings": 1}
```

### Example 2: Evaluate Wrapper Success

Input:

```python
facade = NeuroCnlFacade()
summary = facade.evaluate("example_spec.cnl")
```

Assume underlying pipeline success equivalent to:

```python
{
    "overall_pass": True,
    "error": None,
    "simulation_summary": {"duration_ms": 25.0},
    "assertion_summary": {"passed": 3, "failed": 0},
}
```

Expected output:

```python
summary.ok is True
summary.overall_pass is True
summary.error is None
summary.simulation_summary == {"duration_ms": 25.0}
summary.assertion_summary == {"passed": 3, "failed": 0}
```

### Example 3: Compile Wrapper Failure

Input:

```python
facade = NeuroCnlFacade()
summary = facade.compile("broken_spec.cnl")
```

Assume underlying pipeline result equivalent to:

```python
{
    "overall_pass": False,
    "error": "Parse error near line 1",
    "backend_support": None,
    "validation_summary": None,
}
```

Expected output:

```python
summary.ok is False
summary.overall_pass is False
summary.error == "Parse error near line 1"
```

### Example 4: Wrapper Is Thin

Expected behavior:

```text
The wrapper delegates to the existing pipeline rather than reconstructing compile/evaluate semantics independently.
```

## Edge Cases

- Missing optional sections such as `backend_support` or `simulation_summary` should become `None`.
- Failure cases must stay failures.
- The wrapper may normalize object-like pipeline results or dict-like results, but it must not guess unsupported semantics.

## Acceptance Checklist

- Matches all stated outputs
- Uses only allowed dependencies
- Preserves the truth of the underlying pipeline result
- Stays within compile/evaluate-style wrapper scope
