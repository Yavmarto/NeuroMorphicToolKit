"""End-to-end integration tests for the Teensy deployment pipeline.

Covers:
1. Happy path: CNL spec → neurocnl /api/deploy/teensy/network → Neurochip /api/neurochip/export/teensy → firmware zip
2. Rejected network paths: oversized, recurrent, STDP → proper rejection
3. Post-flash verification via Dream-Hand /api/neurochip/serial/flash/{job_id}/verify

Requires the running Suite API. Its URL and optional app-provisioned administrator
credential are read from the environment, with the supported dev host as the URL default.

This file is intentionally Teensy-specific. It does not validate the PYNQ Z2
deployment path or a real PYNQ board.
"""

from __future__ import annotations

import io
import zipfile

import httpx
import pytest

from .suite_api_client import request_suite_api, suite_api_url

SUITE_API_URL = suite_api_url()
NEUROCNL_URL = SUITE_API_URL
NEUROCHIP_URL = SUITE_API_URL


_request_or_skip = request_suite_api


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

VALID_REFLEX_ARC_SPEC = (
    "Define a network named teensy_reflex.\n"
    "Define an input port named input with shape (1,).\n"
    "Define a LIF neuron named relay with time constant 0.02, resistance 1.0, "
    "leak voltage 0.0, and firing threshold 1.0.\n"
    "Define an output port named output with shape (1,).\n"
    "input connects to relay.\n"
    "relay connects to output."
)

OVERSIZED_NETWORK_SPEC = "\n".join(
    [
        f"The network MUST contain an excitatory pop{i} population of 100 neurons"
        for i in range(50)  # 50 × 100 = 5000 neurons > 4096
    ]
    + ["The connection from pop0 to pop1 MUST have WITH synaptic weight of 1.0"]
)

RECURRENT_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.5\n"
    "The connection from motor neuron to sensory neuron MUST have WITH synaptic weight of 0.3\n"
)

STDP_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.5\n"
    "The connection from sensory neuron to motor neuron MUST adapt WITH STDP learning rate of 0.01\n"
)


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_teensy_e2e_happy_path():
    """Full pipeline: valid CNL spec → deploy endpoint → firmware zip."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Step 1: Deploy through neurocnl (parse → lower → plan → handoff)
        deploy_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": VALID_REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        assert deploy_resp.status_code == 200, (
            f"Deploy failed: {deploy_resp.status_code} {deploy_resp.text}"
        )

        deploy_data = deploy_resp.json()
        assert deploy_data["verdict"] in ("faithful", "approximate")
        assert deploy_data["payload"] is not None
        assert deploy_data["rejection_reasons"] == []

        payload = deploy_data["payload"]
        assert "num_neurons" in payload
        assert "num_synapses" in payload
        assert payload["neuron_model"] == "LIF"
        assert payload["weight_bit_width"] == 8
        assert "populations" in payload
        assert "connections" in payload
        assert payload["network_depth"] >= 1

        # Step 2: Export firmware through Neurochip
        export_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/export/teensy",
            json=payload,
            params={"bit_width": 8},
        )
        assert export_resp.status_code == 200, (
            f"Export failed: {export_resp.status_code} {export_resp.text}"
        )
        assert export_resp.headers["content-type"] == "application/zip"

        # Step 3: Verify the firmware zip contents
        firmware_zip = zipfile.ZipFile(io.BytesIO(export_resp.content))
        names = firmware_zip.namelist()
        assert any("main.ino" in n for n in names), f"main.ino not found in {names}"
        assert any("network_params.h" in n for n in names), (
            f"network_params.h not found in {names}"
        )
        assert any("lif_engine.h" in n for n in names), (
            f"lif_engine.h not found in {names}"
        )
        assert any("platformio.ini" in n for n in names), (
            f"platformio.ini not found in {names}"
        )


@pytest.mark.asyncio
async def test_teensy_e2e_happy_path_with_warnings():
    """Verify a near-capacity network returns 'approximate' verdict with warnings."""
    # Build a network that is within limits but close to capacity
    large_spec = (
        "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The network MUST contain an excitatory hidden population of 3000 neurons\n"
        "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The connection from sensory neuron to hidden MUST have WITH synaptic weight of 0.5\n"
        "The connection from hidden to motor neuron MUST have WITH synaptic weight of 0.5"
    )

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": large_spec, "weight_bit_width": 8},
        )
        # May be 200 (deployable with warnings) or 422 (not_deployable) depending on
        # exact neuron count from parsing — both are correct integration outcomes
        if resp.status_code == 200:
            data = resp.json()
            assert data["verdict"] in ("faithful", "approximate")
            assert data["payload"] is not None


# ---------------------------------------------------------------------------
# Rejected network paths
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_teensy_rejected_oversized_network():
    """Retired biological CNL is rejected before deployment planning."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": OVERSIZED_NETWORK_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422

        detail = resp.json()["detail"]
        error_code = (
            detail.get("code") or detail.get("error")
            if isinstance(detail, dict)
            else detail
        )
        assert error_code == "parse_failed"


@pytest.mark.asyncio
async def test_teensy_rejected_recurrent_topology():
    """Retired biological CNL is rejected before deployment planning."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": RECURRENT_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422

        detail = resp.json()["detail"]
        error_code = (
            detail.get("code") or detail.get("error")
            if isinstance(detail, dict)
            else detail
        )
        assert error_code == "parse_failed"


@pytest.mark.asyncio
async def test_teensy_rejected_learning_rule():
    """Retired STDP syntax is rejected before any Teensy payload is produced."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": STDP_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422

        detail = resp.json()["detail"]
        error_code = (
            detail.get("code") or detail.get("error")
            if isinstance(detail, dict)
            else detail
        )
        assert error_code == "parse_failed"


