import io
import subprocess
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app

client = TestClient(app)


def get_mock_network(neuron_model="LIF"):
    return {
        "num_neurons": 100,
        "num_synapses": 1000,
        "neuron_model": neuron_model,
        "populations": [{"name": "pop1", "size": 100}],
        "connections": [{"pre": "pop1", "post": "pop1", "weight_count": 1000}],
        "weight_bit_width": 32,
        "network_depth": 10,
    }


@pytest.mark.parametrize("target_id", ["akida", "brainscales", "loihi2", "spinnaker", "teensy41"])
def test_full_pipeline_success(target_id):
    # 1. Select Target
    response = client.get(f"/api/neurochip/targets/{target_id}")
    assert response.status_code == 200
    target = response.json()

    # 2. Quantize (using first supported bit width)
    bit_width = target["weight_bit_widths"][0]
    target_name = target["name"]
    response = client.post(
        f"/api/neurochip/quantize?bit_width={bit_width}&target_device={target_name}",
        json=get_mock_network(),
    )
    assert response.status_code == 200
    response.json()

    # 3. Export (Compile)
    # Different targets have different export endpoints
    if target_id == "teensy41":
        response = client.post(
            f"/api/neurochip/export/teensy?bit_width={bit_width}",
            json=get_mock_network(),
        )
    elif target_id == "loihi2":
        # Loihi endpoint takes NetworkInput directly
        response = client.post(
            f"/api/neurochip/export/loihi?bit_width={bit_width}",
            json=get_mock_network(),
        )
    elif target_id == "akida":
        # Akida endpoint takes NetworkInput in "network" wrapper
        response = client.post(
            "/api/neurochip/export/akida",
            json={"network": get_mock_network()},
        )
    elif target_id == "brainscales":
        response = client.post(
            f"/api/neurochip/export/brainscales?bit_width={bit_width}",
            json={"network": get_mock_network()},
        )
    elif target_id == "spinnaker":
        response = client.post(
            f"/api/neurochip/export/spinnaker?bit_width={bit_width}",
            json={"network": get_mock_network()},
        )
    else:
        pytest.fail(f"Unsupported target: {target_id}")

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"


def test_unsupported_model():
    # BrainScaleS might not support a custom model
    response = client.get("/api/neurochip/targets/brainscales")
    target = response.json()
    supported = target["supported_neuron_models"]

    unsupported_model = "ComplexNonLinearModel"
    assert unsupported_model not in supported

    # Analyze should report unsupported feature
    response = client.post(
        "/api/neurochip/analyze?target_id=brainscales",
        json=get_mock_network(neuron_model=unsupported_model),
    )
    assert response.status_code == 200
    data = response.json()
    assert any("not supported" in feature for feature in data["unsupported_features"])


@patch("subprocess.run")
def test_failed_compilation(mock_run):
    # Mock subprocess.run to return non-zero exit code
    mock_run.return_value = MagicMock(returncode=1, stderr="Error: build failed")

    # Create a valid zip with required structure
    import zipfile

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "a", zipfile.ZIP_DEFLATED, False) as zip_file:
        zip_file.writestr("neurochip_firmware/platformio.ini", "[env:teensy41]")

    file = ("test.zip", io.BytesIO(zip_buffer.getvalue()), "application/zip")

    # Start flash job
    response = client.post(
        "/api/neurochip/serial/flash", files={"file": file}, data={"port": "/dev/ttyACM0"}
    )
    assert response.status_code == 200
    job_id = response.json()["job_id"]

    # Poll until failed (in-memory job so it might be fast)
    import time

    for _ in range(10):
        response = client.get(f"/api/neurochip/serial/flash/{job_id}")
        if response.json()["status"] == "failed":
            break
        time.sleep(0.1)

    assert response.json()["status"] == "failed"
    assert "Compilation failed" in response.json()["error"]


@patch("subprocess.run")
def test_flash_timeout(mock_run):
    # Mock subprocess.run to raise TimeoutExpired
    mock_run.side_effect = subprocess.TimeoutExpired(cmd=["pio", "run"], timeout=120)

    # Create a valid zip with required structure
    import zipfile

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "a", zipfile.ZIP_DEFLATED, False) as zip_file:
        zip_file.writestr("neurochip_firmware/platformio.ini", "[env:teensy41]")

    file = ("test.zip", io.BytesIO(zip_buffer.getvalue()), "application/zip")

    response = client.post(
        "/api/neurochip/serial/flash", files={"file": file}, data={"port": "/dev/ttyACM0"}
    )
    job_id = response.json()["job_id"]

    import time

    for _ in range(10):
        response = client.get(f"/api/neurochip/serial/flash/{job_id}")
        if response.json()["status"] == "failed":
            break
        time.sleep(0.1)

    assert response.json()["status"] == "failed"
    assert "timed out" in response.json()["error"]
