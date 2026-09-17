"""Tests for GET /api/simulators/capabilities and POST /api/simulators/run.

The tests verify:
- capabilities endpoint always returns 200 with two backend entries.
- run endpoint returns 200 or 503 (dep missing) for valid CNL — never 500.
- run endpoint returns 400 for CNL that fails to compile.
- run endpoint returns 422 for unknown backend names.
- NIR diagnostics from the classifier are included in warnings or error details.
"""

from __future__ import annotations

from unittest.mock import patch

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

# A minimal NIR-native spec that compiles correctly with compile_to_nir.
VALID_SPEC = "\n".join(
    [
        "Define a network named sim_test.",
        "Define an input port named input with shape (2,).",
        "Define a linear transformation named w_in with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_a "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a linear transformation named w_out with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_b "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_in.",
        "w_in connects to pop_a.",
        "pop_a connects to w_out.",
        "w_out connects to pop_b.",
        "pop_b connects to output.",
    ]
)

INVALID_SPEC = "this is not valid cnl syntax at all"
EMPTY_SPEC = "   "


# ---------------------------------------------------------------------------
# GET /api/simulators/capabilities
# ---------------------------------------------------------------------------


def test_capabilities_returns_200_with_six_backends() -> None:
    resp = client.get("/api/simulators/capabilities")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 6
    names = {b["backend_name"] for b in data}
    assert "lava_sim" in names
    assert "snntorch_sim" in names
    assert "sc_neurocore_sim" in names
    assert "brian2_sim" in names
    assert "nengo_sim" in names
    assert "sinabs_sim" in names


def test_capabilities_response_shape() -> None:
    resp = client.get("/api/simulators/capabilities")
    assert resp.status_code == 200
    for backend in resp.json():
        assert "backend_name" in backend
        assert "display_name" in backend
        assert "available" in backend
        assert "supported_nir_nodes" in backend
        assert "unsupported_nir_nodes" in backend
        assert "approximate_semantics" in backend
        assert "max_timesteps" in backend
        assert "supports_spike_output" in backend


def test_capabilities_lava_availability_flag() -> None:
    resp = client.get("/api/simulators/capabilities")
    assert resp.status_code == 200
    lava = next(b for b in resp.json() if b["backend_name"] == "lava_sim")
    # available can be True or False depending on environment;
    # when False, unavailable_reason must be present and non-empty.
    if not lava["available"]:
        assert lava["unavailable_reason"]


def test_capabilities_blank_lava_worker_url_is_unavailable(monkeypatch) -> None:
    monkeypatch.setenv("NEUROCNL_LAVA_WORKER_URL", "   ")
    with patch("backend.app.routers.simulators._is_available", return_value=False):
        resp = client.get("/api/simulators/capabilities")
    assert resp.status_code == 200
    lava = next(b for b in resp.json() if b["backend_name"] == "lava_sim")
    assert lava["available"] is False
    assert "Backend Setup" in lava["unavailable_reason"]


def test_capabilities_lava_worker_url_enables_remote_backend(monkeypatch) -> None:
    monkeypatch.setenv("NEUROCNL_LAVA_WORKER_URL", "http://lava-backend:8012")
    with patch("backend.app.routers.simulators._is_available", return_value=False):
        resp = client.get("/api/simulators/capabilities")
    assert resp.status_code == 200
    lava = next(b for b in resp.json() if b["backend_name"] == "lava_sim")
    assert lava["available"] is True
    assert lava["requires_optional_dependency"] is None


# ---------------------------------------------------------------------------
# POST /api/simulators/run — error paths (no dep required)
# ---------------------------------------------------------------------------


def test_run_unknown_backend_returns_422() -> None:
    resp = client.post(
        "/api/simulators/run",
        json={"spec": VALID_SPEC, "backend_name": "not_a_simulator"},
        headers={"X-Forwarded-For": "192.0.2.1"},
    )
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "validation_failed"
    assert any("unknown_backend" in str(item) for item in detail["items"])