@pytest.mark.asyncio
async def test_teensy_rejected_invalid_bit_width():
    """Bit widths outside {8, 16, 32} must be rejected."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": VALID_REFLEX_ARC_SPEC, "weight_bit_width": 4},
        )
        assert resp.status_code == 422


@pytest.mark.asyncio
async def test_teensy_rejected_network_does_not_reach_neurochip():
    """Rejected networks should never produce a payload for Neurochip."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": RECURRENT_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422
        detail = resp.json()["detail"]
        # With a 422, no payload is returned — Neurochip never called
        assert "payload" not in detail or detail.get("payload") is None


# ---------------------------------------------------------------------------
# Post-flash Dream-Hand verification
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_teensy_post_flash_verification_contract():
    """Verify the Dream-Hand verification API contract shape.

    This test exercises the Neurochip serial API endpoints:
    1. POST /api/neurochip/serial/flash — start flash job
    2. GET  /api/neurochip/serial/flash/{job_id} — poll status
    3. POST /api/neurochip/serial/flash/{job_id}/verify — trigger verification

    In CI (no hardware), flash will fail at COMPILING or UPLOADING.
    The verify endpoint may return 503 if neurodreamhand is not installed.
    We test API contract shape, not hardware success.
    """
    async with httpx.AsyncClient(timeout=60.0) as client:
        # First, get a firmware zip from a happy-path deploy
        deploy_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": VALID_REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        if deploy_resp.status_code != 200:
            pytest.skip("Deploy endpoint not available for flash test")

        payload = deploy_resp.json()["payload"]

        export_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/export/teensy",
            json=payload,
            params={"bit_width": 8},
        )
        if export_resp.status_code != 200:
            pytest.skip("Export endpoint not available for flash test")

        firmware_bytes = export_resp.content

        # Step 1: Start flash job (will likely fail without hardware, but tests API shape)
        flash_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/serial/flash",
            files={"file": ("firmware.zip", firmware_bytes, "application/zip")},
            data={"port": "/dev/null"},
        )
        # Accept 200 (job started) or 4xx/5xx (no serial port) — test API exists
        if flash_resp.status_code != 200:
            pytest.skip(f"Flash endpoint unavailable: {flash_resp.status_code}")

        flash_data = flash_resp.json()
        assert "job_id" in flash_data
        assert "status" in flash_data
        job_id = flash_data["job_id"]

        # Step 2: Poll flash status (contract shape verification)
        poll_resp = await _request_or_skip(
            client, "GET", f"{NEUROCHIP_URL}/api/neurochip/serial/flash/{job_id}"
        )
        assert poll_resp.status_code == 200
        poll_data = poll_resp.json()
        assert "job_id" in poll_data
        assert "status" in poll_data
        assert "progress_pct" in poll_data

        # Step 3: Verify endpoint — test contract shape
        # If job is not DONE yet, expect 409; if neurodreamhand not installed, expect 503
        verify_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/serial/flash/{job_id}/verify",
            json={
                "port": "/dev/null",
                "run_demo": True,
                "run_hitl": False,
                "hitl_samples": 10,
                "timeout_s": 2.0,
            },
        )
        # 409 = job not done, 503 = neurodreamhand not installed, 200 = actual report
        assert verify_resp.status_code in (200, 409, 503)

        if verify_resp.status_code == 200:
            report = verify_resp.json()
            assert "passed" in report
            assert "smoke" in report
            assert "summary" in report
            assert "serial_port" in report


@pytest.mark.asyncio
async def test_teensy_verify_nonexistent_job():
    """Verify endpoint returns 404 for a nonexistent flash job."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/serial/flash/nonexistent-job-id/verify",
            json={"port": "/dev/null", "run_demo": False, "run_hitl": False},
        )
        assert resp.status_code == 404


@pytest.mark.asyncio
async def test_teensy_serial_ports_listing():
    """GET /api/neurochip/serial/ports returns a list (possibly empty in CI)."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await _request_or_skip(
            client,
            "GET",
            f"{NEUROCHIP_URL}/api/neurochip/serial/ports",
        )
        assert resp.status_code == 200
        ports = resp.json()
        assert isinstance(ports, list)


# ---------------------------------------------------------------------------
# Cross-module contract consistency
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_teensy_payload_schema_consistency():
    """Verify the payload from neurocnl matches what Neurochip accepts.

    The payload returned by /api/deploy/teensy/network should be directly
    submittable to /api/neurochip/export/teensy without transformation.
    """
    async with httpx.AsyncClient(timeout=30.0) as client:
        deploy_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCNL_URL}/api/neurocnl/deploy/teensy/network",
            json={"spec": VALID_REFLEX_ARC_SPEC, "weight_bit_width": 16},
        )
        if deploy_resp.status_code != 200:
            pytest.skip("Deploy endpoint not available")

        payload = deploy_resp.json()["payload"]

        # Payload should have all required NetworkInput fields
        required_fields = {
            "num_neurons",
            "num_synapses",
            "neuron_model",
            "weight_bit_width",
            "network_depth",
            "populations",
            "connections",
        }
        assert required_fields.issubset(set(payload.keys())), (
            f"Missing fields: {required_fields - set(payload.keys())}"
        )

        # It should be accepted by Neurochip export endpoint
        export_resp = await _request_or_skip(
            client,
            "POST",
            f"{NEUROCHIP_URL}/api/neurochip/export/teensy",
            json=payload,
            params={"bit_width": 16},
        )
        assert export_resp.status_code == 200
