# NeuroSense Typing Baseline

This project enforces strict Mypy type checking for the core `neurosense/` package to ensure contract reliability and signal pipeline integrity.

## Strict Typing Baseline

As of Beta-02, the project maintains a **zero-error budget** for strict typing within the `neurosense/` package. All new contributions must maintain this baseline.

## Local Verification

To run Mypy locally with the project configuration, use the following command from the repository root:

```bash
python -m mypy neurosense/ --config-file pyproject.toml
```

## Common Remediation Patterns

### 1. Implicit `Optional`
Mypy now requires explicit `Optional` or `| None` for parameters with a `None` default.
**Before:**
```python
def example(request: Request = None): ...
```
**After:**
```python
def example(request: Request | None = None): ...
```

*Note: In some cases, such as FastAPI dependencies for `Request` and `WebSocket` objects, using explicit `Optional` or `| None` can confuse the framework's dependency injection and cause `FastAPIError` at runtime. In these specific cases, use `# type: ignore[assignment]` on the default value instead.*

### 2. Generic `Callable`
Specify arguments and return types for `Callable`.
**Before:**
```python
async def dispatch(self, request: Request, call_next: Callable) -> Response: ...
```
**After:**
```python
from starlette.middleware.base import RequestResponseEndpoint
async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response: ...
```

### 3. Library Assignment Mismatches
When overriding library methods (like `FastAPI.openapi`) where the signatures don't perfectly match the expected type, use `# type: ignore[method-assign]`.

### 4. Circular Imports and Forward References
Use `from __future__ import annotations` at the top of the file to support forward references and simplify type hints.