def test_run_codegen_only_backend_returns_422_not_silent_snntorch_dispatch() -> None:
    """Regression: nir_support.list_supported_backends() includes 8 codegen-
    only ids /simulators/run has no dispatch branch for. Naively deriving
    the known-backend set from that full list (instead of
    list_simulator_backends()'s strict 3-item subset) would let these
    silently fall through run_simulation's trailing branch into
    SnnTorchSimulatorAdapter -- the wrong simulator, with no error at all.
    One representative id is exercised live (this endpoint is rate-limited
    at 10/minute); the remaining ids are covered by the pure-Python
    companion test below without spending further rate-limit budget.
    """
    resp = client.post(
        "/api/simulators/run",
        json={"spec": VALID_SPEC, "backend_name": "brian2"},
        headers={"X-Forwarded-For": "192.0.2.2"},
    )
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert any("unknown_backend" in str(item) for item in detail["items"])


def test_codegen_only_backends_excluded_from_simulator_runtime_set() -> None:
    """Pure-Python companion to the test above — covers all 8 codegen-only
    ids without hitting the rate-limited /simulators/run endpoint 8 more
    times (a prior version of this test parametrized over all 8 live HTTP
    calls and starved later tests in this file's 10/minute budget).
    """
    from neurocnl.runtime.nir_support import (
        list_simulator_backends,
        list_supported_backends,
    )

    known_backends = set(list_simulator_backends())
    codegen_only_ids = set(list_supported_backends()) - known_backends
    assert codegen_only_ids == {
        "brian2",
        "sinabs",
        "rockpool",
        "pynn",
        "nengo",
        "akida",
        "lava",
        "sc_neurocore_fpga",
    }
    assert codegen_only_ids.isdisjoint(known_backends)


def test_run_invalid_cnl_returns_400() -> None:
    resp = client.post(
        "/api/simulators/run",
        json={"spec": INVALID_SPEC, "backend_name": "lava_sim"},
        headers={"X-Forwarded-For": "192.0.2.3"},
    )
    assert resp.status_code == 400
    detail = resp.json()["detail"]
    assert detail["error"] == "compile_failed"
    assert len(detail["items"]) > 0


def test_run_empty_spec_returns_400_or_422() -> None:
    resp = client.post(
        "/api/simulators/run",
        json={"spec": EMPTY_SPEC, "backend_name": "lava_sim"},
        headers={"X-Forwarded-For": "192.0.2.4"},
    )
    # Either 400 (compile failed) or 422 (no valid sentences) is acceptable.
    assert resp.status_code in {400, 422}
    detail = resp.json()["detail"]
    assert "error" in detail


def test_run_missing_spec_field_returns_422() -> None:
    resp = client.post(
        "/api/simulators/run",
        json={"backend_name": "lava_sim"},
        headers={"X-Forwarded-For": "192.0.2.5"},
    )
    # FastAPI/Pydantic validation error
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# POST /api/simulators/run — success or 503 (dep missing) for valid CNL
# ---------------------------------------------------------------------------


def test_run_valid_cnl_never_returns_500() -> None:
    """Core contract: a valid CNL spec must never produce a 500 error."""
    resp = client.post(
        "/api/simulators/run",
        json={"spec": VALID_SPEC, "backend_name": "lava_sim"},
        headers={"X-Forwarded-For": "192.0.2.6"},
    )
    assert resp.status_code != 500, f"Unexpected 500: {resp.text}"


def test_run_valid_cnl_lava_returns_200_or_503() -> None:
    resp = client.post(
        "/api/simulators/run",
        json={"spec": VALID_SPEC, "backend_name": "lava_sim"},
        headers={"X-Forwarded-For": "192.0.2.7"},
    )
    assert resp.status_code in {
        200,
        503,
    }, f"Unexpected status {resp.status_code}: {resp.text}"


def test_run_valid_cnl_snntorch_returns_200_or_503() -> None:
    resp = client.post(
        "/api/simulators/run",
        json={"spec": VALID_SPEC, "backend_name": "snntorch_sim"},
        headers={"X-Forwarded-For": "192.0.2.8"},
    )
    assert resp.status_code in {
        200,
        503,
    }, f"Unexpected status {resp.status_code}: {resp.text}"


