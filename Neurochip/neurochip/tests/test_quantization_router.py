import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app

client = TestClient(app, raise_server_exceptions=False)


@pytest.fixture
def sample_network():
    return {
        "num_neurons": 100,
        "num_synapses": 1000,
        "neuron_model": "LIF",
        "populations": [{"id": "p0", "size": 100}],
        "connections": [{"from": "p0", "to": "p0"}],
        "weight_bit_width": 8,
        "network_depth": 1,
    }


def test_quantize_with_layer_configs(sample_network):
    response = client.post(
        '/api/neurochip/quantize?bit_width=8&target_device=Teensy 4.1&layer_configs={"layer0":8}',
        json=sample_network,
    )
    assert response.status_code == 200
    assert response.json()["bit_width"] == 8


def test_quantize_with_invalid_layer_configs_json(sample_network):
    # This should fail due to invalid JSON in layer_configs
    response = client.post(
        "/api/neurochip/quantize?bit_width=8&target_device=Teensy 4.1&layer_configs=not_valid_json",
        json=sample_network,
    )
    assert response.status_code == 422


def test_quantize_batch_with_layer_configs(sample_network):
    response = client.post(
        '/api/neurochip/quantize/batch?target_device=Teensy 4.1&layer_configs={"layer0":8}',
        json=sample_network,
    )
    assert response.status_code == 200
    assert isinstance(response.json(), list)
    assert len(response.json()) > 0


def test_configure_quantization():
    config = {
        "target_device": "Teensy 4.1",
        "bit_width": 8,
        "scaling_factor": 1.0,
        "rounding_mode": "nearest",
        "layer_configs": {"layer0": 8},
    }
    response = client.post("/api/neurochip/quantize/configure", json=config)
    assert response.status_code == 200
    # verify round-trip
    resp_json = response.json()
    assert resp_json["target_device"] == config["target_device"]
    assert resp_json["bit_width"] == config["bit_width"]
    assert resp_json["scaling_factor"] == config["scaling_factor"]
    assert resp_json["rounding_mode"] == config["rounding_mode"]
    assert resp_json["layer_configs"] == config["layer_configs"]


def test_quantize_rejects_unknown_target(sample_network):
    response = client.post(
        "/api/neurochip/quantize?bit_width=8&target_device=unknown_target",
        json=sample_network,
    )
    assert response.status_code == 422
    assert response.json()["detail"]["error"] == "unknown_target"
