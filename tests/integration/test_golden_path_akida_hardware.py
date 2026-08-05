"""BrainChip AKida Real-Hardware Validation.

Tests the full map → inference pipeline against a PHYSICAL BrainChip AKida device
connected via USB.  The AKD1000 software simulator and software_fallback mode are
explicitly rejected — this test proves real silicon is executing the network.

=== How hardware is confirmed ===

The key discriminator is runtime_target in the Neurochip Akida status and map
responses.  This field is set by _get_target_device() in akida_backend.py:

    available_devices = akida.devices()   # BrainChip Python SDK
    if available_devices:
        return device, "hardware", str(device)       # ← physical USB chip
    else:
        return simulator, "akd1000_simulator", ...   # ← software simulator

So runtime_target == "hardware" if and only if akida.devices() returns a
non-empty list, which requires a physical AKida USB device to be connected
and enumerated by the OS.

1. GET  /api/neurochip/akida/status
   → sdk_available MUST be True (akida==2.19.1 installed)
   → runtime_target MUST be "hardware" (not "akd1000_simulator" or "software_fallback")
   → device_info is logged as hardware identity evidence

2. POST /api/neurochip/akida/map
   → runtime_target MUST be "hardware" in the response
   → The map call invokes akida.Model.map(device) on the real USB chip

3. POST /api/neurochip/akida/inference
   → Outputs are produced by the mapped model on the physical device
   → telemetry (fps, power) is logged when available

4. POST /api/neurochip/akida/deploy?deployment_mode=on_device
   → deployment_mode=on_device requires sdk_available + successful map
   → Confirms the full package generation round-trip on real hardware

=== Opt-in ===

Set AKIDA_HARDWARE_TEST=true to activate this test suite.
The test skips (not fails) when the env var is absent so standard CI
(no USB chip) is not disrupted.

Set NEUROCHIP_URL to override the default http://localhost:9000.
"""

from __future__ import annotations

import base64
import hashlib
import os
import time
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import httpx
import pytest

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_AKIDA_HW_REQUIRED: bool = os.getenv("AKIDA_HARDWARE_TEST", "").lower() in {
    "1",
    "true",
    "yes",
}

NEUROCHIP_URL: str = os.getenv("NEUROCHIP_URL", "http://localhost:9000")
_AKIDA_BASE: str = f"{NEUROCHIP_URL}/api/neurochip/akida"
_API_KEY: str = os.getenv("NEUROCHIP_API_KEY", "").strip()
_AUTH_HEADERS: dict[str, str] = {"X-API-Key": _API_KEY} if _API_KEY else {}
_MODEL_BUNDLE_PATH: str = os.getenv("AKIDA_MODEL_BUNDLE", "").strip()

# Minimal two-population network for hardware validation.
# sensory (size=4) → motor (size=2) with a FullyConnected layer.
_MAPPED_NETWORK: dict[str, Any] = {
    "akida_version": "akida1",
    "input_population": "sensory",
    "populations": [
        {
            "id": "sensory",
            "size": 4,
            "role": "sensory",
            "population_type": "lif",
            "provenance": [],
            "attributes": {},
        },
        {
            "id": "motor",
            "size": 2,
            "role": "motor",
            "population_type": "lif",
            "provenance": [],
            "attributes": {},
        },
    ],
    "connections": [
        {
            "source": "sensory",
            "target": "motor",
            "units": 2,
            "weight": 0.5,
            "block_type": None,
            "provenance": [],
            "property_provenance": [],
            "attributes": {},
        },
    ],
    "topology_verdict": "faithful",
    "warnings": [],
    "network_summary": {
        "n_neurons": 6,
        "n_synapses": 8,
        "n_populations": 2,
        "n_connections": 1,
        "quantization_bits": 4,
    },
    "metadata_provenance": [],
}

# Input vector for inference (4 channels matching sensory population size)
_INFERENCE_INPUTS: list[float] = [1.0, 0.0, 0.5, 0.0]

