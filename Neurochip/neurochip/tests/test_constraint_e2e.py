from fastapi.testclient import TestClient

from neurochip.app.main import app

client = TestClient(app)


def get_mock_network(num_neurons=100, num_synapses=1000):
    return {
        "num_neurons": num_neurons,
        "num_synapses": num_synapses,
        "neuron_model": "LIF",
        "populations": [{"name": "pop1", "size": num_neurons}],
        "connections": [{"pre": "pop1", "post": "pop1", "weight_count": num_synapses}],
        "weight_bit_width": 32,
        "network_depth": 10,
    }


def test_oversized_network_constraint_failure():
    """
    Test that an oversized network (exceeding neuron capacity) returns a 'fail' status
    in the ConstraintReport instead of a 500 error.
    """
    # Teensy 4.1 has a neuron capacity of 4096. 10,000 neurons should trigger a failure.
    oversized_network = get_mock_network(num_neurons=10000)

    response = client.post("/api/neurochip/analyze?target_id=teensy41", json=oversized_network)

    assert response.status_code == 200
    report = response.json()

    assert report["target_id"] == "teensy41"
    assert report["neuron_fit"] == "fail"
    assert "exceeds capacity" in "".join(report["recommendations"]).lower()


def test_memory_oversized_network_failure():
    """
    Test that a network exceeding memory limits returns a 'fail' status.
    """
    # Teensy 4.1 has 1024 KB memory.
    # Each synapse (32-bit weight) takes (4 + 8) = 12 bytes.
    # 100,000 synapses * 12 bytes = 1,200,000 bytes ~ 1171 KB.
    memory_hog_network = get_mock_network(num_neurons=100, num_synapses=100000)

    response = client.post("/api/neurochip/analyze?target_id=teensy41", json=memory_hog_network)

    assert response.status_code == 200
    report = response.json()

    assert report["memory_fit"] == "fail"
    assert "reduce weight bit-width or network size" in "".join(report["recommendations"]).lower()


def test_valid_network_passes_constraint():
    """
    Test that a small, valid network passes all constraints.
    """
    valid_network = get_mock_network(num_neurons=100)

    response = client.post("/api/neurochip/analyze?target_id=teensy41", json=valid_network)

    assert response.status_code == 200
    report = response.json()

    assert report["neuron_fit"] == "pass"
    assert report["memory_fit"] == "pass"
    assert len(report["unsupported_features"]) == 0
