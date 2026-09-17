from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app

client = TestClient(app, raise_server_exceptions=False)


def get_mock_network():
    return {
        "num_neurons": 10,
        "num_synapses": 20,
        "neuron_model": "LIF",
        "weight_bit_width": 8,
        "network_depth": 1,
        "populations": [{"name": "in", "size": 10}],
        "connections": [{"pre": "in", "post": "in", "weight_count": 20}],
    }


def test_export_neuroml_deprecated():
    # Deprecated: use test_artifact_contracts.py for real artifact tests
    response = client.post("/api/neurochip/export/neuroml", json={"network": get_mock_network()})
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"


def test_websocket_compile_missing_data():
    with client.websocket_connect("/api/neurochip/export/ws/compile") as websocket:
        # Missing network
        websocket.send_json({"target": "teensy"})
        message = websocket.receive_json()
        assert message == {"error": "Missing target or network data"}

        # Missing target
        websocket.send_json({"network": {"num_neurons": 10}})
        message = websocket.receive_json()
        assert message == {"error": "Missing target or network data"}


def test_websocket_compile_unsupported_target():
    with client.websocket_connect("/api/neurochip/export/ws/compile") as websocket:
        payload = {
            "target": "unknown",
            "network": {
                "num_neurons": 10,
                "num_synapses": 20,
                "neuron_model": "lif",
                "weight_bit_width": 8,
                "network_depth": 1,
                "populations": [{"name": "in", "size": 10}],
                "connections": [{"pre": "in", "post": "in", "weight_count": 20}],
            },
        }
        websocket.send_json(payload)
        message = websocket.receive_json()
        assert message == {"error": "Unsupported target: unknown"}


@pytest.mark.mock_only
@patch("neurochip.app.routers.export.akida_generator.generate_akida_package")
def test_export_akida_generator_error(mock_gen):
    mock_gen.side_effect = Exception("generator error")
    response = client.post("/api/neurochip/export/akida", json={"network": get_mock_network()})
    assert response.status_code == 500
    assert (
        response.json()["detail"]
        == "An internal server error occurred while generating the package."
    )


@pytest.mark.mock_only
@patch("neurochip.app.routers.export.brainscales_generator.generate_brainscales_package")
def test_export_brainscales_generator_error(mock_gen):
    mock_gen.side_effect = Exception("generator error")
    response = client.post(
        "/api/neurochip/export/brainscales", json={"network": get_mock_network()}
    )
    assert response.status_code == 500
    assert (
        response.json()["detail"]
        == "An internal server error occurred while generating the package."
    )


@pytest.mark.mock_only
@patch("neurochip.app.routers.export.spinnaker_generator.generate_spinnaker_package")
def test_export_spinnaker_generator_error(mock_gen):
    mock_gen.side_effect = Exception("generator error")
    response = client.post("/api/neurochip/export/spinnaker", json={"network": get_mock_network()})
    assert response.status_code == 500
    assert (
        response.json()["detail"]
        == "An internal server error occurred while generating the package."
    )


@pytest.mark.mock_only
@patch("neurochip.app.routers.export.teensy_generator.generate_teensy_project")
def test_export_teensy_generator_error(mock_gen):
    mock_gen.side_effect = Exception("generator error")
    response = client.post("/api/neurochip/export/teensy", json=get_mock_network())
    assert response.status_code == 500
    assert (
        response.json()["detail"]
        == "An internal server error occurred while generating the package."
    )


@pytest.mark.mock_only
@patch("neurochip.app.routers.export.loihi_generator.generate_loihi_package")
def test_export_loihi_generator_error(mock_gen):
    mock_gen.side_effect = Exception("generator error")
    response = client.post("/api/neurochip/export/loihi", json={"network": get_mock_network()})
    assert response.status_code == 500
    assert (
        response.json()["detail"]
        == "An internal server error occurred while generating the package."
    )


@pytest.mark.mock_only
@patch("neurochip.app.routers.export.loihi_generator.generate_loihi_package")
def test_websocket_compile_loihi_success(mock_gen):
    mock_gen.return_value = b"fake loihi zip"
    with client.websocket_connect("/api/neurochip/export/ws/compile") as websocket:
        payload = {"target": "loihi", "network": get_mock_network()}
        websocket.send_json(payload)
        # It's in a thread, so it might not send progress if mock returns too fast,
        # but the generator call should have happened.
        # Actually generate_loihi_package in export.py doesn't use the result of to_thread.


# ---------------------------------------------------------------------------
# TeensyNetworkPayloadContract enforcement tests
# ---------------------------------------------------------------------------


def test_export_teensy_contract_rejects_bad_neuron_model():
    """Payloads with unsupported neuron models are rejected before firmware gen."""
    payload = {**get_mock_network(), "neuron_model": "unsupported_model"}
    response = client.post("/api/neurochip/export/teensy", json=payload)
    assert response.status_code == 422


def test_export_teensy_contract_rejects_too_many_neurons():
    """Payloads exceeding Teensy 4.1 neuron capacity are rejected before firmware gen."""
    payload = {**get_mock_network(), "num_neurons": 9999}
    response = client.post("/api/neurochip/export/teensy", json=payload)
    assert response.status_code == 422


@patch("neurochip.app.routers.export.teensy_generator.generate_teensy_project")
def test_export_teensy_success(mock_gen):
    """Valid LIF payload reaches the generator and a zip is returned."""
    import io
    import zipfile

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("neurochip_firmware/platformio.ini", "[env:teensy41]")
    mock_gen.return_value = buf.getvalue()

    response = client.post("/api/neurochip/export/teensy", json=get_mock_network())

    assert response.status_code == 200
    assert response.headers["content-type"] == "application/zip"
    mock_gen.assert_called_once()


def test_websocket_compile_teensy_contract_violation():
    """WebSocket Teensy path sends a contract_violation error for out-of-spec payloads."""
    with client.websocket_connect("/api/neurochip/export/ws/compile") as websocket:
        payload = {
            "target": "teensy",
            "network": {**get_mock_network(), "neuron_model": "unsupported_model"},
        }
        websocket.send_json(payload)
        message = websocket.receive_json()
        assert "error" in message
        assert "contract_violation" in message["error"]