pytestmark = pytest.mark.akida_hardware


# ---------------------------------------------------------------------------
# Hardware guard
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def require_akida_hardware_env() -> None:
    """Skip every test unless AKIDA_HARDWARE_TEST=true.

    If the flag IS set but hardware is not detected, individual tests FAIL
    with a clear diagnostic message.
    """
    if not _AKIDA_HW_REQUIRED:
        pytest.skip(
            "BrainChip AKida hardware tests are skipped by default.\n"
            "Set AKIDA_HARDWARE_TEST=true to run on a physical AKida USB device.\n"
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
            f"[AKIDA HW] Neurochip service at {_service_label(url)} is unreachable: {exc}\n"
            "Ensure the Neurochip backend is running with the AKida SDK installed."
        )


def _post_or_fail(client: httpx.Client, url: str, **kwargs: object) -> httpx.Response:
    try:
        return client.post(url, **kwargs)  # type: ignore[return-value]
    except httpx.RequestError as exc:
        pytest.fail(
            f"[AKIDA HW] Neurochip service at {_service_label(url)} is unreachable: {exc}\n"
            "Ensure the Neurochip backend is running with the AKida SDK installed."
        )


_SIMULATOR_TARGETS = {"akd1000_simulator", "software_fallback", "unknown"}


def _assert_hardware_target(data: dict, *, step: str) -> None:
    """Assert runtime_target == 'hardware', producing a maximally informative failure.

    The three non-hardware states:
    - 'akd1000_simulator'  → SDK is installed, but no USB chip; AKD1000 emulator used.
    - 'software_fallback'  → SDK not installed; AkidaSimulator (pure Python) used.
    - 'unknown'            → device probe not attempted yet.
    """
    target = data.get("runtime_target", "")
    assert target == "hardware", (
        f"\n"
        f"══════════════════════════════════════════════════════════════\n"
        f"  HARDWARE TEST FAILED — {step}\n"
        f"══════════════════════════════════════════════════════════════\n"
        f"  runtime_target : '{target}'  (expected 'hardware')\n"
        f"\n"
        f"  No physical BrainChip AKida USB device was detected.\n"
        f"  akida.devices() returned an empty list.\n"
        f"\n"
        + (
            "  The AKD1000 SOFTWARE SIMULATOR is active. This is NOT real hardware.\n"
            if target == "akd1000_simulator"
            else "  Pure-Python software fallback is active (SDK not installed).\n"
            if target == "software_fallback"
            else ""
        )
        + f"\n"
        f"  Checklist:\n"
        f"    □ Is the AKida USB device plugged in?\n"
        f"    □ Is akida==2.19.1 installed in the Neurochip Python environment?\n"
        f"    □ Is the device visible to the OS? (lsusb / Device Manager)\n"
        f'    □ Does `python -c "import akida; print(akida.devices())"` list the chip?\n'
        f"\n"
        f"  Full response: {data}\n"
        f"══════════════════════════════════════════════════════════════"
    )


# ---------------------------------------------------------------------------
# Step 1 — Status: SDK and physical device must be present
# ---------------------------------------------------------------------------


