"""PYNQ-Z2 (sc-neurocore) Real-Hardware Validation.

Tests the full deploy → inference pipeline against a PHYSICAL PYNQ-Z2 FPGA board.
Any simulator fallback causes an explicit FAIL — not a skip.

=== How hardware is confirmed ===

1. GET  /hardware/pynq/preflight
   → runtime_mode MUST be "hardware"
   → preflight_status MUST be "ok" or "degraded" (not "failed")
   The preflight only reports "hardware" mode when the pynq Python package is
   reachable and probe_real_pynq_device_access() succeeds.  A simulator backend
   reports "degraded" with the message "Simulator fallback active".

2. POST /hardware/pynq/deploy with require_hardware=true (both body + query param)
   → Returns HTTP 503 if no real PYNQ device is detected.
   → A 200 with runtime_mode="hardware" in the body proves the FPGA overlay was
     loaded and weights were written via DMA/MMIO on real Zynq-7000 silicon.

3. GET  /hardware/pynq/status
   → runtime_mode MUST remain "hardware" after deploy.

4. POST /hardware/pynq/run
   → Output spikes come back from the FPGA fabric.
   → execution_time_us is logged as evidence of real board latency.

5. POST /hardware/pynq/verify
   → SITL verification runs each stimulus case through the real FPGA and
     records per-case output + timing.

=== Opt-in ===

Set PYNQ_HARDWARE_TEST=true to activate this test suite.
The test skips (not fails) when the env var is absent so standard CI
(which has no board attached) is not disrupted.

Set NEUROCHIP_URL to override the default http://localhost:9000 when the
Neurochip service is running on a different host or port.
"""

from __future__ import annotations

import os
from urllib.parse import urlparse

import httpx
import pytest

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_PYNQ_HW_REQUIRED: bool = os.getenv("PYNQ_HARDWARE_TEST", "").lower() in {"1", "true", "yes"}

NEUROCHIP_URL: str = os.getenv("NEUROCHIP_URL", "http://localhost:9000")
_PYNQ_BASE: str = f"{NEUROCHIP_URL}/hardware/pynq"

# Minimal reflex-arc weights for a 2-input × 2-output network (2×2 = 4 values).
# These are intentionally small floats — the FPGA quantizes them to integers.
_WEIGHTS: list[float] = [0.8, 0.2, 0.3, 0.9]
_INPUT_SPIKES: list[int] = [1, 0]

pytestmark = pytest.mark.pynq_hardware


# ---------------------------------------------------------------------------
# Hardware guard
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def require_pynq_hardware_env() -> None:
    """Skip every test in this module unless PYNQ_HARDWARE_TEST=true.

    If the flag IS set but hardware is not reachable, the individual tests
    will FAIL with a clear message rather than skip.
    """
    if not _PYNQ_HW_REQUIRED:
        pytest.skip(
            "PYNQ-Z2 hardware tests are skipped by default.\n"
            "Set PYNQ_HARDWARE_TEST=true to run on a physical PYNQ-Z2 board (sc-neurocore).\n"
            f"NEUROCHIP_URL is: {NEUROCHIP_URL}"
        )


def _service_label(url: str) -> str:
    parsed = urlparse(url)
    return parsed.netloc or url


def _get_or_fail(client: httpx.Client, url: str, **kwargs: object) -> httpx.Response:
    try:
        return client.get(url, **kwargs)  # type: ignore[return-value]
    except httpx.RequestError as exc:
        pytest.fail(
            f"[PYNQ HW] Neurochip service at {_service_label(url)} is unreachable: {exc}\n"
            "Ensure the Neurochip backend is running with PYNQ hardware mode active."
        )


def _post_or_fail(client: httpx.Client, url: str, **kwargs: object) -> httpx.Response:
    try:
        return client.post(url, **kwargs)  # type: ignore[return-value]
    except httpx.RequestError as exc:
        pytest.fail(
            f"[PYNQ HW] Neurochip service at {_service_label(url)} is unreachable: {exc}\n"
            "Ensure the Neurochip backend is running with PYNQ hardware mode active."
        )


