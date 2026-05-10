# Examples And Acceptance Tests

## Input/Output Examples

### Example 1: Capability Listing Sorts By Normalized Backend Name

Input:

```python
class AdapterA(BaseTrainingAdapter):
    capability = AdapterCapability(
        backend_name=" Framework-B ",
        supported_training_modes=("surrogate",),
        default_training_mode="surrogate",
        output_format="graph",
    )

    def run(self, request: TrainingRequest) -> dict[str, Any]:
        return {"backend": "framework-b", "mode": request.training_mode, "payload": request.payload}


class AdapterB(BaseTrainingAdapter):
    capability = AdapterCapability(
        backend_name="framework-a",
        supported_training_modes=("ann_to_snn", "surrogate"),
        default_training_mode=" ANN_TO_SNN ",
        output_format="graph",
    )

    def run(self, request: TrainingRequest) -> dict[str, Any]:
        return {"backend": "framework-a", "mode": request.training_mode, "payload": request.payload}


registry = TrainingAdapterRegistry([AdapterA(), AdapterB()])
caps = registry.list_capabilities()
```

Expected output:

```python
[cap.backend_name for cap in caps] == ["framework-a", " Framework-B "]
```

### Example 2: Case-Insensitive Adapter Lookup

Input:

```python
adapter = registry.get_adapter("  FRAMEWORK-A ")
```

Expected output:

```python
adapter.capability.backend_name == "framework-a"
```

### Example 3: Default Mode Resolution

Input:

```python
request = TrainingRequest(backend_name="framework-a")
result = registry.dispatch(request)
```

Expected output:

```python
result == {"backend": "framework-a", "mode": "ann_to_snn", "payload": None}
```

### Example 4: Unsupported Mode Fails Closed

Input:

```python
request = TrainingRequest(
    backend_name="framework-b",
    training_mode="ann_to_snn",
)
registry.dispatch(request)
```

Expected behavior:

```text
Raise AdapterSelectionError with a clear message naming the backend and unsupported mode.
```

### Example 5: Duplicate Registration Fails Closed

Input:

```python
class DuplicateAdapter(BaseTrainingAdapter):
    capability = AdapterCapability(
        backend_name=" FRAMEWORK-A ",
        supported_training_modes=("surrogate",),
        default_training_mode="surrogate",
    )

    def run(self, request: TrainingRequest) -> dict[str, Any]:
        return {}


TrainingAdapterRegistry([AdapterB(), DuplicateAdapter()])
```

Expected behavior:

```text
Raise AdapterSelectionError during registry construction.
```

### Example 6: Explicit Blank Mode Fails Closed

Input:

```python
registry.dispatch(TrainingRequest(backend_name="framework-a", training_mode="   "))
```

Expected behavior:

```text
Raise AdapterSelectionError because the training mode becomes empty after normalization.
```

## Edge Cases

- Unknown backends should fail closed.
- Payload may be `None`.
- Payload passthrough should preserve the original object.
- The default training mode itself may need normalization before dispatch.

## Acceptance Checklist

- Matches all stated outputs
- Uses only allowed dependencies
- Preserves fail-closed validation behavior
- Keeps registry behavior deterministic
