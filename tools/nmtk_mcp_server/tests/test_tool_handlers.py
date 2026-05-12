from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tools.nmtk_mcp_server.control_plane_models import (
    LauncherDoctorResponse,
    LauncherDoctorSummary,
    SuiteHealthResponse,
)
from tools.nmtk_mcp_server.models import (
    BackendSupportModel,
    Layer1ResultModel,
    Layer2ResultModel,
    ValidateCnlResponse,
)
from tools.nmtk_mcp_server.module_registry import ModuleStatusModel
from tools.nmtk_mcp_server.runtime_config import RuntimeConfig
from tools.nmtk_mcp_server.simulation_client import (
    SimulationJobResponse,
    SimulationJobStatus,
)
from tools.nmtk_mcp_server.tool_handlers import ToolHandlerContext


class _FakeNeuroCnlClient:
    def validate_cnl(self, request: Any) -> ValidateCnlResponse:
        assert request.spec == "neuron A spikes."
        return ValidateCnlResponse(
            layer1=Layer1ResultModel(overall=True),
            layer2=Layer2ResultModel(overall=True),
            overall=True,
            backend_support=BackendSupportModel(backend="nengo", verdict="faithful"),
        )


class _FakeControlPlaneClient:
    def suite_health(self) -> SuiteHealthResponse:
        return SuiteHealthResponse(status="ok", service="suite_api")

    def doctor(self) -> LauncherDoctorSummary:
        report = LauncherDoctorResponse(
            status="error",
            fatalCount=1,
            degradedCount=0,
            okCount=2,
        )
        return LauncherDoctorSummary(
            status="preflight_failed",
            blocking=True,
            fatal_count=1,
            degraded_count=0,
            ok_count=2,
            report=report,
        )


class _FakeModuleRegistryClient:
    def list_modules(self, *, refresh_updates: bool = False) -> list[ModuleStatusModel]:
        assert refresh_updates is False
        return [
            ModuleStatusModel(
                id="neurocnl",
                status="running",
                preflightStatus="ok",
                effectivePort=9000,
            )
        ]


class _FakeSimulationClient:
    def submit_simulation(self, request: Any) -> SimulationJobResponse:
        assert request.duration == 0.5
        return SimulationJobResponse(
            job_id="job-1",
            status=SimulationJobStatus.queued,
        )

    def poll_job(self, job_id: str) -> SimulationJobResponse:
        assert job_id == "job-1"
        return SimulationJobResponse(
            job_id="job-1",
            status=SimulationJobStatus.complete,
            result={"summary": {"motor_spike_count": 1}},
        )


class _FakeDeployabilityClient:
    def check_deployability(self, request: Any) -> Any:
        return type(
            "Deployability",
            (),
            {
                "outcome": "ok",
                "model_dump": lambda self, mode="json": {
                    "target": request.target,
                    "outcome": "ok",
                },
            },
        )()

    def prepare_neurochip_handoff(
        self,
        spec: str,
        target: str,
        readiness_summary: dict[str, Any] | None = None,
    ) -> Any:
        return type(
            "Handoff",
            (),
            {
                "model_dump": lambda self, mode="json": {
                    "spec": spec,
                    "target": target,
                    "readiness_summary": readiness_summary or {},
                    "artifacts": [],
                }
            },
        )()


def _context(tmp_path: Path) -> ToolHandlerContext:
    repo_root = tmp_path / "repo"
    grammar_path = repo_root / "neurocnl" / "neurocnl" / "cnl"
    support_path = repo_root / "neurocnl" / "docs"
    manifest_path = repo_root / "nmtk" / "neuro_toolkit" / "assets"
    grammar_path.mkdir(parents=True)
    support_path.mkdir(parents=True)
    manifest_path.mkdir(parents=True)
    (grammar_path / "cnl_grammar.md").write_text("# CNL Grammar\n\n## Reflex\n\nNeuron A.", encoding="utf-8")
    (support_path / "support_matrix.md").write_text("# Support\n\n## Nengo\n\nSupported.", encoding="utf-8")
    (manifest_path / "modules.json").write_text(json.dumps([{"id": "neurocnl"}]), encoding="utf-8")
    return ToolHandlerContext(
        config=RuntimeConfig(repo_root=repo_root, state_path=tmp_path / "state.json"),
        neurocnl_client=_FakeNeuroCnlClient(),
        control_plane_client=_FakeControlPlaneClient(),
        module_registry_client=_FakeModuleRegistryClient(),
        simulation_client=_FakeSimulationClient(),
        deployability_client=_FakeDeployabilityClient(),
    )


def test_tool_handlers_return_tool_result_envelopes(tmp_path: Path) -> None:
    context = _context(tmp_path)

    assert context.validate_cnl("neuron A spikes.")["status"] == "ok"
    assert context.suite_health()["details"] == {"status": "ok", "service": "suite_api"}
    assert context.launcher_doctor()["status"] == "preflight_failed"
    assert context.list_modules()["details"]["modules"][0]["id"] == "neurocnl"
    assert context.get_cnl_authoring_guide(topic="reflex")["details"]["guide"]["sections"]
    assert context.submit_simulation("neuron A spikes.", duration=0.5)["details"]["job_id"] == "job-1"
    assert context.poll_simulation_job("job-1")["details"]["status"] == "complete"
    assert context.check_deployability("neuron A spikes.", "teensy")["details"]["target"] == "teensy"
    assert context.prepare_neurochip_handoff("neuron A spikes.", "teensy")["details"]["target"] == "teensy"


def test_tool_handlers_persist_local_state(tmp_path: Path) -> None:
    context = _context(tmp_path)

    saved = context.save_deerflow_packet("task-1", {"task_type": "mcp_scaffold"})
    loaded = context.load_local_state()

    assert saved["status"] == "ok"
    assert loaded["details"]["active_packet_id"] == "task-1"
    assert loaded["details"]["packets"]["task-1"]["payload"] == {
        "task_type": "mcp_scaffold"
    }