def _assert_hardware_mode(data: dict, *, step: str) -> None:
    """Assert runtime_mode == 'hardware', producing a maximally informative failure."""
    mode = data.get("runtime_mode", "")
    assert mode == "hardware", (
        f"\n"
        f"══════════════════════════════════════════════════════════════\n"
        f"  HARDWARE TEST FAILED — {step}\n"
        f"══════════════════════════════════════════════════════════════\n"
        f"  runtime_mode : '{mode}'  (expected 'hardware')\n"
        f"\n"
        f"  The Neurochip service is running in SIMULATOR fallback mode.\n"
        f"  No physical PYNQ-Z2 board was detected.\n"
        f"\n"
        f"  Checklist:\n"
        f"    □ Is the PYNQ-Z2 powered on and connected?\n"
        f"    □ Is NEUROCHIP_PYNQ_PYTHON set to the board's Python path?\n"
        f"      (or is `pynq` importable in the current Python environment?)\n"
        f"    □ Are the overlay assets installed?\n"
        f"      (snn_overlay.bit + snn_overlay.hwh + overlay_manifest.json)\n"
        f"\n"
        f"  Full response: {data}\n"
        f"══════════════════════════════════════════════════════════════"
    )


# ---------------------------------------------------------------------------
# Step 1 — Preflight: board must be online and in hardware mode
# ---------------------------------------------------------------------------


def test_pynq_preflight_confirms_real_hardware() -> None:
    """Preflight must report runtime_mode='hardware' and a non-failed status.

    This is the first and strongest hardware proof: the preflight endpoint
    calls probe_real_pynq_device_access() which opens the PYNQ device driver
    and fails fast if no board is present.
    """
    with httpx.Client(timeout=30.0) as client:
        resp = _get_or_fail(client, f"{_PYNQ_BASE}/preflight")
        assert resp.status_code == 200, (
            f"[PYNQ HW] Preflight endpoint returned {resp.status_code}: {resp.text}"
        )
        data = resp.json()

        # Hard proof: no simulator
        _assert_hardware_mode(data, step="preflight")

        preflight_status = data.get("preflight_status", "")
        assert preflight_status in {"ok", "degraded"}, (
            f"\n"
            f"  HARDWARE TEST FAILED — preflight status\n"
            f"  preflight_status : '{preflight_status}'\n"
            f"  message          : {data.get('preflight_message')}\n"
            f"  overlay_assets   : {data.get('overlay_assets')}\n"
            f"\n"
            f"  Overlay assets are not ready.  Run the launcher's Install Overlay step."
        )

        # Structured audit log: visible in pytest -s output and CI Step Summary
        print(f"\n{'═'*60}")
        print(f"  [PYNQ HW] PREFLIGHT — HARDWARE CONFIRMED")
        print(f"{'═'*60}")
        print(f"  runtime_mode     : {data.get('runtime_mode')}")
        print(f"  preflight_status : {data.get('preflight_status')}")
        print(f"  preflight_message: {data.get('preflight_message')}")
        print(f"  install_mode     : {data.get('install_mode')}")
        rt = data.get("runtime_details", {})
        if rt.get("effectivePynqPython"):
            print(f"  pynq_python      : {rt['effectivePynqPython']}")
        if rt.get("agentPackageVersion"):
            print(f"  agent_version    : {rt['agentPackageVersion']}")
        if data.get("resolved_paths"):
            print(f"  resolved_paths   : {data['resolved_paths']}")
        print(f"{'═'*60}")


# ---------------------------------------------------------------------------
# Step 2 — Deploy: require_hardware=true proves real FPGA overlay load
# ---------------------------------------------------------------------------


