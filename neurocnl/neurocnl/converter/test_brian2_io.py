"""Tests for Brian2 remote runtime integration helpers."""

import json
from typing import Any

import nir
import numpy as np
import pytest

from neurocnl.converter.brian2_io import Brian2IO


def test_unsupported_node_type_raises() -> None:
    """Unrecognized NIR node types must raise loudly, not silently skip --
    the previous silent-skip mode is exactly how gaps like this go
    undetected until a user notices missing code in the generated notebook.
    """
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "flat": nir.Flatten(
                input_type={"input": np.array([2])},
                start_dim=1,
                end_dim=-1,
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "flat"), ("flat", "output")],
        type_check=False,
    )
    with pytest.raises(NotImplementedError, match="not supported in Brian2IO"):
        Brian2IO().from_nir(graph)


def test_input_output_only_graph_does_not_raise() -> None:
    """Boundary nodes must remain a no-op, not start raising."""
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "output")],
        type_check=False,
    )
    Brian2IO().from_nir(graph)  # must not raise


class _FakeHTTPResponse:
    def __init__(self, payload: dict[str, object]) -> None:
        self._payload = json.dumps(payload).encode("utf-8")

    def __enter__(self) -> "_FakeHTTPResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self) -> bytes:
        return self._payload


def test_brian2_payload_reconciles_lif_population_sizes_from_linear_weights() -> None:
    """Scalar-tau LIF nodes must widen to match adjacent Linear weight shapes."""
    graph = nir.NIRGraph(
        nodes={
            "excitatory": nir.LIF(
                tau=np.array([0.02]),
                v_threshold=np.array([1.0]),
                v_leak=np.array([0.0]),
                r=np.array([1.0]),
            ),
            "w_ext": nir.Linear(weight=np.ones((8, 4))),
            "inhibitory": nir.LIF(
                tau=np.array([0.01]),
                v_threshold=np.array([1.0]),
                v_leak=np.array([0.0]),
                r=np.array([1.0]),
            ),
            "w_e_i": nir.Linear(weight=np.ones((2, 8))),
        },
        edges=[("excitatory", "w_e_i"), ("w_e_i", "inhibitory")],
        type_check=False,
    )
    payload = Brian2IO().to_runtime_payload(graph)
    sizes = {p["name"]: p["size"] for p in payload["populations"]}
    assert sizes["excitatory"] == 8
    assert sizes["inhibitory"] == 2


def test_brian2_io_remote_compile_and_run_round_trip() -> None:
    nodes = {
        "input": nir.LIF(
            tau=np.array([0.01, 0.01]),
            v_threshold=np.array([1.0, 1.0]),
            v_leak=np.array([0.0, 0.0]),
            r=np.array([1.0, 1.0]),
        ),
        "dense": nir.Linear(weight=np.array([[1.0, 0.0], [0.0, 1.0]])),
        "output": nir.LIF(
            tau=np.array([0.02, 0.02]),
            v_threshold=np.array([1.0, 1.0]),
            v_leak=np.array([0.0, 0.0]),
            r=np.array([1.0, 1.0]),
        ),
    }
    graph = nir.NIRGraph(
        nodes=nodes,
        edges=[("input", "dense"), ("dense", "output")],
    )
    captured: list[tuple[str, dict[str, Any]]] = []

    def opener(request, timeout: float):  # type: ignore[no-untyped-def]
        assert timeout == 30.0
        body = json.loads(request.data.decode("utf-8"))
        captured.append((request.full_url, body))
        if request.full_url.endswith("/compile"):
            return _FakeHTTPResponse({"status": "compiled", "session_id": "sess-1"})
        if request.full_url.endswith("/run"):
            return _FakeHTTPResponse(
                {"status": "success", "spikes": {"0": [0]}, "execution_time_ms": 1.5}
            )
        raise AssertionError(f"Unexpected URL {request.full_url}")

    result = Brian2IO().compile_and_run_remote(
        graph,
        base_url="http://brian2-backend:8013",
        steps=4,
        opener=opener,
    )

    assert result["compile"]["session_id"] == "sess-1"
    assert result["run"]["status"] == "success"
    compile_url, compile_payload = captured[0]
    run_url, run_payload = captured[1]
    assert compile_url == "http://brian2-backend:8013/api/neurocnl/brian2/compile"
    assert run_url == "http://brian2-backend:8013/api/neurocnl/brian2/run"
    assert compile_payload["network"]["num_neurons"] == 4
    assert compile_payload["network"]["num_synapses"] == 4
    assert compile_payload["network"]["connections"][0]["pre"] == "input"
    assert compile_payload["network"]["connections"][0]["post"] == "output"
    assert run_payload == {"session_id": "sess-1", "steps": 4}
