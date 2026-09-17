import json

import pytest
from fastapi.testclient import TestClient

from neurosim.app.main import app


def test_simulation_ws() -> None:
    client = TestClient(app)
    with client.websocket_connect("/api/neurosim/ws/simulation") as websocket:
        graph = {
            "nodes": [
                {
                    "id": "n1",
                    "component_id": "lif_population",
                    "parameters": {"name": "n1"},
                    "position": [0, 0],
                }
            ],
            "edges": [],
            "metadata": {},
        }
        websocket.send_text(json.dumps({"graph": graph}))

        # Expect status starting
        msg = json.loads(websocket.receive_text())
        assert msg["type"] == "status"
        assert msg["status"] == "starting"

        # Since it streams in 0.1s chunks, we receive multiple frame messages
        received_frames = 0
        while True:
            msg = json.loads(websocket.receive_text())
            print("RECEIVED:", msg)
            if msg["type"] == "frame":
                # New protocol: frame carries a playback snapshot
                assert msg["status"] == "running"
                assert "playback" in msg
                assert "current_time_ms" in msg
                received_frames += 1
            elif msg["type"] == "node_update":
                # Legacy protocol support (not emitted by current code)
                assert msg["node_id"] == "n1"
                received_frames += 1
            elif msg["type"] == "completion":
                assert msg["status"] == "completed"
                break
            elif msg["type"] == "cancelled":
                break
            else:
                pytest.fail(f"Unexpected message type: {msg}")

        assert received_frames > 0
