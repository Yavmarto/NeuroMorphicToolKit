# Interfaces

Document only signatures, types, schemas, and stub bodies here.

## Package Layout

Assume these files already exist:

```text
tools/nmtk_mcp_server/__init__.py
tools/nmtk_mcp_server/resources.py
tools/nmtk_mcp_server/models.py
tools/nmtk_mcp_server/neurocnl_client.py
tools/nmtk_mcp_server/control_plane.py
tools/nmtk_mcp_server/control_plane_models.py
```

Create these files:

```text
tools/nmtk_mcp_server/result_models.py
tools/nmtk_mcp_server/authoring.py
tools/nmtk_mcp_server/module_registry.py
tools/nmtk_mcp_server/simulation_client.py
tools/nmtk_mcp_server/deployability_client.py
tools/nmtk_mcp_server/prompts.py
tools/nmtk_mcp_server/state_store.py
tools/nmtk_mcp_server/server_blueprint.py
tools/nmtk_mcp_server/tests/test_result_models.py
tools/nmtk_mcp_server/tests/test_authoring.py
tools/nmtk_mcp_server/tests/test_module_registry.py
tools/nmtk_mcp_server/tests/test_state_store.py
tools/nmtk_mcp_server/tests/test_server_blueprint.py
```

## `tools/nmtk_mcp_server/result_models.py`

```python
from pydantic import BaseModel, Field
from typing import Any


class ArtifactRef(BaseModel):
    kind: str
    uri: str | None = None
    path: str | None = None
    title: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class NextAction(BaseModel):
    action: str
    label: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)


class ToolResult(BaseModel):
    status: str
    summary: str
    details: dict[str, Any] = Field(default_factory=dict)
    artifacts: list[ArtifactRef] = Field(default_factory=list)
    next_actions: list[NextAction] = Field(default_factory=list)
```

## `tools/nmtk_mcp_server/authoring.py`

```python
from dataclasses import dataclass

from .resources import CanonicalPaths


@dataclass(frozen=True)
class AuthoringGuide:
    intent: str | None
    target_backend: str | None
    relevant_sections: list[str]
    examples: list[str]
    warnings: list[str]


def get_cnl_authoring_guide(
    paths: CanonicalPaths,
    intent: str | None = None,
    target_backend: str | None = None,
) -> AuthoringGuide:
    """Return a compact authoring guide derived from local grammar and support docs."""
```

## `tools/nmtk_mcp_server/module_registry.py`

```python
from pydantic import BaseModel, Field
from typing import Any


class ModuleStatusModel(BaseModel):
    id: str
    name: str | None = None
    status: str | None = None
    route: str | None = None
    effective_port: int | None = None
    health_url: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class ModuleRegistryClientError(RuntimeError):
    """Raised when launcher module status retrieval fails."""


class ModuleRegistryClient:
    def __init__(self, launcher_base_url: str = "http://127.0.0.1:8765") -> None: ...

    def list_modules(self) -> list[ModuleStatusModel]:
        """GET /api/launcher/modules and return typed module records."""

    def get_module(self, module_id: str) -> ModuleStatusModel | None:
        """Return one module by id or None if not present."""
```

## `tools/nmtk_mcp_server/simulation_client.py`

```python
from pydantic import BaseModel, Field
from typing import Any


class SimulationClientError(RuntimeError):
    """Raised when simulation-oriented API calls fail."""


class NeuroCnlSimulationRequest(BaseModel):
    spec: str
    backend: str = "nengo"
    mode: str = "validate_only"
    params: dict[str, Any] = Field(default_factory=dict)


class NeuroSimPreviewRequest(BaseModel):
    graph_or_spec: dict[str, Any] | str
    duration_ms: int = 1000


class JobRef(BaseModel):
    job_id: str
    status: str


class SimulationClient:
    def __init__(self, suite_api_base_url: str = "http://127.0.0.1:9000") -> None: ...

    def run_neurocnl_simulation(self, request: NeuroCnlSimulationRequest) -> JobRef:
        """Return a queued job reference for full mode or a local validation-shaped placeholder for validate_only mode."""

    def run_neurosim_preview(self, request: NeuroSimPreviewRequest) -> dict[str, Any]:
        """POST to /api/neurosim/preview and return parsed JSON."""
```

## `tools/nmtk_mcp_server/deployability_client.py`

