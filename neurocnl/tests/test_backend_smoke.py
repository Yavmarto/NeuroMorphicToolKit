import os
import socket
import subprocess
import sys
import tempfile
import time

import pytest

if os.getenv("NEUROCNL_RUN_BACKEND_SMOKE") != "1":
    pytest.skip(
        "Set NEUROCNL_RUN_BACKEND_SMOKE=1 to run backend smoke test.",
        allow_module_level=True,
    )

httpx = pytest.importorskip("httpx")
pytest.importorskip("uvicorn")

SERVER_READY_RETRIES = 30
SERVER_READY_RETRY_INTERVAL_SECONDS = 1
MAX_POLL_RETRIES = 120
POLL_INTERVAL_SECONDS = 0.5
SERVER_STARTUP_ATTEMPTS = 3


def _get_ephemeral_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


@pytest.fixture(scope="module")
def backend_server():
    """Start the FastAPI backend server as a separate process."""
    # Ensure we are in the root directory for imports to work
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    # Start the server
    # We need to set PYTHONPATH to root so 'backend' and 'neurocnl' can be imported
    env = os.environ.copy()
    env["PYTHONPATH"] = (
        root_dir if not env.get("PYTHONPATH") else f"{root_dir}{os.pathsep}{env['PYTHONPATH']}"
    )

    with tempfile.TemporaryDirectory(prefix="neurocnl-smoke-") as temp_cwd:
        last_failure = "No startup attempts were made."
        for attempt in range(1, SERVER_STARTUP_ATTEMPTS + 1):
            port = _get_ephemeral_port()
            log_path = os.path.join(temp_cwd, f"uvicorn-attempt-{attempt}.log")
            with open(log_path, "w+", encoding="utf-8") as log_file:
                process = subprocess.Popen(
                    [
                        sys.executable,
                        "-m",
                        "uvicorn",
                        "backend.app.main:app",
                        "--host",
                        "127.0.0.1",
                        "--port",
                        str(port),
                    ],
                    cwd=temp_cwd,
                    env=env,
                    stdout=log_file,
                    stderr=log_file,
                    text=True,
                )

                # Wait for the server to be ready
                ready = False
                url = f"http://127.0.0.1:{port}"
                with httpx.Client(base_url=url) as client:
                    for _ in range(SERVER_READY_RETRIES):
                        if process.poll() is not None:
                            break
                        try:
                            response = client.get("/health", timeout=1.0)
                            if response.status_code == 200:
                                ready = True
                                break
                        except httpx.RequestError:
                            pass
                        time.sleep(SERVER_READY_RETRY_INTERVAL_SECONDS)

                if ready:
                    try:
                        yield url
                    finally:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                    return

                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                log_file.seek(0)
                log_output = log_file.read()
                last_failure = (
                    f"Attempt {attempt}/{SERVER_STARTUP_ATTEMPTS} failed on port {port} "
                    f"(return code: {process.returncode}).\nLog output:\n{log_output}"
                )

        pytest.fail(
            f"Backend server failed to start after {SERVER_STARTUP_ATTEMPTS} attempts.\n{last_failure}"
        )


def test_studio_backend_flow_smoke(backend_server):
    """
    Smoke test exercising the main Studio backend flow:
    1. List templates
    2. Validate a template spec
    3. Execute a simulation job
    4. Fetch the result
    """
    base_url = backend_server

    with httpx.Client(base_url=base_url, timeout=10.0) as client:
        # 1. List templates
        resp = client.get("/api/templates")
        assert resp.status_code == 200, f"Failed to list templates: {resp.text}"
        templates_data = resp.json()
        assert "templates" in templates_data
        assert len(templates_data["templates"]) > 0

        # Pick the 'reflex_arc' template
        template = next((t for t in templates_data["templates"] if t["id"] == "reflex_arc"), None)
        assert template is not None, "reflex_arc template not found"
        spec = template["spec"]
        assert spec

        # 2. Validate the template spec
        val_resp = client.post(
            "/api/validate", json={"spec": spec, "params": {}, "backend": "nengo"}
        )
        assert val_resp.status_code == 200, f"Validation failed: {val_resp.text}"
        val_data = val_resp.json()
        assert val_data["overall"] is True
        assert val_data["layer1"]["overall"] is True
        assert val_data["layer2"]["overall"] is True

        # 3. Execute a simulation job
        sim_resp = client.post("/api/simulate", json={"spec": spec, "duration": 0.5, "dt": 0.001})
        assert sim_resp.status_code == 202, f"Simulation trigger failed: {sim_resp.text}"
        job_data = sim_resp.json()
        assert "job_id" in job_data
        job_id = job_data["job_id"]

        # 4. Fetch/Poll for the result
        completed = False
        last_status_data = None
        for _ in range(MAX_POLL_RETRIES):
            job_resp = client.get(f"/api/jobs/{job_id}")
            assert job_resp.status_code == 200
            status_data = job_resp.json()
            last_status_data = status_data

            if status_data["status"] == "complete":
                completed = True
                result = status_data["result"]
                assert result["duration"] == 0.5
                assert "probes" in result
                assert "summary" in result
                break
            elif status_data["status"] == "failed":
                pytest.fail(f"Job failed: {status_data.get('error')}")

            time.sleep(POLL_INTERVAL_SECONDS)

        assert completed is True, (
            f"Simulation job did not complete in time. Last status: {last_status_data}"
        )