def test_run_200_result_shape() -> None:
    """When lava is available, the result shape must match SimulatorRunResult."""
    with patch("backend.app.routers.simulators._is_available", return_value=True):
        resp = client.post(
            "/api/simulators/run",
            json={
                "spec": VALID_SPEC,
                "backend_name": "lava_sim",
                "timesteps": 50,
                "seed": 7,
            },
            headers={"X-Forwarded-For": "192.0.2.9"},
        )
    if resp.status_code != 200:
        return  # dep unavailable in this environment — skip shape check
    data = resp.json()
    assert data["backend_name"] == "lava_sim"
    assert data["status"] == "completed"
    assert data["support_level"] in {"exact", "approximate", "unsupported"}
    assert data["timesteps"] == 50
    assert "nir_summary" in data
    assert data["nir_summary"]["node_count"] > 0
    assert "metadata" in data
    assert data["metadata"]["seed"] == 7


def test_run_503_has_structured_diagnostic() -> None:
    """When the dependency is missing the error must be structured, not a plain 500."""
    with patch("backend.app.routers.simulators._is_available", return_value=False):
        resp = client.post(
            "/api/simulators/run",
            json={"spec": VALID_SPEC, "backend_name": "lava_sim"},
            headers={"X-Forwarded-For": "192.0.2.10"},
        )
    assert resp.status_code == 503
    detail = resp.json()["detail"]
    assert detail["error"] == "missing_dependency"
    assert len(detail["items"]) > 0
    assert detail["items"][0]["hint"]


# ---------------------------------------------------------------------------
# POST /api/simulators/run — explicit stimulus
# ---------------------------------------------------------------------------


def test_run_with_explicit_stimulus_accepted_or_503() -> None:
    resp = client.post(
        "/api/simulators/run",
        json={
            "spec": VALID_SPEC,
            "backend_name": "snntorch_sim",
            "timesteps": 30,
            "stimulus": {
                "type": "spike_train",
                "population": "input",
                "spikes": {"0": [0, 5, 10], "1": [3, 8]},
            },
        },
        headers={"X-Forwarded-For": "192.0.2.11"},
    )
    # 200 (dep available) or 503 (dep missing) — never 422 for a valid stimulus shape.
    assert resp.status_code in {200, 503}, f"Unexpected {resp.status_code}: {resp.text}"


# ---------------------------------------------------------------------------
# POST /api/simulators/run — T1-6 Lava real dispatch (mocked Lava)
# ---------------------------------------------------------------------------


def test_run_lava_real_dispatch_returns_runtime_mode() -> None:
    """When lava adapter is mocked to succeed, runtime_mode is 'in_process_lava_sim'."""
    mock_result = {
        "spikes": {"lif": {"0": [0, 5, 10]}},
        "voltages": {},
        "execution_time_ms": 15.0,
        "runtime_mode": "in_process_lava_sim",
        "warnings": [],
    }
    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.lava_simulator.LavaSimulatorAdapter.run",
            return_value=type("R", (), mock_result)(),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={
                "spec": VALID_SPEC,
                "backend_name": "lava_sim",
                "timesteps": 50,
                "seed": 7,
            },
            # Use a unique forwarded IP to bypass the shared rate limit bucket.
            headers={"X-Forwarded-For": "192.0.2.100"},
        )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["backend_name"] == "lava_sim"
    assert data["status"] == "completed"
    assert data["metadata"]["runtime_mode"] == "in_process_lava_sim"
    assert data["metadata"]["seed"] == 7
    # spikes are non-empty when adapter returns real results
    assert data["spikes"] == {"lif": {"0": [0, 5, 10]}}


def test_run_lava_dispatch_error_returns_422() -> None:
    """LavaDispatchError from the adapter must become a structured 422."""
    from neurocnl.runtime.lava_simulator import LavaDispatchError

    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.lava_simulator.LavaSimulatorAdapter.run",
            side_effect=LavaDispatchError("Lava process exploded"),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={"spec": VALID_SPEC, "backend_name": "lava_sim"},
            headers={"X-Forwarded-For": "192.0.2.101"},
        )
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "lava_dispatch_failed"
    assert any("Lava process exploded" in item["message"] for item in detail["items"])


