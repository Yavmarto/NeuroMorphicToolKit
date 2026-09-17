from fastapi.testclient import TestClient

from neurochip.app.main import app


def test_websocket_compile_success():
    client = TestClient(app)
    with client.websocket_connect("/api/neurochip/export/ws/compile") as websocket:
        payload = {
            "target": "teensy",
            "network": {
                "num_neurons": 10,
                "num_synapses": 20,
                "neuron_model": "LIF",
                "weight_bit_width": 8,
                "network_depth": 1,
                "populations": [{"name": "in", "size": 10}],
                "connections": [{"pre": "in", "post": "in", "weight_count": 20}],
            },
        }
        websocket.send_json(payload)

        # We expect several progress messages
        messages = []
        for _ in range(5):
            message = websocket.receive_json()
            messages.append(message)
            if message.get("progress") == 1.0:
                break

        assert len(messages) > 0
        assert any(m.get("progress") == 1.0 for m in messages)


def test_websocket_unsupported_target():
    client = TestClient(app)
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
        assert "error" in message
        assert "Unsupported target" in message["error"]


def test_websocket_compile_neuroml_success():
    client = TestClient(app)
    with client.websocket_connect("/api/neurochip/export/ws/compile") as websocket:
        payload = {
            "target": "neuroml",
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

        messages = []
        for _ in range(10):
            message = websocket.receive_json()
            messages.append(message)
            if message.get("progress") == 1.0:
                break

        assert any(m.get("progress") == 1.0 for m in messages)
        assert any("NeuroML" in m.get("message", "") for m in messages)
