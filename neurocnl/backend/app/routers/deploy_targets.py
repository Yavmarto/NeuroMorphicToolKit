"""GET /api/deploy-targets — deploy-target metadata for the Hardware Deployment UI.

Sourced entirely from neurocnl.runtime.nir_support, the single source of
truth for per-backend node support (see nir_support.py's module docstring).
"""

from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from neurocnl.runtime.nir_support import (
    SIMULATOR_RUNTIME_BACKENDS,
    get_supported_node_types,
    list_supported_backends,
)

router = APIRouter()

# Notebook-backed framework runtimes with an in-studio preview/run path.
_FRAMEWORK_RUNTIME_BACKENDS: frozenset[str] = frozenset(
    {"brian2", "sinabs", "rockpool", "nengo"}
)

# Hardware deploy targets (subset of list_supported_backends()).
_DEPLOY_CAPABLE_BACKENDS: frozenset[str] = frozenset(
    {"akida", "pynq", "lava", "sc_neurocore_fpga"}
)


class DeployTargetInfo(BaseModel):
    id: str
    runtime_capable: bool
    deploy_capable: bool
    supported_nodes: list[str] = Field(default_factory=list)
    approximate_nodes: list[str] = Field(default_factory=list)
    unsupported_nodes: list[str] = Field(default_factory=list)


@router.get("/deploy-targets", response_model=list[DeployTargetInfo])
def list_deploy_targets() -> list[DeployTargetInfo]:
    result: list[DeployTargetInfo] = []
    for backend_id in list_supported_backends():
        table = get_supported_node_types(backend_id)
        result.append(
            DeployTargetInfo(
                id=backend_id,
                runtime_capable=(
                    backend_id in SIMULATOR_RUNTIME_BACKENDS
                    or backend_id in _FRAMEWORK_RUNTIME_BACKENDS
                ),
                deploy_capable=backend_id in _DEPLOY_CAPABLE_BACKENDS,
                supported_nodes=[n for n, v in table.items() if v == "exact"],
                approximate_nodes=[n for n, v in table.items() if v == "approximate"],
                unsupported_nodes=[n for n, v in table.items() if v == "unsupported"],
            )
        )
    return result
