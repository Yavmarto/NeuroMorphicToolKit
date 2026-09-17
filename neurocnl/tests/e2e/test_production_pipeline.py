import os
import subprocess
import time

import pytest
import requests

pytest.importorskip("playwright")
from playwright.sync_api import Page, expect


@pytest.fixture(scope="module", autouse=True)
def backend_server():
    """Start the FastAPI backend server."""
    # Ensure we are in the root directory
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

    # Use a custom port to avoid conflicts
    port = 8000

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
        stdout, stderr = process.communicate()
        pytest.fail(f"Backend server failed to start.\nSTDOUT: {stdout}\nSTDERR: {stderr}")

    yield f"http://localhost:{port}"

    # Terminate the server
    process.terminate()
    process.wait()


def test_pipeline(page: Page, backend_server: str):
    """Test the full simulation pipeline from the Studio UI."""
    page.goto(backend_server)

    # Handle Setup Screen if it appears
    if "/#/setup" in page.url:
        page.click("text=Check Connection")
        expect(page.get_by_text("Connected to neurocnl backend")).to_be_visible(timeout=10000)
        page.click("text=Save & Continue")

    # Wait for the app to load
    page.wait_for_selector("text=neurocnl Studio", timeout=30000)

    # Input a valid CNL spec
    spec = (
        "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
        "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0\n"
    )

    # In Flutter web, text selectors can be tricky.
    # Let's try to find the editor by clicking the "CNL Editor" text area region
    page.click("text=CNL Editor")
    # Small delay to ensure focus
    page.wait_for_timeout(500)
    page.keyboard.type(spec)

    # Trigger Run Simulation
    run_button = page.get_by_role("button", name="Run Simulation")
    expect(run_button).to_be_enabled()
    run_button.click()

    # Wait for simulation to complete
    # The button text changes to "Running..." and then back
    expect(page.get_by_text("Running…")).to_be_visible()
    expect(page.get_by_role("button", name="Run Simulation")).to_be_enabled(timeout=30000)

    # Switch to Simulation tab if not already there
    page.get_by_role("tab", name="Simulation").click()

    # Verify results appear
    expect(page.get_by_text("Sensory Spike Count")).to_be_visible()
    expect(page.get_by_text("Motor Spike Count")).to_be_visible()
