import os
import subprocess
import time

import pytest
import requests


@pytest.fixture(scope="module", autouse=True)
def backend_server():
    """Start the FastAPI backend server."""
    # Ensure we are in the root directory
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

    # Use a custom port to avoid conflicts
    port = 8099

    # Start the server
    process = subprocess.Popen(
        ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", str(port)],
        cwd=root_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    # Wait for the server to be ready
    max_retries = 30
    ready = False
    for _ in range(max_retries):
        try:
            response = requests.get(f"http://localhost:{port}/health")
            if response.status_code == 200:
                ready = True
                break
        except requests.exceptions.ConnectionError:
            pass
        time.sleep(1)

    if not ready:
        process.terminate()
        stdout, stderr = process.communicate()
        pytest.fail(f"Backend server failed to start.\nSTDOUT: {stdout}\nSTDERR: {stderr}")

    yield f"http://localhost:{port}"

    # Terminate the server
    process.terminate()
    process.wait()


def test_export_flow(backend_server: str):
    """Trigger at least one export flow and verify the returned payload looks structurally valid."""
    spec = (
        "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The sensory neuron membrane potential MUST decay WITH time constant of 0.05 seconds\n"
        "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
        "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The motor neuron membrane potential MUST decay WITH time constant of 0.05 seconds\n"
        "The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
        "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0\n"
    )

    response = requests.post(
        f"{backend_server}/api/export",
        json={"spec": spec, "format": "lava", "filename": "spec.cnl"},
        timeout=10,
    )

    assert response.status_code == 200, (
        f"Expected 200, got {response.status_code}. Response: {response.text}"
    )
    content = response.text

    # Assert structural validity for lava format which is python code
    assert "import" in content
    assert "from lava" in content or "lava" in content.lower()
    assert "class" in content or "Process" in content or "Model" in content
    assert "sensory" in content.lower()
    assert "motor" in content.lower()


def test_async_simulation_job_polling(backend_server: str):
    """Exercise an async simulation job that returns 202, poll /api/jobs/{job_id}, and assert completion payload shape."""
    spec = (
        "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The sensory neuron membrane potential MUST decay WITH time constant of 0.05 seconds\n"
        "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
        "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The motor neuron membrane potential MUST decay WITH time constant of 0.05 seconds\n"
        "The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
        "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0\n"
    )

    response = requests.post(
        f"{backend_server}/api/simulate",
        json={"spec": spec, "duration": 2.0},
        timeout=10,
    )

    assert response.status_code == 202, (
        f"Expected 202, got {response.status_code}. Response: {response.text}"
    )
    job_data = response.json()
    assert "job_id" in job_data
    assert job_data["status"] == "queued" or job_data["status"] == "running"

    job_id = job_data["job_id"]

    # Poll the job
    max_polls = 20
    poll_interval = 0.5
    for _ in range(max_polls):
        poll_response = requests.get(f"{backend_server}/api/jobs/{job_id}", timeout=5)
        assert poll_response.status_code == 200
        poll_data = poll_response.json()
        if poll_data["status"] == "complete":
            break
        elif poll_data["status"] == "failed":
            pytest.fail(f"Job failed: {poll_data.get('error')}")
        time.sleep(poll_interval)
    else:
        pytest.fail("Job did not complete within the expected time.")

    # Verify the final job payload includes the key PipelineResultContract fields expected by the UI.
    result = poll_data.get("result", {})
    assert result is not None
    assert "duration" in result
    assert "dt" in result
    assert "timesteps" in result
    assert "probes" in result
    assert "summary" in result
    assert "wall_time_seconds" in result

    # Summary should have specific fields
    summary = result["summary"]
    assert "sensory_spike_count" in summary
    assert "motor_spike_count" in summary