```python
from pydantic import BaseModel, Field
from typing import Any


class DeployabilityClientError(RuntimeError):
    """Raised when deployability boilerplate calls fail."""


class DeployabilityRequest(BaseModel):
    spec: str
    target: str
    options: dict[str, Any] = Field(default_factory=dict)


class DeployabilityResponse(BaseModel):
    target: str
    route: str
    accepted: bool
    raw_response: dict[str, Any] = Field(default_factory=dict)


class NeurochipHandoff(BaseModel):
    target: str
    spec: str
    readiness_summary: dict[str, Any] = Field(default_factory=dict)
    artifacts: list[dict[str, Any]] = Field(default_factory=list)


class DeployabilityClient:
    def __init__(self, suite_api_base_url: str = "http://127.0.0.1:9000") -> None: ...

    def check_deployability(self, request: DeployabilityRequest) -> DeployabilityResponse:
        """Call the target-specific route without inventing final production verdict semantics."""

    def prepare_neurochip_handoff(
        self,
        spec: str,
        target: str,
        readiness_summary: dict[str, Any] | None = None,
    ) -> NeurochipHandoff:
        """Create a typed handoff payload without device execution."""
```

## `tools/nmtk_mcp_server/prompts.py`

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class PromptTemplate:
    name: str
    description: str
    resource_uris: list[str]
    template: str


def load_prompt_templates() -> list[PromptTemplate]:
    """Return versioned prompt metadata for Phase 1-3 workflows."""
```

## `tools/nmtk_mcp_server/state_store.py`

```python
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class StatePaths:
    base_dir: Path

    @property
    def sessions_dir(self) -> Path: ...

    @property
    def jobs_dir(self) -> Path: ...

    @property
    def artifacts_dir(self) -> Path: ...

    @property
    def deerflow_dir(self) -> Path: ...


class StateStore:
    def __init__(self, paths: StatePaths) -> None: ...

    def ensure_layout(self) -> None:
        """Create the expected directory layout."""

    def write_session(self, session_id: str, payload: dict[str, Any]) -> Path: ...
    def write_job(self, job_id: str, payload: dict[str, Any]) -> Path: ...
    def write_deerflow_packet(self, task_id: str, payload: dict[str, Any]) -> Path: ...
    def write_deerflow_result(self, task_id: str, payload: dict[str, Any]) -> Path: ...
    def read_json(self, path: Path) -> dict[str, Any]: ...
```

## `tools/nmtk_mcp_server/server_blueprint.py`

```python
from dataclasses import dataclass, field
from typing import Any, Callable


@dataclass(frozen=True)
class ResourceSpec:
    uri: str
    name: str
    description: str
    mime_type: str


@dataclass(frozen=True)
class ToolSpec:
    name: str
    description: str
    input_schema: dict[str, Any]
    handler_name: str


@dataclass(frozen=True)
class PromptSpec:
    name: str
    description: str
    arguments: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class ServerBlueprint:
    resources: list[ResourceSpec]
    tools: list[ToolSpec]
    prompts: list[PromptSpec]


def build_server_blueprint() -> ServerBlueprint:
    """Assemble the runtime-neutral Phase 1-3 MCP surface."""
```

## Tests

### `test_result_models.py`

Cover:

- default empty collections
- artifact and next-action serialization
- tool result round-trip through model validation

### `test_authoring.py`

Cover:

- grammar/support docs produce a non-empty authoring guide
- backend warnings are included when a matching backend is requested
- irrelevant long-document text is not returned wholesale

### `test_module_registry.py`

Cover:

- launcher modules success
- missing module returns None
- HTTP failure raises `ModuleRegistryClientError`
- invalid JSON raises `ModuleRegistryClientError`

### `test_state_store.py`

Cover:

- layout creation
- session/job/deerflow writes produce JSON files
- `read_json` returns the written payload

### `test_server_blueprint.py`

Cover:

- expected Phase 1 resource URIs are present
- expected Phase 1-2 tool names are present
- expected prompt names are present
- blueprint assembly is transport-neutral and contains no concrete runtime dependency

## Reference Notes

- Read-only resources:
  - `nmtk://cnl/grammar/current`
  - `nmtk://cnl/support-matrix/current`
  - `nmtk://suite/modules/current`
  - `nmtk://api/openapi/current`
- Phase 1 safe tools:
  - `validate_cnl`
  - `suite_health`
  - `doctor`
  - `module_status`
  - `get_cnl_authoring_guide`
- Phase 2 boilerplate-only tools:
  - `run_neurocnl_simulation`
  - `run_neurosim_preview`
  - `check_deployability`
  - `prepare_neurochip_handoff`
- Phase 3 workflow support:
  - prompt metadata
  - local state store
  - DeerFlow packet/result persistence
