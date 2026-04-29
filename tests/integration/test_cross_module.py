import os
import time
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4

import httpx
import pytest

# Service URLs from environment or defaults (Docker service names)
NEUROCNL_URL = os.getenv("NEUROCNL_URL", "http://neurocnl:8000")
NEUROSIM_URL = os.getenv("NEUROSIM_URL", "http://neurosim:8000")
NEUROCHIP_URL = os.getenv("NEUROCHIP_URL", "http://neurochip:8000")
NEUROSENSE_URL = os.getenv("NEUROSENSE_URL", "http://neurosense:8000")
NEUROHUB_URL = os.getenv("NEUROHUB_URL", "http://neurohub:8000")
NEUROBENCH_URL = os.getenv("NEUROBENCH_URL", "http://neurobench:8000")


def _service_label(url: str) -> str:
    parsed = urlparse(url)
    return parsed.netloc or parsed.path or url


async def _request_or_skip(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    **kwargs: object,
) -> httpx.Response:
    try:
        return await client.request(method, url, **kwargs)
    except httpx.RequestError as exc:
        pytest.skip(f"Integration service {_service_label(url)} unavailable: {exc}")


def _default_neurosense_artifact_path() -> str:
    return str(
        Path(__file__).resolve().parents[2]
        / "Neurosense"
        / "neurosense"
        / "tests"
        / "fixtures"
        / "canonical_emg_session.hdf5"
    )


@pytest.mark.asyncio
async def test_neurocnl_to_neurosim():
    """Test neurocnl -> Neurosim pipeline (CNL design -> simulation)"""
    spec = "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5"

    # 1. Validate in neurocnl
    async with httpx.AsyncClient() as client:
        resp = await _request_or_skip(client, "POST", f"{NEUROCNL_URL}/api/parse", json={"spec": spec})
        assert resp.status_code == 200
        assert resp.json()["errors"] == 0

        # 2. Parse in neurosim to get graph
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROSIM_URL}/api/neurosim/parse-cnl",
            json={"cnl_spec": spec, "import_mode": "repair"},
        )
        assert resp.status_code == 200
        graph = resp.json()
        assert "nodes" in graph

        # 3. Run preview in neurosim
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROSIM_URL}/api/neurosim/preview",
            json={"graph": graph, "duration_ms": 100},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "queued"


@pytest.mark.asyncio
async def test_neurosim_to_neurochip():
    """Test Neurosim -> Neurochip pipeline (simulation -> hardware deployment)"""
    mock_graph = {
        "nodes": [
            {
                "id": "n1",
                "component_id": "lif_population",
                "parameters": {"n_neurons": 10},
                "position": [0, 0],
            }
        ],
        "edges": [],
        "metadata": {},
    }

    async with httpx.AsyncClient() as client:
        # 1. Export from neurosim as C
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROSIM_URL}/api/neurosim/export/python?allow_approximate=true",
            json=mock_graph,
        )
        assert resp.status_code == 200
        assert resp.json()["format"] == "python"

        # 2. Validate deployment in neurochip
        manifest = {
            "target_device": "Teensy 4.1",
            "core_count": 1,
            "firmware_version": "1.0.0",
            "checksum_sha256": "a" * 64,
        }
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/deployments/validate", json=manifest
        )
        assert resp.status_code == 200
        assert resp.json()["target_device"] == "Teensy 4.1"


@pytest.mark.asyncio
async def test_neurosense_to_neurocnl():
    """Test Neurosense -> neurocnl pipeline (biosignal -> SNN model)"""
    mock_data = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
    encoding_config = {
        "method": "rate",
        "rate_max_hz": 200.0,
        "refractory_period": 0.001,
        "temporal_resolution": 0.001,
    }

    async with httpx.AsyncClient() as client:
        # 1. Encode in neurosense
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROSENSE_URL}/api/neurosense/encode",
            json={
                "data": mock_data,
                "encoding_config": encoding_config,
                "sampling_rate_hz": 250.0,
            },
        )
        assert resp.status_code == 200
        spikes = resp.json()["spike_trains"]
        assert len(spikes) == 2

        # 2. Use in neurocnl (Mocking integration via prosthetic sim)
        spec = "The sensory neuron MUST fire"
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/prosthetic/simulate",
            json={"spec": spec, "duration": 0.1, "n_neurons": 10},
        )
        if resp.status_code == 503:
            pytest.skip("NeuroCNL prosthetic simulation requires optional MuJoCo runtime.")
        # The endpoint returns 202 Accepted for background jobs
        assert resp.status_code == 202


