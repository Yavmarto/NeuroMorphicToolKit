import os
import subprocess
import sys
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


@pytest.fixture
def studio_page(page: Page, backend_server: str):
    """Navigate to the Studio UI and handle setup."""
    page.goto(backend_server)

    # Handle Setup Screen if it appears
    if "/#/setup" in page.url:
        page.click("text=Check Connection")
        expect(page.get_by_text("Connected to neurocnl backend")).to_be_visible(timeout=10000)
        page.click("text=Save & Continue")

    # Wait for the app to load
    page.wait_for_selector("text=neurocnl Studio", timeout=30000)
    return page


def _type_in_editor(page: Page, text: str):
    # Click on the editor
    page.click("text=CNL Editor")
    page.wait_for_timeout(500)

    # Click the editor area specifically (flt-semantics usually handles input in Flutter Web)
    # If standard click isn't enough to focus the invisible input field,
    # we can try selecting all existing text first
    is_mac = sys.platform == "darwin"
    modifier = "Meta" if is_mac else "Control"

    page.keyboard.press(f"{modifier}+A")
    page.keyboard.press("Backspace")
    page.keyboard.type(text)


def test_negative_time_constant(studio_page: Page):
    """Test the pipeline fails cleanly with a negative time constant."""
    spec = (
        "The sensory neuron MUST fire IF membrane potential exceeds 0.8\n"
        "The sensory neuron membrane potential MUST decay WITH time constant of -0.05 seconds\n"
    )

    _type_in_editor(studio_page, spec)

    run_button = studio_page.get_by_role("button", name="Run Simulation")
    expect(run_button).to_be_enabled()

    with studio_page.expect_response("**/api/validate") as response_info:
        run_button.click()

    response = response_info.value
    assert response.status == 200
    json_response = response.json()
    assert json_response["overall"] is False
    assert json_response["layer1"]["overall"] is False
    assert any("membrane_time_constant" in f["name"] for f in json_response["layer1"]["failed"])

    expect(studio_page.get_by_role("button", name="Run Simulation")).to_be_enabled(timeout=30000)

    # Validate that Layer 1 failed due to negative time constant
    expect(studio_page.get_by_text("Layer 1: Physical Parameters")).to_be_visible()
    expect(studio_page.get_by_text("Input should be greater than 0")).to_be_visible()


def test_structural_topology_violation(studio_page: Page):
    """Test the pipeline fails cleanly with a structural topology violation."""
    spec = (
        "The sensory neuron MUST fire IF membrane potential exceeds 0.8\n"
        "The motor neuron MUST fire IF membrane potential exceeds 0.8\n"
        "The connection from sensory neuron to motor neuron MUST have synaptic weight of 0.0\n"
    )

    _type_in_editor(studio_page, spec)

    run_button = studio_page.get_by_role("button", name="Run Simulation")
    expect(run_button).to_be_enabled()

    with studio_page.expect_response("**/api/validate") as response_info:
        run_button.click()

    response = response_info.value
    assert response.status == 200
    json_response = response.json()
    assert json_response["overall"] is False
    assert json_response["layer2"]["overall"] is False
    assert any(
        "zero_weight_synapse" in f["check"] for f in json_response["layer2"]["checks_failed"]
    )

    expect(studio_page.get_by_role("button", name="Run Simulation")).to_be_enabled(timeout=30000)

    # Validate that Layer 2 failed due to 0 weight
    expect(studio_page.get_by_text("Layer 2: Structural Topology")).to_be_visible()

    # Look for error text.
    expect(studio_page.get_by_text("has zero weight")).to_be_visible()


def test_unrecognized_sentence(studio_page: Page):
    """Test the pipeline fails cleanly with an unrecognized sentence."""
    spec = "Make a neuron that goes zap fast."

    _type_in_editor(studio_page, spec)

    run_button = studio_page.get_by_role("button", name="Run Simulation")
    expect(run_button).to_be_enabled()

    with studio_page.expect_response("**/api/validate") as response_info:
        run_button.click()

    response = response_info.value
    assert response.status == 400
    json_response = response.json()
    assert "detail" in json_response

    # UI gracefully handles "No valid CNL sentences found"
    expect(studio_page.get_by_text("No valid CNL sentences found.")).to_be_visible(timeout=30000)