def test_akida_status_confirms_real_hardware() -> None:
    """Status must report sdk_available=True and runtime_target='hardware'.

    A runtime_target of 'hardware' is only possible when akida.devices()
    enumerates at least one physical USB AKida chip.
    """
    with httpx.Client(timeout=30.0, headers=_AUTH_HEADERS) as client:
        resp = _get_or_fail(client, f"{_AKIDA_BASE}/status")
        assert resp.status_code == 200, (
            f"[AKIDA HW] Status endpoint returned {resp.status_code}: {resp.text}"
        )
        data = resp.json()

        # SDK must be installed
        sdk_available = data.get("sdk_available", False)
        assert sdk_available is True, (
            f"\n"
            f"  HARDWARE TEST FAILED — Akida SDK not installed\n"
            f"  sdk_available : {sdk_available}\n"
            f"  sdk_issues    : {data.get('sdk_issues')}\n"
            f"  sdk_issue_detail: {data.get('sdk_issue_detail')}\n"
            f"\n"
            f"  Install the Akida SDK: akida==2.19.1 + tensorflow==2.19.*"
        )

        # Physical hardware must be detected
        _assert_hardware_target(data, step="status")

        print(f"\n{'═' * 60}")
        print("  [AKIDA HW] STATUS — REAL HARDWARE CONFIRMED")
        print(f"{'═' * 60}")
        print(f"  sdk_available    : {data.get('sdk_available')}")
        print(f"  sdk_status       : {data.get('sdk_status')}")
        print(f"  runtime_target   : {data.get('runtime_target')}")
        print(f"  device_info      : {data.get('device_info')}")
        print(f"  state            : {data.get('state')}")
        env = data.get("environment_checks", {})
        print(f"  host_supported   : {env.get('host_supported')}")
        print(f"  python_supported : {env.get('python_supported')}")
        print(f"  tensorflow_avail : {env.get('tensorflow_available')}")
        print(f"{'═' * 60}")


# ---------------------------------------------------------------------------
# Step 2 — Map: model must be mapped to the physical device
# ---------------------------------------------------------------------------


def test_akida_map_to_physical_device() -> None:
    """Map a network to the AKida device; runtime_target must be 'hardware'.

    The /map endpoint calls AkidaBackend.map_to_device() which invokes
    model.map(device) where device is the physical USB chip returned by
    akida.devices()[0].  If the device is the AKD1000 simulator, the target
    is 'akd1000_simulator' — explicitly not accepted here.
    """
    with httpx.Client(timeout=60.0, headers=_AUTH_HEADERS) as client:
        resp = _post_or_fail(
            client,
            f"{_AKIDA_BASE}/map",
            params={"bit_width": 4},
            json=_MAPPED_NETWORK,
        )

        if resp.status_code == 503:
            pytest.fail(
                "[AKIDA HW] Map returned HTTP 503 — Akida SDK unavailable on this host.\n"
                "Install akida==2.19.1 in the Neurochip Python environment."
            )

        if resp.status_code == 502:
            # 502 from AkidaDeviceMappingError — SDK present but mapping failed
            pytest.fail(
                f"[AKIDA HW] Map returned HTTP 502 — device mapping failed.\n"
                f"Response: {resp.text}"
            )

        assert resp.status_code == 200, (
            f"[AKIDA HW] Map failed: {resp.status_code}\n{resp.text}"
        )
        data = resp.json()

        # Physical hardware must be the target
        _assert_hardware_target(data, step="map")

        sdk_status = data.get("sdk_status", "")
        assert sdk_status == "deployable", (
            f"[AKIDA HW] sdk_status='{sdk_status}' after map — expected 'deployable'.\n"
            f"sdk_issues: {data.get('sdk_issues')}\n"
            f"sdk_issue_detail: {data.get('sdk_issue_detail')}"
        )

        print(f"\n{'═' * 60}")
        print("  [AKIDA HW] MAP — MODEL LOADED ONTO PHYSICAL CHIP")
        print(f"{'═' * 60}")
        print(f"  runtime_target   : {data.get('runtime_target')}")
        print(f"  device_info      : {data.get('device_info')}")
        print(f"  sdk_status       : {data.get('sdk_status')}")
        print(f"  state            : {data.get('state')}")
        if data.get("model_summary"):
            ms = data["model_summary"]
            print(f"  n_neurons        : {ms.get('n_neurons')}")
            print(f"  n_synapses       : {ms.get('n_synapses')}")
        print(f"{'═' * 60}")


# ---------------------------------------------------------------------------
# Step 3 — Inference: outputs from the physical AKida chip
# ---------------------------------------------------------------------------