def test_pynq_deploy_on_real_hardware() -> None:
    """Deploy with require_hardware=true; HTTP 503 means no board found.

    The require_hardware flag makes the endpoint return 503 immediately
    when the backend is in simulator mode.  A 200 response with
    runtime_mode='hardware' is proof the FPGA overlay was loaded and
    weights were written via MMIO/DMA on real Zynq-7000 silicon.
    """
    with httpx.Client(timeout=60.0) as client:
        resp = _post_or_fail(
            client,
            f"{_PYNQ_BASE}/deploy",
            params={"require_hardware": "true"},
            json={"weights": _WEIGHTS, "require_hardware": True},
        )

        if resp.status_code == 503:
            detail = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else resp.text
            pytest.fail(
                f"\n"
                f"══════════════════════════════════════════════════════════════\n"
                f"  HARDWARE TEST FAILED — deploy returned HTTP 503\n"
                f"══════════════════════════════════════════════════════════════\n"
                f"  require_hardware=true was rejected: no physical PYNQ device detected.\n"
                f"  Response: {detail}\n"
                f"══════════════════════════════════════════════════════════════"
            )

        assert resp.status_code == 200, (
            f"[PYNQ HW] Deploy failed unexpectedly: {resp.status_code}\n{resp.text}"
        )
        data = resp.json()

        # Confirm hardware in deploy response
        _assert_hardware_mode(data, step="deploy")

        print(f"\n{'═'*60}")
        print(f"  [PYNQ HW] DEPLOY — FPGA OVERLAY LOADED ON REAL HARDWARE")
        print(f"{'═'*60}")
        print(f"  status           : {data.get('status')}")
        print(f"  runtime_mode     : {data.get('runtime_mode')}")
        print(f"  preflight_status : {data.get('preflight_status')}")
        print(f"  overlay_version  : {data.get('overlay_version')}")
        print(f"{'═'*60}")


# ---------------------------------------------------------------------------
# Step 3 — Status: confirm hardware mode is retained after deploy
# ---------------------------------------------------------------------------


def test_pynq_status_shows_hardware_after_deploy() -> None:
    """Status endpoint must report runtime_mode='hardware' after deploy."""
    with httpx.Client(timeout=30.0) as client:
        # Deploy first
        deploy_resp = _post_or_fail(
            client,
            f"{_PYNQ_BASE}/deploy",
            params={"require_hardware": "true"},
            json={"weights": _WEIGHTS, "require_hardware": True},
        )
        if deploy_resp.status_code == 503:
            pytest.fail("[PYNQ HW] Cannot confirm status — deploy returned 503 (no hardware).")
        assert deploy_resp.status_code == 200, f"Pre-deploy failed: {deploy_resp.text}"

        # Check status
        status_resp = _get_or_fail(client, f"{_PYNQ_BASE}/status")
        assert status_resp.status_code == 200, (
            f"[PYNQ HW] Status endpoint returned {status_resp.status_code}: {status_resp.text}"
        )
        data = status_resp.json()
        _assert_hardware_mode(data, step="status post-deploy")

        print(f"\n  [PYNQ HW] STATUS — runtime_mode={data.get('runtime_mode')}")
        print(f"  [PYNQ HW]           state={data.get('state')}")
        print(f"  [PYNQ HW]           install_mode={data.get('install_mode')}")
        print(f"  [PYNQ HW]           loop_running={data.get('loop_running')}")


# ---------------------------------------------------------------------------
# Step 4 — Inference: output spikes from the real FPGA
# ---------------------------------------------------------------------------


def test_pynq_run_inference_on_real_hardware() -> None:
    """Inference must return output spikes produced by the FPGA fabric.

    execution_time_us is logged as corroborating evidence.  A simulator
    cannot be in use because the deploy step required require_hardware=true
    and the status step confirmed runtime_mode='hardware'.
    """
    with httpx.Client(timeout=60.0) as client:
        # Deploy (hardware mode already proven by test order, but we re-deploy
        # to make this test self-contained and safe to run in isolation)
        deploy_resp = _post_or_fail(
            client,
            f"{_PYNQ_BASE}/deploy",
            params={"require_hardware": "true"},
            json={"weights": _WEIGHTS, "require_hardware": True},
        )
        if deploy_resp.status_code == 503:
            pytest.fail("[PYNQ HW] Cannot run inference — deploy returned 503 (no hardware).")
        assert deploy_resp.status_code == 200, f"Pre-deploy failed: {deploy_resp.text}"
        _assert_hardware_mode(deploy_resp.json(), step="deploy (before run)")

        # Run inference
        run_resp = _post_or_fail(
            client,
            f"{_PYNQ_BASE}/run",
            json={"input_spikes": _INPUT_SPIKES, "timesteps": 1},
        )
        assert run_resp.status_code == 200, (
            f"[PYNQ HW] Run failed: {run_resp.status_code}\n{run_resp.text}"
        )
        run_data = run_resp.json()

        assert "output_spikes" in run_data, (
            f"[PYNQ HW] No output_spikes in run response: {run_data}"
        )
        assert isinstance(run_data["output_spikes"], list), (
            f"[PYNQ HW] output_spikes must be a list, got: {type(run_data['output_spikes'])}"
        )
        assert "execution_time_us" in run_data, (
            f"[PYNQ HW] No execution_time_us in run response: {run_data}"
        )

        exec_us: float = float(run_data.get("execution_time_us", 0))
        assert exec_us > 0, (
            f"[PYNQ HW] execution_time_us must be > 0, got {exec_us}"
        )

        print(f"\n{'═'*60}")
        print(f"  [PYNQ HW] INFERENCE — REAL FPGA OUTPUT")
        print(f"{'═'*60}")
        print(f"  input_spikes      : {_INPUT_SPIKES}")
        print(f"  output_spikes     : {run_data['output_spikes']}")
        print(f"  execution_time_us : {exec_us:.1f} µs")
        print(f"  timesteps         : {run_data.get('timesteps', 1)}")
        print(f"{'═'*60}")


