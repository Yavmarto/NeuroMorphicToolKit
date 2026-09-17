import json
import urllib.request
from types import SimpleNamespace
from typing import Any

import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.routers import lava as lava_router
from neurochip.app.services import lava_backend as lava_backend_module

client = TestClient(app)


def test_lava_compile_missing_dep():
    # If Lava is missing, it should return 503 instead of 500
    # Provide network data
    network = {
        "num_neurons": 10,
        "num_synapses": 5,
        "neuron_model": "LIF",
        "populations": [],
        "connections": [],
        "weight_bit_width": 8,
        "network_depth": 1,
    }
    response = client.post(
        "/api/neurochip/hardware/lava/compile", json={"network": network, "run_config": "sim"}
    )

    assert response.status_code == 503
    assert "not installed" in response.json()["detail"].lower()


def test_lava_compile_success_with_structured_payload(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _FakeDensePort:
        def connect(self, _other: object) -> None:
            return None

    class _FakeLifPort:
        def connect(self, _other: object) -> None:
            return None

    class _FakeLIF:
        def __init__(self, *, shape: tuple[int], vth: float):
            self.shape = shape
            self.vth = vth
            self.s_out = _FakeLifPort()
            self.a_in = object()
            self.name = f"lif_{shape[0]}"

        def run(self, *, condition: object, run_cfg: object) -> None:
            self._last_condition = condition
            self._last_run_cfg = run_cfg

        def stop(self) -> None:
            return None

    class _FakeDense:
        def __init__(self, *, weights: object):
            self.weights = weights
            self.s_in = object()
            self.a_out = _FakeDensePort()

    class _FakeMonitor:
        def probe(self, _port: object, _steps: int) -> None:
            return None

        def get_data(self) -> dict[str, dict[str, list[list[int]]]]:
            return {"lif_2": {"s_out": [[1, 0], [0, 1], [0, 0]]}}

    class _FakeRunSteps:
        def __init__(self, num_steps: int):
            self.num_steps = num_steps

    class _FakeLoihi2SimCfg:
        pass

    class _FakeArray(list[object]):
        @property
        def shape(self) -> tuple[int, ...]:
            if self and isinstance(self[0], list):
                return (len(self), len(self[0]))
            return (len(self),)

        @property
        def ndim(self) -> int:
            return len(self.shape)

    def _fake_asarray(values: object, dtype: object = None) -> _FakeArray:
        if isinstance(values, list):
            if values and isinstance(values[0], list):
                return _FakeArray([list(row) for row in values])
            return _FakeArray(list(values))
        return _FakeArray([values])

    monkeypatch.setattr(lava_backend_module, "LAVA_AVAILABLE", True)
    monkeypatch.setattr(lava_backend_module, "LIF", _FakeLIF)
    monkeypatch.setattr(lava_backend_module, "Dense", _FakeDense)
    monkeypatch.setattr(lava_backend_module, "Monitor", _FakeMonitor)
    monkeypatch.setattr(lava_backend_module, "RunSteps", _FakeRunSteps)
    monkeypatch.setattr(lava_backend_module, "Loihi2SimCfg", _FakeLoihi2SimCfg)
    monkeypatch.setattr(lava_backend_module, "Loihi2HwCfg", _FakeLoihi2SimCfg)
    monkeypatch.setattr(
        lava_backend_module.LavaBackend,
        "_format_spikes",
        lambda self, raw_spikes, population_process: {"0": [0], "1": [1]},
    )
    monkeypatch.setattr(
        lava_backend_module,
        "np",
        SimpleNamespace(asarray=_fake_asarray),
    )
    lava_router.backend = lava_backend_module.LavaBackend()

    network = {
        "num_neurons": 4,
        "num_synapses": 4,
        "neuron_model": "LIF",
        "populations": [
            {"name": "sensory", "size": 2, "threshold": 1.0},
            {"name": "motor", "size": 2, "threshold": 1.0},
        ],
        "connections": [
            {
                "pre": "sensory",
                "post": "motor",
                "weight_count": 4,
                "weights": [[1.0, 0.0], [0.0, 1.0]],
            }
        ],
        "weight_bit_width": 8,
        "network_depth": 2,
    }
    compile_response = client.post(
        "/api/neurochip/hardware/lava/compile",
        json={"network": network, "run_config": "sim"},
    )

    assert compile_response.status_code == 200
    body = compile_response.json()
    assert body["status"] == "compiled"
    assert body["session_id"]

    run_response = client.post(
        "/api/neurochip/hardware/lava/run",
        json={"session_id": body["session_id"], "steps": 3},
    )

    assert run_response.status_code == 200
    run_body = run_response.json()
    assert run_body["status"] == "success"
    assert run_body["spikes"] == {"0": [0], "1": [1]}
    assert run_body["execution_time_ms"] is not None


def test_lava_run_invalid_session_id_returns_error(monkeypatch):
    monkeypatch.setattr(lava_backend_module, "LAVA_AVAILABLE", True)
    lava_router.backend = lava_backend_module.LavaBackend()

    response = client.post(
        "/api/neurochip/hardware/lava/run",
        json={"session_id": "missing-session", "steps": 3},
    )

    assert response.status_code == 404
    assert "invalid session id" in response.json()["detail"].lower()


def test_lava_compile_hw_mode_without_runtime_returns_preflight_failure():
    network = {
        "num_neurons": 10,
        "num_synapses": 5,
        "neuron_model": "LIF",
        "populations": [],
        "connections": [],
        "weight_bit_width": 8,
        "network_depth": 1,
    }
    response = client.post(
        "/api/neurochip/hardware/lava/compile",
        json={"network": network, "run_config": "hw"},
    )

    assert response.status_code == 503
    assert "preflight" in response.json()["detail"].lower()


def test_lava_router_proxies_to_remote_backend(monkeypatch):
    class _FakeHTTPResponse:
        def __init__(self, payload):
            self._payload = json.dumps(payload).encode("utf-8")

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return None

        def read(self):
            return self._payload

    captured: dict[str, Any] = {}

    def fake_urlopen(request: urllib.request.Request, timeout: float) -> _FakeHTTPResponse:
        captured["url"] = request.full_url
        captured["timeout"] = timeout
        request_data = request.data
        assert isinstance(request_data, bytes)
        captured["body"] = json.loads(request_data.decode("utf-8"))
        return _FakeHTTPResponse({"status": "compiled", "session_id": "remote-session"})

    network = {
        "num_neurons": 2,
        "num_synapses": 1,
        "neuron_model": "LIF",
        "populations": [{"name": "input", "size": 2, "threshold": 1.0}],
        "connections": [],
        "weight_bit_width": 8,
        "network_depth": 1,
    }

    monkeypatch.setenv("NEUROCHIP_LAVA_BACKEND_URL", "http://lava-backend:8012")
    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    response = client.post(
        "/api/neurochip/hardware/lava/compile",
        json={"network": network, "run_config": "sim"},
    )

    assert response.status_code == 200
    assert response.json() == {"status": "compiled", "session_id": "remote-session"}
    assert captured["url"] == "http://lava-backend:8012/api/neurochip/hardware/lava/compile"
    assert captured["timeout"] == 30.0
    body = captured["body"]
    assert isinstance(body, dict)
    assert body["run_config"] == "sim"
    assert isinstance(body["network"], dict)
    assert body["network"]["neuron_model"] == "LIF"


def test_lava_run_stops_the_runtime_after_a_successful_run(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Regression: a successful run used to leave Lava's processes resident.

    Lava's runtime is OS processes backed by POSIX shared memory (``/psm_*``)
    that only ``stop()`` releases. Callers reach ``/compile`` and ``/run`` but
    not ``/stop``, so every successful simulation leaked a runtime until the
    worker ran out of descriptors and even a two-neuron network failed with
    "[Errno 24] Too many open files".
    """
    stopped: list[str] = []

    class _Process:
        def __init__(self) -> None:
            self.s_out = object()

        def run(self, *, condition: object, run_cfg: object) -> None:
            return None

        def stop(self) -> None:
            stopped.append("root")

    class _Monitor:
        def probe(self, *_args: object) -> None:
            return None

        def get_data(self) -> dict[str, Any]:
            return {}

    backend = lava_backend_module.LavaBackend()
    process = _Process()
    backend.sessions["s1"] = {
        "target_population_name": "pop",
        "population_processes": {"pop": process},
    }

    monkeypatch.setattr(lava_backend_module, "LAVA_AVAILABLE", True)
    monkeypatch.setattr(lava_backend_module, "Monitor", _Monitor)
    monkeypatch.setattr(lava_backend_module, "RunSteps", lambda **_: object())
    monkeypatch.setattr(lava_backend_module, "Loihi2SimCfg", lambda: object())
    monkeypatch.setattr(lava_backend_module.LavaBackend, "_format_spikes", lambda *_a, **_k: {})

    result = backend.run("s1", steps=5)

    assert result["status"] == "success"
    assert stopped == ["root"], "the Lava runtime must be released after a run"
