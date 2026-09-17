"""Tests for WS /api/neurochip/akida/stream.

All tests run without the Akida SDK — the backend falls back to AkidaSimulator.
"""

from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.routers import akida as akida_router
from neurochip.app.services.akida_backend import AkidaBackend

client = TestClient(app)

_MAPPED_NETWORK = {
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
    "connections": [{"pre": "sensory", "post": "motor", "weight": 1.0}],
    "akida_version": "akida1",
    "network_summary": {},
}


def _deployed_backend() -> AkidaBackend:
    """Return a constructed + mapped simulator-backed AkidaBackend."""
    backend = AkidaBackend()
    backend.construct_model(_MAPPED_NETWORK, bit_width=4)
    backend.map_to_device()
    return backend


# ---------------------------------------------------------------------------
# Guard: not deployed
# ---------------------------------------------------------------------------


def test_akida_stream_not_deployed() -> None:
    with patch.object(akida_router, "backend_instance", None):
        with client.websocket_connect("/api/neurochip/akida/stream") as ws:
            ws.send_json({"inputs": [0.1, 0.2, 0.3, 0.4]})
            msg = ws.receive_json()
            assert msg["error_code"] == "NOT_DEPLOYED"
            assert "error" in msg


# ---------------------------------------------------------------------------
# Guard: invalid input shape
# ---------------------------------------------------------------------------


def test_akida_stream_invalid_input_not_a_list() -> None:
    with patch.object(akida_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/api/neurochip/akida/stream") as ws:
            ws.send_json({"inputs": 42})
            msg = ws.receive_json()
            assert msg["error_code"] == "INVALID_INPUT"


# ---------------------------------------------------------------------------
# Happy path: single frame
# ---------------------------------------------------------------------------


def test_akida_stream_single_frame_returns_outputs() -> None:
    with patch.object(akida_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/api/neurochip/akida/stream") as ws:
            ws.send_json({"inputs": [0.5, 0.5, 0.5, 0.5]})
            msg = ws.receive_json()

            assert "outputs" in msg
            assert isinstance(msg["outputs"], list)
            assert "spike_count" in msg
            assert msg["spike_count"] == len(msg["outputs"])
            assert "telemetry" in msg


# ---------------------------------------------------------------------------
# Happy path: multiple sequential frames on one connection
# ---------------------------------------------------------------------------


def test_akida_stream_multiple_frames() -> None:
    with patch.object(akida_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/api/neurochip/akida/stream") as ws:
            for _ in range(3):
                ws.send_json({"inputs": [0.1, 0.2, 0.3, 0.4]})
                msg = ws.receive_json()
                assert "outputs" in msg


# ---------------------------------------------------------------------------
# Empty inputs list — AkidaInferenceError, returned as error frame
# ---------------------------------------------------------------------------


def test_akida_stream_empty_inputs_returns_error_frame() -> None:
    with patch.object(akida_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/api/neurochip/akida/stream") as ws:
            ws.send_json({"inputs": []})
            msg = ws.receive_json()
            assert "error_code" in msg
