"""Tests for the analysis router — /analyze and /partition endpoints."""

from fastapi.testclient import TestClient

from neurochip.app.main import app

client = TestClient(app)

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

# pynq_z2 has neuron_capacity=256 — useful for boundary tests
PYNQ_TARGET = "pynq_z2"

# A network that fits PYNQ (128 neurons < 256 capacity)
SMALL_NETWORK = {
    "num_neurons": 128,
    "num_synapses": 256,
    "neuron_model": "LIF",
    "populations": [
        {"name": "sensory", "size": 64},
        {"name": "motor", "size": 64},
    ],
    "connections": [
        {"pre": "sensory", "post": "motor", "weight_count": 256},
    ],
    "weight_bit_width": 8,
    "network_depth": 1,
}

# A network that does NOT fit PYNQ (400 neurons > 256 capacity)
LARGE_NETWORK = {
    "num_neurons": 400,
    "num_synapses": 800,
    "neuron_model": "LIF",
    "populations": [
        {"name": "layer1", "size": 200},
        {"name": "layer2", "size": 200},
    ],
    "connections": [
        {"pre": "layer1", "post": "layer2", "weight_count": 800},
    ],
    "weight_bit_width": 8,
    "network_depth": 1,
}


# ---------------------------------------------------------------------------
# /partition — network fits single chip
# ---------------------------------------------------------------------------


def test_partition_network_fits_single_chip():
    resp = client.post(
        "/api/neurochip/partition",
        params={"target_id": PYNQ_TARGET},
        json=SMALL_NETWORK,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["target_id"] == PYNQ_TARGET
    assert body["target_capacity"] == 256
    assert body["network_fits_single_chip"] is True
    assert body["suggestions"] == []
    assert body["message"] is None


# ---------------------------------------------------------------------------
# /partition — network exceeds capacity, suggestions returned
# ---------------------------------------------------------------------------


def test_partition_network_exceeds_capacity():
    resp = client.post(
        "/api/neurochip/partition",
        params={"target_id": PYNQ_TARGET},
        json=LARGE_NETWORK,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["network_fits_single_chip"] is False
    assert len(body["suggestions"]) >= 1
    # Each suggestion must carry heuristic labelling
    for suggestion in body["suggestions"]:
        assert suggestion["support_level"] == "heuristic"
        assert suggestion["is_estimate"] is True
        assert suggestion["num_partitions"] >= 2
        assert len(suggestion["partitions"]) >= 2
    assert body["message"] is not None
    assert "256" in body["message"]


# ---------------------------------------------------------------------------
# /partition — unknown target → 404
# ---------------------------------------------------------------------------


def test_partition_unknown_target_returns_404():
    resp = client.post(
        "/api/neurochip/partition",
        params={"target_id": "does_not_exist"},
        json=SMALL_NETWORK,
    )
    assert resp.status_code == 404
    assert "does_not_exist" in resp.json()["detail"]


# ---------------------------------------------------------------------------
# /analyze — sanity check (existing endpoint, not changed)
# ---------------------------------------------------------------------------


def test_analyze_small_network_passes():
    resp = client.post(
        "/api/neurochip/analyze",
        params={"target_id": PYNQ_TARGET},
        json=SMALL_NETWORK,
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["target_id"] == PYNQ_TARGET
    assert body["neuron_fit"] in ("pass", "warn", "fail")