@pytest.mark.asyncio
async def test_neurosense_artifact_handoff():
    """Test canonical NeuroSense artifact handoff into neurocnl and Neurobench."""
    artifact_path = os.getenv(
        "NEUROSENSE_ARTIFACT_PATH", _default_neurosense_artifact_path()
    )

    async with httpx.AsyncClient() as client:
        replay_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/prosthetic/neurosense/replay",
            json={"artifact_path": artifact_path, "preview_frames": 2},
        )
        if replay_resp.status_code == 404:
            pytest.skip(
                "NeuroCNL service could not access the configured NeuroSense artifact path."
            )
        assert replay_resp.status_code == 200, replay_resp.text
        replay_data = replay_resp.json()
        assert replay_data["artifact_schema_version"] == "1.0"
        assert replay_data["frame_count"] > 0
        assert replay_data["spike_event_count"] > 0

        bench_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROBENCH_URL}/api/neurobench/run",
            json={
                "benchmark_id": "neurosense_replay_contract",
                "network_path": "unused-for-recording-benchmark.cnl",
                "params": {"artifact_path": artifact_path},
            },
        )
        if bench_resp.status_code == 404:
            pytest.skip(
                "NeuroBench service does not have the NeuroSense recording benchmark loaded."
            )
        assert bench_resp.status_code == 200, bench_resp.text
        job_id = bench_resp.json()["job_id"]

        for _ in range(10):
            status_resp = await _request_or_skip(
                client,
                "GET",
                f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}"
            )
            assert status_resp.status_code == 200, status_resp.text
            status_data = status_resp.json()
            if status_data["status"] == "COMPLETED":
                result_resp = await _request_or_skip(
                    client,
                    "GET",
                    f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}/result"
                )
                assert result_resp.status_code == 200, result_resp.text
                result = result_resp.json()
                assert result["target_id"] == "neurosense_recording"
                assert result["metrics"]["input_spike_events"] > 0
                break
            if status_data["status"] == "FAILED":
                if "Session artifact not found" in (status_data.get("error") or ""):
                    pytest.skip(
                        "NeuroBench service could not access the configured NeuroSense artifact path."
                    )
                pytest.fail(
                    f"NeuroBench recording benchmark failed: {status_data.get('error')}"
                )
            time.sleep(1)
        else:
            pytest.fail("Timed out waiting for NeuroBench recording benchmark job.")


@pytest.mark.asyncio
async def test_neurohub_orchestration():
    """Test Neurohub orchestration of multi-module workflow"""
    workflow = {
        "id": f"test-integration-wf-{uuid4()}",
        "name": "Integration Pipeline",
        "description": "Validates CNL then runs Sim",
        "steps": [
            {
                "id": "val-step",
                "name": "Validate",
                "app": "neurocnl",
                "endpoint": "/api/validate",
                "method": "POST",
                "parameters": {
                    "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5"
                },
                "success_criteria": "overall == True",
                "on_failure": "halt",
            },
            {
                "id": "sim-step",
                "name": "Simulate",
                "app": "neurosim",
                "endpoint": "/api/neurosim/preview",
                "method": "POST",
                "parameters": {
                    "graph": {
                        "nodes": [
                            {
                                "id": "n1",
                                "component_id": "lif_population",
                                "parameters": {"name": "n1", "n_neurons": 10},
                                "position": [0, 0],
                            }
                        ],
                        "edges": [],
                        "metadata": {},
                    },
                    "duration_ms": 50,
                },
                "success_criteria": "status == 'queued'",
                "on_failure": "halt",
                "depends_on": ["val-step"],
            },
        ],
        "builtin": False,
    }

    async with httpx.AsyncClient() as client:
        # 1. Create workflow
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROHUB_URL}/api/neurohub/workflows", json=workflow
        )
        assert resp.status_code == 201

        # 2. Run workflow (requires a project_id)
        # First create a mock project
        project_id = f"test-project-{uuid4()}"
        project_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROHUB_URL}/api/neurohub/projects",
            json={
                "id": project_id,
                "name": "Test Project",
                "description": "Integration Test",
                "created_at": "2026-04-29T15:00:00Z",
                "updated_at": "2026-04-29T15:00:00Z",
                "owner": "testuser",
                "members": [{"user_id": "testuser", "name": "Test User", "role": "admin"}],
                "links": {
                    "neurochip_deployment_ids": [],
                    "neurobench_benchmark_ids": [],
                    "neurobench_baseline_ids": [],
                    "neurosense_session_ids": [],
                },
                "milestones": [],
                "tags": ["integration"],
                "status": "not_started",
            },
        )
        assert project_resp.status_code == 201, project_resp.text

        run_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROHUB_URL}/api/neurohub/workflows/{workflow['id']}/run",
            params={"project_id": project_id},
        )
        assert run_resp.status_code == 200
        run_id = run_resp.json()["id"]

        # 3. Poll for completion
        for _ in range(10):
            status_resp = await _request_or_skip(
                client,
                "GET",
                f"{NEUROHUB_URL}/api/neurohub/workflows/runs/{run_id}"
            )
            if status_resp.json()["status"] == "completed":
                break
            assert status_resp.json()["status"] != "failed"
            time.sleep(2)
        else:
            pytest.fail("Workflow timed out")


@pytest.mark.asyncio
async def test_neurobench_benchmarking():
    """Test Neurobench benchmarking across multiple modules"""
    async with httpx.AsyncClient() as client:
        # Mock benchmarking call referencing a path
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROBENCH_URL}/api/neurobench/run",
            json={
                "benchmark_id": "power_efficiency",
                "network_path": "/models/neurocnl_generated_model.py",
                "params": {"duration": 1.0},
            },
        )
        assert resp.status_code == 200
        # According to router.py, it returns model_dump() of result if request provided,
        # but current mock implementation in benchmark_runner might vary.
        # Based on router code, it should have a result or job_id.
        data = resp.json()
        assert "job_id" in data or "status" in data
