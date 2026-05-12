from __future__ import annotations

from typing import Any

from .authoring import build_authoring_guide
from .control_plane import ControlPlaneClient
from .deployability_client import DeployabilityClient, DeployabilityRequest
from .models import ValidateCnlRequest
from .module_registry import ModuleRegistryClient, shape_module_statuses
from .neurocnl_client import NeuroCnlClient
from .resources import (
    CanonicalPaths,
    load_cnl_grammar,
    load_modules_manifest,
    load_support_matrix,
)
from .result_models import ArtifactRef, NextAction, ToolResult
from .runtime_config import RuntimeConfig
from .simulation_client import SimulationClient, SimulationRequest
from .state_store import DeerFlowPacket, JsonStateStore


class ToolHandlerContext:
    def __init__(
        self,
        config: RuntimeConfig,
        *,
        neurocnl_client: Any | None = None,
        control_plane_client: Any | None = None,
        module_registry_client: Any | None = None,
        simulation_client: Any | None = None,
        deployability_client: Any | None = None,
    ) -> None:
        self.config = config
        self.paths = CanonicalPaths(config.repo_root)
        self.neurocnl_client = neurocnl_client or NeuroCnlClient(config.suite_api_base_url)
        self.control_plane_client = control_plane_client or ControlPlaneClient(
            suite_api_base_url=config.suite_api_base_url,
            launcher_base_url=config.launcher_base_url,
        )
        self.module_registry_client = module_registry_client or ModuleRegistryClient(
            config.launcher_base_url
        )
        self.simulation_client = simulation_client or SimulationClient(
            config.suite_api_base_url
        )
        self.deployability_client = deployability_client or DeployabilityClient(
            config.suite_api_base_url
        )
        self.state_store = JsonStateStore(config.resolved_state_path)

    def validate_cnl(
        self,
        spec: str,
        backend: str = "nengo",
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        response = self.neurocnl_client.validate_cnl(
            ValidateCnlRequest(spec=spec, backend=backend, params=params or {})
        )
        status = "ok" if response.overall else "needs_attention"
        return _dump_result(
            ToolResult(
                status=status,
                summary="NeuroCNL validation completed.",
                details=response.model_dump(mode="json"),
                next_actions=[
                    NextAction(action="submit_simulation", label="Submit simulation")
                ]
                if response.overall
                else [],
            )
        )

    def suite_health(self) -> dict[str, Any]:
        response = self.control_plane_client.suite_health()
        return _dump_result(
            ToolResult(
                status=response.status,
                summary="suite_api health read completed.",
                details=response.model_dump(mode="json"),
            )
        )

    def launcher_doctor(self) -> dict[str, Any]:
        summary = self.control_plane_client.doctor()
        return _dump_result(
            ToolResult(
                status=summary.status,
                summary="Launcher doctor read completed.",
                details=summary.model_dump(mode="json"),
            )
        )

    def list_modules(self, refresh_updates: bool = False) -> dict[str, Any]:
        modules = self.module_registry_client.list_modules(
            refresh_updates=refresh_updates
        )
        return _dump_result(
            ToolResult(
                status="ok",
                summary="Launcher modules read completed.",
                details={"modules": shape_module_statuses(modules)},
            )
        )

    def get_cnl_authoring_guide(
        self,
        topic: str | None = None,
        max_sections_per_source: int = 2,
    ) -> dict[str, Any]:
        guide = build_authoring_guide(
            grammar_text=load_cnl_grammar(self.paths),
            support_matrix_text=load_support_matrix(self.paths),
            topic=topic,
            max_sections_per_source=max_sections_per_source,
        )
        return _dump_result(
            ToolResult(
                status="ok",
                summary="CNL authoring guide built from canonical resources.",
                details={"guide": guide.model_dump(mode="json")},
            )
        )

    def submit_simulation(
        self,
        spec: str,
        duration: float = 1.0,
        dt: float = 0.001,
        backend: str = "nengo",
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        response = self.simulation_client.submit_simulation(
            SimulationRequest(
                spec=spec,
                params=params or {},
                duration=duration,
                dt=dt,
                backend=backend,
            )
        )
        return _dump_result(
            ToolResult(
                status="ok",
                summary="Simulation job submitted through suite_api.",
                details=response.model_dump(mode="json"),
                next_actions=[
                    NextAction(
                        action="poll_simulation_job",
                        label="Poll simulation job",
                        payload={"job_id": response.job_id},
                    )
                ],
            )
        )

    def poll_simulation_job(self, job_id: str) -> dict[str, Any]:
        response = self.simulation_client.poll_job(job_id)
        status = "ok" if response.status != "failed" else "failed"
        return _dump_result(
            ToolResult(
                status=status,
                summary="Simulation job status read completed.",
                details=response.model_dump(mode="json"),
            )
        )

    def check_deployability(
        self,
        spec: str,
        target: str,
        options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        response = self.deployability_client.check_deployability(
            DeployabilityRequest(spec=spec, target=target, options=options or {})
        )
        result_status = "needs_attention" if response.outcome == "not_deployable" else "ok"
        return _dump_result(
            ToolResult(
                status=result_status,
                summary="Deployability check completed without device execution.",
                details=response.model_dump(mode="json"),
            )
        )

    def prepare_neurochip_handoff(
        self,
        spec: str,
        target: str,
        readiness_summary: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        handoff = self.deployability_client.prepare_neurochip_handoff(
            spec,
            target,
            readiness_summary=readiness_summary,
        )
        return _dump_result(
            ToolResult(
                status="ok",
                summary="Neurochip handoff scaffold prepared without deployment.",
                details=handoff.model_dump(mode="json"),
            )
        )

    def save_deerflow_packet(
        self,
        packet_id: str,
        payload: dict[str, Any],
        title: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        state = self.state_store.upsert_packet(
            DeerFlowPacket(
                packet_id=packet_id,
                title=title,
                payload=payload,
                metadata=metadata or {},
            ),
            activate=True,
        )
        return _dump_result(
            ToolResult(
                status="ok",
                summary="DeerFlow packet persisted locally.",
                details=state.model_dump(mode="json"),
                artifacts=[
                    ArtifactRef(
                        kind="deerflow_packet",
                        path=str(self.config.resolved_state_path),
                        title=packet_id,
                    )
                ],
            )
        )

    def load_local_state(self) -> dict[str, Any]:
        state = self.state_store.load()
        return _dump_result(
            ToolResult(
                status="ok",
                summary="Local MCP state loaded.",
                details=state.model_dump(mode="json"),
            )
        )

    def load_modules_manifest_resource(self) -> str:
        return _json_text(load_modules_manifest(self.paths))


def _dump_result(result: ToolResult) -> dict[str, Any]:
    return result.model_dump(mode="json")


def _json_text(payload: Any) -> str:
    import json

    return json.dumps(payload, indent=2, sort_keys=True)
