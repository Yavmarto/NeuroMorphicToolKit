import os
import time
from pathlib import Path
from urllib.parse import urlparse

import httpx
import pytest

# Every ordinary product route is mounted by the consolidated Suite API.
# A single required base URL prevents tests silently exercising retired
# per-module ports or skipping the whole suite when the gateway is absent.
SUITE_API_URL = os.getenv("SUITE_API_URL", "http://127.0.0.1:9000").rstrip("/")
NEUROCNL_URL = SUITE_API_URL
NEUROSIM_URL = SUITE_API_URL
NEUROCHIP_URL = SUITE_API_URL
NEUROSENSE_URL = SUITE_API_URL
NEUROHUB_URL = SUITE_API_URL
NEUROBENCH_URL = SUITE_API_URL

NIR_NATIVE_REFLEX_SPEC = "\n".join(
    [
        "Define a network named integration_reflex.",
        "Define an input port named input with shape (1,).",
        "Define a LIF neuron named relay with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (1,).",
        "input connects to relay.",
        "relay connects to output.",
    ]
)


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
        pytest.fail(f"Required Suite API {_service_label(url)} unavailable: {exc}")


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
    spec = NIR_NATIVE_REFLEX_SPEC

    # 1. Validate in neurocnl
    async with httpx.AsyncClient() as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/parse",
            json={"spec": spec},
        )
        assert resp.status_code == 200
        assert resp.json()["errors"] == 0

        # 2. Parse in neurosim to get graph
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROSIM_URL}/api/neurosim/parse-cnl",
            json={"cnl_spec": spec},
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
            f"{NEUROCHIP_URL}/api/neurochip/deployments/validate",
            json=manifest,
        )
        assert resp.status_code == 200
        assert resp.json()["target_device"] == "Teensy 4.1"


@pytest.mark.asyncio
async def test_neurocnl_to_neurochip_lava_simulator():
    """Test NeuroCNL -> Neurochip Lava simulator handoff."""
    spec = NIR_NATIVE_REFLEX_SPEC

    async with httpx.AsyncClient() as client:
        deploy_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/lava/network",
            json={"spec": spec, "weight_bit_width": 8},
        )
        assert deploy_resp.status_code == 200, deploy_resp.text
        deploy_data = deploy_resp.json()
        if deploy_data["support_state"] == "unsupported":
            pytest.skip("NeuroCNL reported this Lava path as unsupported.")

        payload = deploy_data.get("deploy_payload")
        assert payload is not None

        compile_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/hardware/lava/compile",
            json={"network": payload, "run_config": "sim"},
        )
        if compile_resp.status_code == 503:
            pytest.skip(
                "Neurochip Lava simulator runtime is unavailable in this environment."
            )
        assert compile_resp.status_code == 200, compile_resp.text
        session_id = compile_resp.json()["session_id"]

        run_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/hardware/lava/run",
            json={"session_id": session_id, "steps": 3},
        )
        assert run_resp.status_code == 200, run_resp.text
        assert run_resp.json()["status"] == "success"


@pytest.mark.asyncio
async def test_neurocnl_to_neurochip_akida_runtime_handoff():
    """Test NeuroCNL -> Neurochip Akida mapped-network handoff."""
    spec = NIR_NATIVE_REFLEX_SPEC

    async with httpx.AsyncClient() as client:
        deploy_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/akida/network",
            json={
                "spec": spec,
                "weight_bit_width": 4,
                "akida_version": "akida2",
            },
        )
        assert deploy_resp.status_code == 200, deploy_resp.text
        deploy_data = deploy_resp.json()
        if deploy_data["support_state"] == "unsupported":
            pytest.skip("NeuroCNL reported this Akida path as unsupported.")

        mapped_network = deploy_data.get("mapped_network")
        assert mapped_network is not None

        map_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/akida/map?bit_width=4",
            json=mapped_network,
        )
        if map_resp.status_code == 503:
            pytest.skip(
                "Neurochip Akida runtime mapping is unavailable in this environment."
            )
        assert map_resp.status_code == 200, map_resp.text
        map_data = map_resp.json()
        assert "sdk_status" in map_data
        assert "runtime_target" in map_data
        assert "sdk_available" in map_data


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
            f"{NEUROCNL_URL}/api/neurocnl/prosthetic/simulate",
            json={"spec": spec, "duration": 0.1, "n_neurons": 10},
        )
        if resp.status_code == 503:
            pytest.skip(
                "NeuroCNL prosthetic simulation requires optional MuJoCo runtime."
            )
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
                client, "GET", f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}"
            )
            assert status_resp.status_code == 200, status_resp.text
            status_data = status_resp.json()
            if status_data["status"] == "COMPLETED":
                result_resp = await _request_or_skip(
                    client,
                    "GET",
                    f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}/result",
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
async def test_neurohub_registry_health():
    """Test that the Suite API exposes NeuroHub's self-health contract."""
    async with httpx.AsyncClient() as client:
        resp = await _request_or_skip(
            client,
            "GET",
            f"{NEUROHUB_URL}/api/neurohub/health",
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["status"] in {"ok", "degraded"}


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
