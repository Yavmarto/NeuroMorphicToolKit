# Interfaces

Document only signatures, types, schemas, and stub bodies here.

## Target Surface 1: `training_registry.py`

```python
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


class AdapterSelectionError(ValueError):
    """Raised when an adapter cannot be selected or used honestly."""


@dataclass(frozen=True, slots=True)
class AdapterCapability:
    backend_name: str
    supported_training_modes: tuple[str, ...]
    default_training_mode: str
    output_format: str | None = None


@dataclass(frozen=True, slots=True)
class TrainingRequest:
    backend_name: str
    training_mode: str | None = None
    payload: dict[str, Any] | None = None


class BaseTrainingAdapter:
    capability: AdapterCapability

    def run(self, request: TrainingRequest) -> dict[str, Any]:
        """Return a side-effect-free summary for this foundation slice."""
        raise NotImplementedError


class TrainingAdapterRegistry:
    def __init__(self, adapters: list[BaseTrainingAdapter]) -> None:
        raise NotImplementedError

    def list_capabilities(self) -> list[AdapterCapability]:
        raise NotImplementedError

    def get_adapter(self, backend_name: str) -> BaseTrainingAdapter:
        raise NotImplementedError

    def resolve_mode(self, adapter: BaseTrainingAdapter, training_mode: str | None) -> str:
        raise NotImplementedError

    def dispatch(self, request: TrainingRequest) -> dict[str, Any]:
        raise NotImplementedError
```

## Target Surface 2: `test_training_registry.py`

Expected test themes:

- capability sorting
- case-insensitive adapter lookup
- default-mode dispatch
- unsupported-mode rejection
- duplicate registration rejection
- blank-mode rejection
- unknown-backend rejection
- payload passthrough

## Minimal Dispatch Contract

The sanitized `run()` contract for adapters is intentionally simple:

```python
{
    "backend": "normalized-backend-name-or-stable-adapter-id",
    "mode": "resolved-normalized-training-mode",
    "payload": request.payload,
}
```

# Reference Notes

- This slice is for registry and validation semantics, not real training execution.
- A side-effect-free example adapter is acceptable in tests.
- Capability objects may preserve their original display backend name while selection uses normalized names.