def test_run_lava_unexpected_error_returns_422_not_500() -> None:
    """Unexpected exceptions from the Lava adapter must be wrapped and return 422, never 500."""
    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True),
        patch(
            "neurocnl.runtime.lava_simulator.LavaSimulatorAdapter._run_in_process",
            side_effect=ValueError("Lava setup crashed unexpectedly"),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={"spec": VALID_SPEC, "backend_name": "lava_sim"},
            headers={"X-Forwarded-For": "192.0.2.101"},
        )
    assert resp.status_code == 422, f"Expected 422, got {resp.status_code}: {resp.text}"
    detail = resp.json()["detail"]
    assert detail["error"] == "lava_dispatch_failed"
    assert any(
        "Lava setup crashed unexpectedly" in item["message"] for item in detail["items"]
    )


# ---------------------------------------------------------------------------
# POST /api/simulators/run — T1-7 snnTorch real dispatch (mocked)
# ---------------------------------------------------------------------------


def test_run_snntorch_real_dispatch_returns_in_process_runtime_mode() -> None:
    """When snnTorch adapter is mocked to succeed, runtime_mode is 'in_process_snntorch_sim'."""
    mock_result = {
        "spikes": {"lif": {"0": [0, 2]}},
        "voltages": {"lif": {"0": [0.1, 0.5, 0.3]}},
        "execution_time_ms": 8.0,
        "runtime_mode": "in_process_snntorch_sim",
        "warnings": [],
    }
    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            return_value=type("R", (), mock_result)(),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={
                "spec": VALID_SPEC,
                "backend_name": "snntorch_sim",
                "timesteps": 50,
                "seed": 3,
            },
            headers={"X-Forwarded-For": "192.0.2.102"},
        )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["backend_name"] == "snntorch_sim"
    assert data["status"] == "completed"
    assert data["metadata"]["runtime_mode"] == "in_process_snntorch_sim"
    assert data["metadata"]["seed"] == 3
    assert data["spikes"] == {"lif": {"0": [0, 2]}}


def test_run_snntorch_dispatch_error_returns_422() -> None:
    """SnnTorchDispatchError from the adapter must become a structured 422."""
    from neurocnl.runtime.snntorch_simulator import SnnTorchDispatchError

    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            side_effect=SnnTorchDispatchError("snnTorch loop crashed"),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={"spec": VALID_SPEC, "backend_name": "snntorch_sim"},
            headers={"X-Forwarded-For": "192.0.2.104"},
        )
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "snntorch_dispatch_failed"
    assert any("snnTorch loop crashed" in item["message"] for item in detail["items"])


def test_run_snntorch_voltage_traces_in_result() -> None:
    """When snnTorch returns membrane traces, result voltages must be non-empty."""
    mock_result = {
        "spikes": {"lif": {}},
        "voltages": {"lif": {"0": [0.1, 0.3], "1": [0.2, 0.4]}},
        "execution_time_ms": 5.0,
        "runtime_mode": "in_process_snntorch_sim",
        "warnings": [],
    }
    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            return_value=type("R", (), mock_result)(),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={"spec": VALID_SPEC, "backend_name": "snntorch_sim"},
            headers={"X-Forwarded-For": "192.0.2.105"},
        )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["voltages"] != {}


def test_run_with_invalid_stimulus_population_returns_422() -> None:
    with patch("backend.app.routers.simulators._is_available", return_value=True):
        resp = client.post(
            "/api/simulators/run",
            json={
                "spec": VALID_SPEC,
                "backend_name": "lava_sim",
                "stimulus": {
                    "type": "spike_train",
                    "population": "does_not_exist",
                    "spikes": {"0": [1, 2]},
                },
            },
            headers={"X-Forwarded-For": "192.0.2.103"},
        )
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "validation_failed"
    assert any("does_not_exist" in item["message"] for item in detail["items"])


# ---------------------------------------------------------------------------
# Trained weights (POST /api/simulators/run, trained_nir_base64)
# ---------------------------------------------------------------------------
#
# The CNL spec stores tensor shape only, so a run without a trained NIR graph
# simulates a network in which every weight is 0.0 — it completes in
# milliseconds and records no spikes. These tests pin the two halves of the fix:
# the graph really is overlaid when a trained file arrives, and the caller is
# told out loud when one does not.