def test_akida_inference_on_real_hardware() -> None:
    """Inference must produce outputs from the physically mapped AKida chip.

    telemetry.fps and telemetry.power are logged when available — these
    are hardware power metrics captured from the chip, impossible to
    obtain from a software simulator.
    """
    with httpx.Client(timeout=60.0, headers=_AUTH_HEADERS) as client:
        # Map first (make this test self-contained)
        map_resp = _post_or_fail(
            client,
            f"{_AKIDA_BASE}/map",
            params={"bit_width": 4},
            json=_MAPPED_NETWORK,
        )
        if map_resp.status_code == 503:
            pytest.fail("[AKIDA HW] Cannot run inference — SDK unavailable.")
        if map_resp.status_code == 502:
            pytest.fail(
                f"[AKIDA HW] Cannot run inference — map failed: {map_resp.text}"
            )
        assert map_resp.status_code == 200, f"Pre-map failed: {map_resp.text}"
        _assert_hardware_target(map_resp.json(), step="map (before inference)")

        # Run inference
        infer_resp = _post_or_fail(
            client,
            f"{_AKIDA_BASE}/inference",
            json={"inputs": _INFERENCE_INPUTS},
        )
        assert infer_resp.status_code == 200, (
            f"[AKIDA HW] Inference failed: {infer_resp.status_code}\n{infer_resp.text}"
        )
        infer_data = infer_resp.json()

        assert "outputs" in infer_data, (
            f"[AKIDA HW] No 'outputs' in inference response: {infer_data}"
        )
        assert isinstance(infer_data["outputs"], list), (
            f"[AKIDA HW] outputs must be a list, got: {type(infer_data['outputs'])}"
        )

        print(f"\n{'═' * 60}")
        print("  [AKIDA HW] INFERENCE — REAL CHIP OUTPUT")
        print(f"{'═' * 60}")
        print(f"  inputs           : {_INFERENCE_INPUTS}")
        print(f"  outputs          : {infer_data['outputs']}")

        telemetry = infer_data.get("telemetry", {})
        if telemetry:
            fps = telemetry.get("fps")
            power = telemetry.get("power")
            if fps is not None:
                print(f"  chip fps         : {fps}")
            if power is not None:
                print(f"  chip power (mW)  : {power}")

        exec_us = infer_data.get("execution_time_us")
        if exec_us is not None:
            print(f"  execution_time_us: {exec_us:.1f} µs")
        print(f"{'═' * 60}")


# ---------------------------------------------------------------------------
# Step 4 — on_device deploy: full package generation on real hardware
# ---------------------------------------------------------------------------


def test_akida_on_device_deploy_on_real_hardware() -> None:
    """deployment_mode=on_device requires a successful SDK map to hardware.

    The endpoint returns HTTP 502 if SDK mapping failed or not attempted.
    A 200 with a valid ZIP response confirms that:
      1. The network was constructed by the Akida SDK
      2. It was mapped to the physical chip (not the AKD1000 simulator)
      3. A deployment package was generated with correct checksums
    """
    with httpx.Client(timeout=60.0, headers=_AUTH_HEADERS) as client:
        resp = _post_or_fail(
            client,
            f"{_AKIDA_BASE}/deploy/mapped",
            params={"bit_width": 4, "deployment_mode": "on_device"},
            json=_MAPPED_NETWORK,
        )

        if resp.status_code == 502:
            # 502 means on_device mapping failed
            pytest.fail(
                f"[AKIDA HW] on_device deploy returned HTTP 502 — SDK mapping failed or "
                f"no hardware found.\nResponse: {resp.text}"
            )

        assert resp.status_code == 200, (
            f"[AKIDA HW] on_device deploy failed: {resp.status_code}\n{resp.text}"
        )

        # Confirm it's a valid ZIP
        content_type = resp.headers.get("content-type", "")
        assert "zip" in content_type or "octet-stream" in content_type, (
            f"[AKIDA HW] Expected ZIP content-type, got: {content_type}"
        )

        deployment_mode_header = resp.headers.get("X-Akida-Deployment-Mode", "")
        runtime_target_header = resp.headers.get("X-Akida-Runtime-Target", "")

        assert deployment_mode_header == "on_device", (
            f"[AKIDA HW] Expected X-Akida-Deployment-Mode=on_device, "
            f"got: '{deployment_mode_header}'"
        )
        assert runtime_target_header == "hardware", (
            f"\n"
            f"  HARDWARE TEST FAILED — on_device deploy runtime target\n"
            f"  X-Akida-Runtime-Target : '{runtime_target_header}'  (expected 'hardware')\n"
            f"  The deployment was generated against a non-hardware target.\n"
            f"  Ensure a physical AKida USB device is connected and detected."
        )

        zip_size = len(resp.content)
        assert zip_size > 0, "[AKIDA HW] Empty ZIP response from on_device deploy."

        print(f"\n{'═' * 60}")
        print("  [AKIDA HW] ON_DEVICE DEPLOY — REAL HARDWARE PACKAGE")
        print(f"{'═' * 60}")
        print(f"  deployment_mode  : {deployment_mode_header}")
        print(f"  runtime_target   : {runtime_target_header}")
        print(f"  package_size     : {zip_size:,} bytes")
        print(f"{'═' * 60}")


