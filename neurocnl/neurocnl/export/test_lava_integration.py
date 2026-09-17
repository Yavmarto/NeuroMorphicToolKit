"""Tests for Lava framework integration."""

import json
from typing import Any, cast
from urllib.request import Request

import nengo
import nir
import numpy as np

from neurocnl.converter.lava_io import LavaIO
from neurocnl.export.lava_exporter import export_lava


def test_lava_exporter_hw_mode_false() -> None:
    """Test Lava exporter generates Loihi2SimCfg when hw_mode=False."""
    net = nengo.Network()
    with net:
        nengo.Ensemble(10, 1)

    code = export_lava(net, hw_mode=False)
    assert "Loihi2SimCfg" in code
    assert (
        "Loihi2HwCfg" not in code.split("run_cfg =")[1]
    )  # Make sure run_cfg assigns SimCfg


def test_lava_exporter_hw_mode_true() -> None:
    """Test Lava exporter generates Loihi2HwCfg when hw_mode=True."""
    net = nengo.Network()
    with net:
        nengo.Ensemble(10, 1)

    code = export_lava(net, hw_mode=True)
    assert "Loihi2HwCfg" in code
    assert "Loihi2HwCfg()" in code


def test_lava_io_from_nir_hw_mode_false() -> None:
    """Test LavaIO from_nir generates Loihi2SimCfg when hw_mode=False."""
    nodes = {
        "n1": nir.LIF(
            tau=np.array([0.02]),
            v_threshold=np.array([1.0]),
            v_leak=np.array([0.0]),
            r=np.array([1.0]),
        )
    }
    graph = nir.NIRGraph(nodes=nodes, edges=[])

    io = LavaIO()
    code = io.from_nir(graph, hw_mode=False)
    assert "Loihi2SimCfg" in code
    assert "Loihi2HwCfg()" not in code


def test_lava_io_from_nir_hw_mode_true() -> None:
    """Test LavaIO from_nir generates Loihi2HwCfg when hw_mode=True."""
    nodes = {
        "n1": nir.LIF(
            tau=np.array([0.02]),
            v_threshold=np.array([1.0]),
            v_leak=np.array([0.0]),
            r=np.array([1.0]),
        )
    }
    graph = nir.NIRGraph(nodes=nodes, edges=[])

    io = LavaIO()
    code = io.from_nir(graph, hw_mode=True)
    assert "Loihi2HwCfg" in code
    assert "Loihi2HwCfg()" in code


class _FakeHTTPResponse:
    def __init__(self, payload: dict[str, object]) -> None:
        self._payload = json.dumps(payload).encode("utf-8")

    def __enter__(self) -> "_FakeHTTPResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        return None

    def read(self) -> bytes:
        return self._payload


def test_lava_io_remote_compile_and_run_round_trip() -> None:
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
    captured: list[tuple[str, Any]] = []

    def opener(request: Request, timeout: float) -> _FakeHTTPResponse:
        assert timeout == 30.0
        body = json.loads(cast(bytes, request.data).decode("utf-8"))
        captured.append((request.full_url, body))
        if request.full_url.endswith("/compile"):
            return _FakeHTTPResponse({"status": "compiled", "session_id": "sess-1"})
        if request.full_url.endswith("/run"):
            return _FakeHTTPResponse({"status": "success", "spikes": {"0": [0]}})
        raise AssertionError(f"Unexpected URL {request.full_url}")

    result = LavaIO().compile_and_run_remote(
        graph,
        base_url="http://lava-backend:8012",
        steps=4,
        opener=opener,
    )

    assert result["compile"]["session_id"] == "sess-1"
    assert result["run"]["status"] == "success"
    compile_url, compile_payload = captured[0]
    run_url, run_payload = captured[1]
    assert compile_url == "http://lava-backend:8012/api/neurochip/hardware/lava/compile"
    assert run_url == "http://lava-backend:8012/api/neurochip/hardware/lava/run"
    # NIR's own type-checking auto-inserts a synthetic boundary `nir.Input`
    # node ("input_input") ahead of the first node here, because "input" is
    # itself an `nir.LIF` rather than a real `nir.Input` -- LavaIO now tracks
    # every `nir.Input` (including this synthetic one) as a real, driveable
    # population, adding 2 neurons and one identity-weight synapse on top of
    # the two real LIF populations (2 neurons each).
    assert compile_payload["network"]["num_neurons"] == 6
    assert compile_payload["network"]["num_synapses"] == 8
    assert compile_payload["network"]["connections"][0]["pre"] == "input"
    assert compile_payload["network"]["connections"][0]["post"] == "output"
    assert compile_payload["network"]["connections"][1]["pre"] == "input_input"
    assert compile_payload["network"]["connections"][1]["post"] == "input"
    assert run_payload == {"session_id": "sess-1", "steps": 4}