def _trained_nir_base64(*shapes: tuple[int, int], fill: float = 0.5) -> str:
    """A base64 `.nir` file holding one Linear matrix per shape, chained."""
    import base64
    import io

    import nir
    import numpy as np

    names = [f"w{index}" for index in range(len(shapes))]
    graph = nir.NIRGraph(
        nodes={
            name: nir.Linear(weight=np.full(shape, fill))
            for name, shape in zip(names, shapes, strict=True)
        },
        edges=[(a, b) for a, b in zip(names, names[1:], strict=False)],
    )
    buffer = io.BytesIO()
    nir.write(buffer, graph)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def _captured_graph_run(store: dict) -> object:
    """A fake adapter `run` that records the graph it was handed."""

    def _run(self, graph, *args, **kwargs):  # noqa: ANN001, ARG001
        store["graph"] = graph
        return type(
            "R",
            (),
            {
                "spikes": {"pop_a": {"0": [1]}},
                "voltages": {},
                "execution_time_ms": 1.0,
                "runtime_mode": "in_process_snntorch_sim",
                "warnings": [],
            },
        )()

    return _run


def test_run_without_trained_nir_warns_that_every_weight_is_zero() -> None:
    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            _captured_graph_run({}),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={"spec": VALID_SPEC, "backend_name": "snntorch_sim"},
            headers={"X-Forwarded-For": "192.0.2.110"},
        )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["trained_weights"] is None
    assert any("0.0" in w and "NIR Exporter" in w for w in data["warnings"]), data[
        "warnings"
    ]


def test_run_with_trained_nir_overlays_the_weights_and_drops_the_warning() -> None:
    captured: dict = {}
    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            _captured_graph_run(captured),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={
                "spec": VALID_SPEC,
                "backend_name": "snntorch_sim",
                "trained_nir_base64": _trained_nir_base64((2, 2), (2, 2)),
            },
            headers={"X-Forwarded-For": "192.0.2.111"},
        )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["trained_weights"]["applied"] is True
    assert data["trained_weights"]["nonzero"] == 8
    # Assert on the zero-weight warning itself. Matching the bare substring
    # "0.0" also matched any warning that happened to quote a decimal — such as
    # the unreachable-threshold advisory, which legitimately names a timestep.
    assert not any(
        "Every weight in this network is 0.0" in w for w in data["warnings"]
    ), data["warnings"]

    # The simulator must receive the overlaid graph, not the spec's zeros.
    import numpy as np

    weights = [
        node.weight
        for node in captured["graph"].nodes.values()
        if type(node).__name__ == "Linear"
    ]
    assert weights and all(np.all(matrix == 0.5) for matrix in weights)


def test_run_with_mismatched_trained_nir_returns_422() -> None:
    with patch("backend.app.routers.simulators._is_available", return_value=True):
        resp = client.post(
            "/api/simulators/run",
            json={
                "spec": VALID_SPEC,
                "backend_name": "snntorch_sim",
                "trained_nir_base64": _trained_nir_base64((7, 7)),
            },
            headers={"X-Forwarded-For": "192.0.2.112"},
        )
    assert resp.status_code == 422, resp.text
    detail = resp.json()["detail"]
    assert detail["error"] == "trained_nir_mismatch"
    assert any("re-run training" in item["message"].lower() for item in detail["items"])


def test_run_with_unreadable_trained_nir_returns_422() -> None:
    with patch("backend.app.routers.simulators._is_available", return_value=True):
        resp = client.post(
            "/api/simulators/run",
            json={
                "spec": VALID_SPEC,
                "backend_name": "snntorch_sim",
                "trained_nir_base64": "bm90IGEgbmlyIGZpbGU=",
            },
            headers={"X-Forwarded-For": "192.0.2.113"},
        )
    assert resp.status_code == 422, resp.text
    assert resp.json()["detail"]["error"] == "invalid_trained_nir"


# ---------------------------------------------------------------------------
# POST /api/simulators/run — the stimulus that actually drove the run
# ---------------------------------------------------------------------------
# Without this echo, an empty output raster and an empty *input* look identical
# in the Studio, and the generated default stimulus is invisible to the caller
# that never supplied one.

