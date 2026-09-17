"""Tests for WS /hardware/pynq/stream.

All tests run without PYNQ hardware — the backend falls back to PynqSimulator.
"""

from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.routers import pynq as pynq_router
from neurochip.app.services.pynq_backend import PYNQBackend

client = TestClient(app)


def _deployed_backend() -> PYNQBackend:
    """Return a configured simulator-backed PYNQBackend ready for inference."""
    backend = PYNQBackend()
    backend.load_overlay()
    backend.configure(
        weights=[1.0, 0.5, 0.5, 1.0],
        config={},
        # A 2 -> 2 layer: four weights, one input word per neuron per timestep.
        layers=[
            {
                "input_size": 2,
                "output_size": 2,
                "weight_offset": 0,
                "threshold": 1,
                "leak_shift": 0,
                "refractory": 0,
            }
        ],
    )
    return backend


# ---------------------------------------------------------------------------
# Guard: not deployed
# ---------------------------------------------------------------------------


def test_stream_not_deployed() -> None:
    with patch.object(pynq_router, "backend_instance", None):
        with client.websocket_connect("/hardware/pynq/stream") as ws:
            ws.send_json({"input_spikes": [1, 0], "timesteps": 1})
            msg = ws.receive_json()
            assert msg["error_code"] == "NOT_DEPLOYED"
            assert "error" in msg


# ---------------------------------------------------------------------------
# Guard: invalid input shape
# ---------------------------------------------------------------------------


def test_stream_invalid_input_not_a_list() -> None:
    with patch.object(pynq_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/hardware/pynq/stream") as ws:
            ws.send_json({"input_spikes": "oops", "timesteps": 1})
            msg = ws.receive_json()
            assert msg["error_code"] == "INVALID_INPUT"


# ---------------------------------------------------------------------------
# Happy path: single frame
# ---------------------------------------------------------------------------


def test_stream_single_frame_returns_output_spikes() -> None:
    with patch.object(pynq_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/hardware/pynq/stream") as ws:
            ws.send_json({"input_spikes": [1, 0], "timesteps": 1})
            msg = ws.receive_json()

            assert "output_spikes" in msg
            assert isinstance(msg["output_spikes"], list)
            assert "spike_count" in msg
            assert msg["spike_count"] == len(msg["output_spikes"])
            assert "timesteps" in msg


# ---------------------------------------------------------------------------
# Happy path: multiple sequential frames on one connection
# ---------------------------------------------------------------------------


def test_stream_multiple_frames() -> None:
    with patch.object(pynq_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/hardware/pynq/stream") as ws:
            for _ in range(3):
                ws.send_json({"input_spikes": [1, 0], "timesteps": 1})
                msg = ws.receive_json()
                assert "output_spikes" in msg


# ---------------------------------------------------------------------------
# Empty input list — DmaTransferError from simulator, returned as error frame
# ---------------------------------------------------------------------------


def test_stream_empty_input_spikes_returns_error_frame() -> None:
    with patch.object(pynq_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/hardware/pynq/stream") as ws:
            ws.send_json({"input_spikes": [], "timesteps": 1})
            msg = ws.receive_json()
            # Backend raises DmaTransferError → sent as error JSON, not a crash
            assert "error_code" in msg


# ---------------------------------------------------------------------------
# Default timesteps (omit field)
# ---------------------------------------------------------------------------


def test_stream_defaults_timesteps_to_one() -> None:
    with patch.object(pynq_router, "backend_instance", _deployed_backend()):
        with client.websocket_connect("/hardware/pynq/stream") as ws:
            ws.send_json({"input_spikes": [1, 0]})
            msg = ws.receive_json()
            assert "output_spikes" in msg
            assert msg.get("timesteps", 1) == 1