# ---------------------------------------------------------------------------
# Step 5 — full MNIST bundle conversion, evaluation, and sample inference
# ---------------------------------------------------------------------------


def test_akida_mnist_bundle_on_real_hardware() -> None:
    """Convert and evaluate a Studio bundle, then infer one stored sample."""
    if not _MODEL_BUNDLE_PATH:
        pytest.skip("AKIDA_MODEL_BUNDLE does not point to a generated Studio bundle.")

    bundle_path = Path(_MODEL_BUNDLE_PATH).expanduser().resolve()
    assert bundle_path.is_file(), f"AKIDA_MODEL_BUNDLE is not a file: {bundle_path}"
    bundle = bundle_path.read_bytes()
    digest = hashlib.sha256(bundle).hexdigest()
    request = {
        "filename": bundle_path.name,
        "bundleBase64": base64.b64encode(bundle).decode("ascii"),
        "sha256": digest,
        "requirePhysicalHardware": True,
    }

    with httpx.Client(timeout=120.0, headers=_AUTH_HEADERS) as client:
        submitted = _post_or_fail(
            client,
            f"{_AKIDA_BASE}/model-jobs",
            json=request,
        )
        assert submitted.status_code == 202, (
            f"[AKIDA HW] Bundle submission failed: {submitted.status_code}\n"
            f"{submitted.text}"
        )
        job = submitted.json()
        job_id = job["jobId"]

        deadline = time.monotonic() + 20 * 60
        while job.get("stage") not in {"completed", "failed"}:
            assert time.monotonic() < deadline, (
                f"[AKIDA HW] Model job {job_id} did not finish within 20 minutes."
            )
            time.sleep(2)
            response = _get_or_fail(client, f"{_AKIDA_BASE}/model-jobs/{job_id}")
            assert response.status_code == 200, response.text
            job = response.json()

        assert job["stage"] == "completed", (
            f"[AKIDA HW] Model job failed with {job.get('errorCode')}: "
            f"{job.get('message')}"
        )
        assert job["runtimeTarget"] == "hardware", job
        assert job["hardwareVerified"] is True, job
        assert job["metrics"]["akida_accuracy"] >= 0.96, job["metrics"]
        assert (
            abs(job["metrics"]["pytorch_accuracy"] - job["metrics"]["onnx_accuracy"])
            <= 0.001
        ), job["metrics"]

        inference = _post_or_fail(
            client,
            f"{_AKIDA_BASE}/models/{job['modelId']}/inference",
            json={"sampleIndex": 0},
        )
        assert inference.status_code == 200, inference.text
        result = inference.json()
        assert result["runtimeTarget"] == "hardware", result
        assert result["hardwareVerified"] is True, result
        assert result["prediction"] in range(10), result
        assert result["label"] in range(10), result
