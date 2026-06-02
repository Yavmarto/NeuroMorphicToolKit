"""Golden Path 1: author → validate → simulate → inspect → persist.

Tests the full studio workflow without requiring hardware.
Each step skips gracefully if the required service is unavailable.

Services required: neurocnl (+ neurosim routes), neurobench.
Start them with the launcher or set NEUROCNL_URL / NEUROBENCH_URL env vars.
"""

import asyncio
import os
from urllib.parse import urlparse

import httpx
import pytest

NEUROCNL_URL = os.getenv("NEUROCNL_URL", "http://neurocnl:8000")
NEUROSIM_URL = os.getenv("NEUROSIM_URL", "http://neurocnl:8000")
NEUROBENCH_URL = os.getenv("NEUROBENCH_URL", "http://neurobench:8000")

# Minimal valid NIR-native spec: one sensory neuron → one motor neuron.
_REFLEX_ARC_SPEC = "\n".join([
    "Define an input port named sensory with shape (1,).",
    "Define a leaky integrate-and-fire neuron named relay"
    " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
    " and firing threshold 1.0.",
    "Define an output port named motor with shape (1,).",
    "sensory connects to relay.",
    "relay connects to motor.",
])


def _service_label(url: str) -> str:
    parsed = urlparse(url)
    return parsed.netloc or url


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


@pytest.mark.asyncio
@pytest.mark.golden_path
async def test_golden_path_1_no_hardware() -> None:
    """Golden Path 1: author → validate → simulate → inspect → persist (no hardware)."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        # ------------------------------------------------------------------
        # Step 1: Author — parse the CNL spec
        # ------------------------------------------------------------------
        resp = await _request_or_skip(
            client, "POST", f"{NEUROCNL_URL}/api/parse",
            json={"spec": _REFLEX_ARC_SPEC},
        )
        assert resp.status_code == 200, f"Parse failed: {resp.text}"
        assert resp.json()["errors"] == 0, f"Parse errors: {resp.json()}"

        # ------------------------------------------------------------------
        # Step 2: Validate — L1 + L2 + backend support verdict
        # ------------------------------------------------------------------
        resp = await _request_or_skip(
            client, "POST", f"{NEUROCNL_URL}/api/validate",
            json={"spec": _REFLEX_ARC_SPEC},
        )
        assert resp.status_code == 200, f"Validate failed: {resp.text}"
        v = resp.json()
        assert v["overall"] is True, f"Validation did not pass: {v}"
        assert v["backend_support"] is not None, "backend_support must not be null"
        assert v["backend_support"]["verdict"] in {"faithful", "approximate"}, (
            f"Expected faithful/approximate verdict, got: {v['backend_support']['verdict']}"
        )

        # ------------------------------------------------------------------
        # Step 3: Simulate — neurosim parse-cnl + preview
        # ------------------------------------------------------------------
        resp = await _request_or_skip(
            client, "POST", f"{NEUROSIM_URL}/api/neurosim/parse-cnl",
            json={"cnl_spec": _REFLEX_ARC_SPEC},
        )
        assert resp.status_code == 200, f"Neurosim parse-cnl failed: {resp.text}"
        graph = resp.json()
        assert "nodes" in graph, f"Graph missing 'nodes': {graph}"

        resp = await _request_or_skip(
            client, "POST", f"{NEUROSIM_URL}/api/neurosim/preview",
            json={"graph": graph, "duration_ms": 100},
        )
        assert resp.status_code == 200, f"Neurosim preview failed: {resp.text}"
        preview = resp.json()
        assert preview.get("status") in {"queued", "running", "completed"}, (
            f"Unexpected preview status: {preview}"
        )

        # ------------------------------------------------------------------
        # Step 4: Inspect — compile to NIR, verify backend verdict header
        # ------------------------------------------------------------------
        resp = await _request_or_skip(
            client, "POST", f"{NEUROCNL_URL}/api/export",
            json={"spec": _REFLEX_ARC_SPEC, "format": "nir"},
        )
        assert resp.status_code == 200, f"NIR export failed: {resp.text}"
        assert "octet-stream" in resp.headers.get("Content-Type", ""), (
            "NIR export must return application/octet-stream"
        )
        verdict = resp.headers.get("X-NeuroCNL-Backend-Verdict", "")
        assert verdict in {"faithful", "approximate"}, (
            f"NIR export verdict should be faithful or approximate, got '{verdict}'"
        )

        # ------------------------------------------------------------------
        # Step 5: Persist — submit to Neurobench, poll for COMPLETED result
        # ------------------------------------------------------------------
        resp = await _request_or_skip(
            client, "POST", f"{NEUROBENCH_URL}/api/neurobench/run",
            json={
                "benchmark_id": "power_efficiency",
                "network_content": _REFLEX_ARC_SPEC,
                "target": "simulation",
            },
        )
        assert resp.status_code == 200, f"Neurobench run failed: {resp.text}"
        job_data = resp.json()
        assert "job_id" in job_data, f"Expected job_id in response: {job_data}"
        job_id = job_data["job_id"]

        # Poll for completion (max 30 s)
        job: dict = {}
        for _ in range(30):
            resp = await _request_or_skip(
                client, "GET", f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}",
            )
            assert resp.status_code == 200
            job = resp.json()
            if job["status"] in {"COMPLETED", "FAILED"}:
                break
            await asyncio.sleep(1.0)

        assert job["status"] == "COMPLETED", (
            f"Neurobench job did not complete: status={job['status']},"
            f" error={job.get('error')}"
        )

        # Fetch and verify the persisted result
        resp = await _request_or_skip(
            client, "GET", f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}/result",
        )
        assert resp.status_code == 200, f"Neurobench result fetch failed: {resp.text}"
        result = resp.json()
        assert "metrics" in result, f"Result missing 'metrics': {result}"
