import os
import time
import httpx
import pytest

# Service URLs from environment or defaults (Docker service names)
NEUROCNL_URL = os.getenv("NEUROCNL_URL", "http://neurocnl:8000")
NEUROSIM_URL = os.getenv("NEUROSIM_URL", "http://neurosim:8000")
NEUROCHIP_URL = os.getenv("NEUROCHIP_URL", "http://neurochip:8000")
NEUROSENSE_URL = os.getenv("NEUROSENSE_URL", "http://neurosense:8000")
NEUROHUB_URL = os.getenv("NEUROHUB_URL", "http://neurohub:8000")
NEUROBENCH_URL = os.getenv("NEUROBENCH_URL", "http://neurobench:8000")


@pytest.mark.asyncio
async def test_neurocnl_to_neurosim():
    """Test neurocnl -> Neurosim pipeline (CNL design -> simulation)"""
    spec = "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5"

    # 1. Validate in neurocnl
    async with httpx.AsyncClient() as client:
        resp = await client.post(f"{NEUROCNL_URL}/api/parse", json={"spec": spec})
        assert resp.status_code == 200
        assert resp.json()["errors"] == 0

        # 2. Parse in neurosim to get graph
        resp = await client.post(
            f"{NEUROSIM_URL}/api/neurosim/parse-cnl", json={"cnl_spec": spec}
        )
        assert resp.status_code == 200
        graph = resp.json()
        assert "nodes" in graph

        # 3. Run preview in neurosim
        resp = await client.post(
            f"{NEUROSIM_URL}/api/neurosim/preview",
            json={"graph": graph, "duration_ms": 100},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"


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
        resp = await client.post(
            f"{NEUROSIM_URL}/api/neurosim/export/c", json=mock_graph
        )
        assert resp.status_code == 200
        assert resp.json()["format"] == "c"

        # 2. Validate deployment in neurochip
        manifest = {
            "target_device": "Teensy 4.1",
            "firmware_version": "1.0.0",
            "checksum_sha256": "a" * 64,
        }
        resp = await client.post(
            f"{NEUROCHIP_URL}/api/neurochip/deployments/validate", json=manifest
        )
        assert resp.status_code == 200
        assert resp.json()["target_device"] == "Teensy 4.1"


@pytest.mark.asyncio
async def test_neurosense_to_neurocnl():
    """Test Neurosense -> neurocnl pipeline (biosignal -> SNN model)"""
    mock_data = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
    encoding_config = {"method": "step_forward", "parameters": {"threshold": 0.01}}

    async with httpx.AsyncClient() as client:
        # 1. Encode in neurosense
        resp = await client.post(
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
        resp = await client.post(
            f"{NEUROCNL_URL}/api/prosthetic/simulate",
            json={"spec": spec, "duration": 0.1, "n_neurons": 10},
        )
        # The endpoint returns 202 Accepted for background jobs
        assert resp.status_code == 202


@pytest.mark.asyncio
async def test_neurohub_orchestration():
    """Test Neurohub orchestration of multi-module workflow"""
    workflow = {
        "id": "test-integration-wf",
        "name": "Integration Pipeline",
        "description": "Validates CNL then runs Sim",
        "steps": [
            {
                "id": "val-step",
                "name": "Validate",
                "app": "neurocnl",
                "endpoint": "/api/validate",
                "method": "POST",
                "parameters": {"spec": "Sensory neuron MUST fire"},
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
                                "component_id": "lif",
                                "parameters": {},
                                "position": [0, 0],
                            }
                        ],
                        "edges": [],
                        "metadata": {},
                    },
                    "duration_ms": 50,
                },
                "success_criteria": "status == 'ok'",
                "on_failure": "halt",
                "depends_on": ["val-step"],
            },
        ],
        "builtin": False,
    }

    async with httpx.AsyncClient() as client:
        # 1. Create workflow
        resp = await client.post(
            f"{NEUROHUB_URL}/api/neurohub/workflows", json=workflow
        )
        assert resp.status_code == 201

        # 2. Run workflow (requires a project_id)
        # First create a mock project
        project_resp = await client.post(
            f"{NEUROHUB_URL}/api/neurohub/projects",
            json={"name": "Test Project", "description": "Integration Test"},
        )
        project_id = project_resp.json()["id"]

        run_resp = await client.post(
            f"{NEUROHUB_URL}/api/neurohub/workflows/test-integration-wf/run",
            params={"project_id": project_id},
        )
        assert run_resp.status_code == 200
        run_id = run_resp.json()["id"]

        # 3. Poll for completion
        for _ in range(10):
            status_resp = await client.get(
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
        resp = await client.post(
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