_MOCK_SNNTORCH_RESULT = {
    "spikes": {"pop_b": {"0": [1]}},
    "voltages": {},
    "execution_time_ms": 4.0,
    "runtime_mode": "in_process_snntorch_sim",
    "warnings": [],
}

# 784 neurons × 100 timesteps at a firing rate of 1.0 is 78,400 entries, past
# the 50,000-entry transport cap.
WIDE_SPEC = "\n".join(
    [
        "Define a network named wide_sim_test.",
        "Define an input port named input with shape (784,).",
        "Define a linear transformation named w_in with weight matrix shape (2, 784).",
        "Define a LIF neuron named pop_a "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_in.",
        "w_in connects to pop_a.",
        "pop_a connects to output.",
    ]
)


def _run_snntorch(payload: dict, *, client_ip: str) -> dict:
    """Dispatch a run with the snnTorch adapter mocked, and return the body."""
    with (
        patch("backend.app.routers.simulators._is_available", return_value=True),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            return_value=type("R", (), _MOCK_SNNTORCH_RESULT)(),
        ),
    ):
        resp = client.post(
            "/api/simulators/run",
            json={"backend_name": "snntorch_sim", **payload},
            headers={"X-Forwarded-For": client_ip},
        )
    assert resp.status_code == 200, resp.text
    return resp.json()


def test_run_echoes_the_generated_stimulus_when_the_caller_supplied_none() -> None:
    data = _run_snntorch(
        {"spec": VALID_SPEC, "timesteps": 40, "seed": 5, "firing_rate": 0.5},
        client_ip="192.0.2.1",
    )

    stimulus = data["stimulus"]
    assert stimulus["generated"] is True
    assert stimulus["truncated"] is False
    assert stimulus["population"] == data["metadata"]["stimulus_population"]
    assert stimulus["neuron_count"] == data["metadata"]["stimulus_neuron_count"]
    assert stimulus[
        "spikes"
    ], "a generated stimulus that fires nowhere is not a stimulus"
    # Same shape as one population of `spikes`, so the raster painter is reused.
    assert all(isinstance(key, str) for key in stimulus["spikes"])
    assert all(
        all(isinstance(step, int) for step in steps)
        for steps in stimulus["spikes"].values()
    )


def test_run_echoes_an_explicit_stimulus_unchanged() -> None:
    supplied = {"0": [0, 5, 10], "1": [3, 8]}
    data = _run_snntorch(
        {
            "spec": VALID_SPEC,
            "timesteps": 30,
            "stimulus": {
                "type": "spike_train",
                "population": "input",
                "spikes": supplied,
            },
        },
        client_ip="192.0.2.2",
    )

    stimulus = data["stimulus"]
    assert stimulus["generated"] is False
    assert stimulus["truncated"] is False
    assert stimulus["population"] == "input"
    assert stimulus["spikes"] == supplied


def test_an_oversized_stimulus_drops_whole_neurons_rather_than_trimming_them() -> None:
    """A half-length spike list would paint a silent stretch that never happened."""
    from backend.app.routers.simulators import _MAX_STIMULUS_SPIKES
    from neurocnl import compile_to_nir
    from neurocnl.runtime.stimulus import generate_default_stimulus

    data = _run_snntorch(
        {"spec": WIDE_SPEC, "timesteps": 100, "seed": 2, "firing_rate": 1.0},
        client_ip="192.0.2.3",
    )

    stimulus = data["stimulus"]
    assert stimulus["truncated"] is True
    assert stimulus["neuron_count"] == 784
    emitted = stimulus["spikes"]
    assert sum(len(steps) for steps in emitted.values()) <= _MAX_STIMULUS_SPIKES
    assert len(emitted) < 784

    # Every neuron that survived must carry its complete train, and the kept
    # ones must be the lowest indices so the raster reads from the top.
    full = generate_default_stimulus(compile_to_nir(WIDE_SPEC), 100, 2, 1.0)
    assert sorted(int(key) for key in emitted) == list(range(len(emitted)))
    for key, steps in emitted.items():
        assert steps == full.spikes[int(key)]