# ---------------------------------------------------------------------------
# Step 5 — SITL verification: structured stimulus → output matrix
# ---------------------------------------------------------------------------


def test_pynq_sitl_verify_on_real_hardware() -> None:
    """Run multiple stimulus cases through the real FPGA and log the I/O matrix.

    The /verify endpoint deploys a fresh backend then runs each stimulus case
    through the FPGA, recording per-case output spikes and execution time.
    No expected_output_spikes are asserted here because the network weights
    are minimal — the goal is proving the FPGA executes all cases without
    errors and producing a timestamped I/O record.
    """
    with httpx.Client(timeout=60.0) as client:
        verify_resp = _post_or_fail(
            client,
            f"{_PYNQ_BASE}/verify",
            json={
                "weights": _WEIGHTS,
                "stimulus_cases": [
                    {
                        "label": "zero_input",
                        "input_spikes": [0, 0],
                        "expected_output_spikes": None,
                        "timesteps": 1,
                    },
                    {
                        "label": "channel_0_only",
                        "input_spikes": [1, 0],
                        "expected_output_spikes": None,
                        "timesteps": 1,
                    },
                    {
                        "label": "channel_1_only",
                        "input_spikes": [0, 1],
                        "expected_output_spikes": None,
                        "timesteps": 1,
                    },
                    {
                        "label": "full_input",
                        "input_spikes": [1, 1],
                        "expected_output_spikes": None,
                        "timesteps": 1,
                    },
                ],
            },
        )
        assert verify_resp.status_code == 200, (
            f"[PYNQ HW] SITL verify failed: {verify_resp.status_code}\n{verify_resp.text}"
        )
        verify_data = verify_resp.json()

        total = verify_data.get("total_cases", 0)
        passed = verify_data.get("passed_cases", 0)
        mean_us: float = float(verify_data.get("mean_exec_us", 0))
        max_us: float = float(verify_data.get("max_exec_us", 0))

        assert total > 0, "[PYNQ HW] No stimulus cases were run by verify."

        print(f"\n{'═'*60}")
        print(f"  [PYNQ HW] SITL VERIFY — REAL FPGA I/O MATRIX")
        print(f"{'═'*60}")
        print(f"  summary          : {verify_data.get('summary')}")
        print(f"  total_cases      : {total}")
        print(f"  passed_cases     : {passed}")
        print(f"  mean_exec_us     : {mean_us:.1f} µs")
        print(f"  max_exec_us      : {max_us:.1f} µs")
        print(f"\n  Stimulus → FPGA Output Matrix:")
        print(f"  {'Label':<20} {'Input':<12} {'Output':<20} {'Time (µs)'}")
        print(f"  {'-'*20} {'-'*12} {'-'*20} {'-'*12}")
        for step in verify_data.get("steps", []):
            print(
                f"  {step['label']:<20} "
                f"{str(step['input_spikes']):<12} "
                f"{str(step['output_spikes']):<20} "
                f"{step['execution_time_us']:.1f}"
            )
        print(f"{'═'*60}")

        # Every case must complete without an exception from the FPGA
        # (passed=False only when expected_output_spikes doesn't match; we
        # set them all to None so passed should always be True here)
        for step in verify_data.get("steps", []):
            assert step.get("passed") is True, (
                f"[PYNQ HW] SITL case '{step['label']}' reported passed=False "
                f"(output={step['output_spikes']}, expected={step['expected_output_spikes']})"
            )
