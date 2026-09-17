"""Regression tests for LavaIO.to_runtime_payload() population size inference."""

from typing import Any, Literal

import nir
import numpy as np
import pytest

from neurocnl.converter.lava_io import LavaIO


def _scalar_lif(**kwargs: Any) -> nir.LIF:
    """Reproduce exactly what the NIR CNL compiler produces: scalar tau, not an array."""
    defaults = dict(
        tau=np.float64(0.01),
        r=np.float64(1.0),
        v_leak=np.float64(0.0),
        v_threshold=np.float64(0.5),
    )
    defaults.update(kwargs)
    return nir.LIF(**defaults)


def _multi_neuron_graph() -> nir.NIRGraph:
    """
    Minimal graph that mirrors what the NIR CNL compiler produces for
    slip_reflex.cnl (sensor=1 neuron, interneuron=30 neurons):

      input(1) → sensor_LIF(scalar tau) → Linear(30,1) → interneuron_LIF(scalar tau) → output(30)
    """
    nodes = {
        "input": nir.Input(input_type={"input": np.array([1])}),
        "sensor": _scalar_lif(tau=np.float64(0.005), v_threshold=np.float64(0.5)),
        "w_sensor_interneuron": nir.Linear(weight=np.ones((30, 1), dtype=float)),
        "interneuron": _scalar_lif(tau=np.float64(0.01), v_threshold=np.float64(0.45)),
        "output": nir.Output(output_type={"output": np.array([30])}),
    }
    edges = [
        ("input", "sensor"),
        ("sensor", "w_sensor_interneuron"),
        ("w_sensor_interneuron", "interneuron"),
        ("interneuron", "output"),
    ]
    # type_check=False mirrors what the NIR CNL compiler produces: scalar LIF nodes
    # have empty shape metadata that fails NIR's type-inference pass, but the
    # to_runtime_payload() code path never calls infer_types() — it just reads tau.
    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False)


def test_population_sizes_inferred_from_linear_weights() -> None:
    """Interneuron has 30 neurons (Linear rows). Payload must say size=30, not 1."""
    payload = LavaIO().to_runtime_payload(_multi_neuron_graph())
    pop_by_name = {p["name"]: p for p in payload["populations"]}
    assert pop_by_name["interneuron"]["size"] == 30, (
        f"Expected interneuron size=30, got {pop_by_name['interneuron']['size']}"
    )
    assert pop_by_name["sensor"]["size"] == 1  # sensor has 1 neuron (Linear columns)


def test_connection_weight_shape_matches_population_sizes() -> None:
    """Weight shape must equal (target_pop_size, source_pop_size) after reconciliation.

    Before the fix: interneuron size=1 but weight has 30 rows → mismatch → FAIL
    After the fix: interneuron size=30 and weight has 30 rows → consistent → PASS
    """
    payload = LavaIO().to_runtime_payload(_multi_neuron_graph())
    pop_by_name = {p["name"]: p for p in payload["populations"]}
    conn = next(
        c for c in payload["connections"] if c["pre"] == "sensor" and c["post"] == "interneuron"
    )
    weights = np.array(conn["weights"])
    expected_shape = (pop_by_name["interneuron"]["size"], pop_by_name["sensor"]["size"])
    assert weights.shape == expected_shape, (
        f"Weight shape {weights.shape} does not match population sizes "
        f"(interneuron={pop_by_name['interneuron']['size']}, sensor={pop_by_name['sensor']['size']}). "
        f"This is the Lava HTTP 422 mismatch: weight has {weights.shape[0]} target rows "
        f"but population size says {pop_by_name['interneuron']['size']}."
    )


def test_total_neuron_count_reflects_reconciled_sizes() -> None:
    """num_neurons sums reconciled sizes: input(1) + sensor(1) + interneuron(30) = 32.

    The Input node is now tracked as a real population (role="input") so that
    the Input -> Dense -> LIF synapse is retained in "connections" instead of
    being silently dropped (see test_lava_simulator.py for the runtime-level
    consequence: without this, the network's first layer was never driven by
    the stimulus and the Lava simulator produced an empty spike raster).
    """
    payload = LavaIO().to_runtime_payload(_multi_neuron_graph())
    assert payload["num_neurons"] == 32


def test_identity_weight_graph_unaffected() -> None:
    """Existing graphs with scalar (1,1) weights must still produce size=1 populations."""
    nodes = {
        "input": nir.Input(input_type={"input": np.array([1])}),
        "sensor": _scalar_lif(),
        "w": nir.Linear(weight=np.ones((1, 1), dtype=float)),
        "actuator": _scalar_lif(),
        "output": nir.Output(output_type={"output": np.array([1])}),
    }
    edges = [
        ("input", "sensor"),
        ("sensor", "w"),
        ("w", "actuator"),
        ("actuator", "output"),
    ]
    payload = LavaIO().to_runtime_payload(nir.NIRGraph(nodes=nodes, edges=edges, type_check=False))
    pop_by_name = {p["name"]: p for p in payload["populations"]}
    assert pop_by_name["sensor"]["size"] == 1
    assert pop_by_name["actuator"]["size"] == 1
    # input(1) + sensor(1) + actuator(1) = 3 -- the Input node is now a
    # tracked population (role="input") so its synapse to "sensor" survives.
    assert payload["num_neurons"] == 3


def _unsupported_type_graph() -> nir.NIRGraph:
    return nir.NIRGraph(
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


def test_unsupported_node_type_raises_from_nir() -> None:
    with pytest.raises(NotImplementedError, match="not supported in LavaIO"):
        LavaIO().from_nir(_unsupported_type_graph())


def test_unsupported_node_type_raises_from_runtime_payload() -> None:
    with pytest.raises(NotImplementedError, match="not supported in LavaIO.to_runtime_payload"):
        LavaIO().to_runtime_payload(_unsupported_type_graph())


def test_input_output_only_graph_from_nir_does_not_raise() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "output")],
        type_check=False,
    )
    LavaIO().from_nir(graph)  # must not raise
    LavaIO().to_runtime_payload(graph)  # must not raise


def _dense_lif_graph(dense_node: nir.NIRNode) -> nir.NIRGraph:
    """Input -> <dense_node> -> LIF -> Output, mirroring lif_*.ipynb's shape."""
    n = 2
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([n])}),
            "dense": dense_node,
            "lif": _scalar_lif(),
            "output": nir.Output(output_type={"output": np.array([n])}),
        },
        edges=[("input", "dense"), ("dense", "lif"), ("lif", "output")],
        type_check=False,
    )


def test_affine_zero_bias_produces_same_payload_shape_as_linear() -> None:
    """A zero-bias Affine node must be accepted and produce the exact same
    payload shape Linear already produces for the identical topology --
    Affine's weight is real "exact"-parity data (not a fallback identity
    matrix). The dense node sits directly between Input and a neuron
    population, so the wired connection now correctly appears in
    "connections" (Input is tracked as a role="input" population).
    """
    n = 2
    affine_payload = LavaIO().to_runtime_payload(
        _dense_lif_graph(nir.Affine(weight=np.eye(n), bias=np.zeros(n)))
    )
    linear_payload = LavaIO().to_runtime_payload(_dense_lif_graph(nir.Linear(weight=np.eye(n))))
    assert affine_payload["populations"] == linear_payload["populations"]
    assert affine_payload["connections"] == linear_payload["connections"]
    assert len(affine_payload["connections"]) == 1
    assert affine_payload["connections"][0]["pre"] == "input"
    assert affine_payload["connections"][0]["post"] == "lif"


def test_affine_nonzero_bias_raises_value_error() -> None:
    """Non-zero bias must fail loudly, not silently drop the bias or the weight."""
    graph = _dense_lif_graph(nir.Affine(weight=np.eye(2), bias=np.array([0.1, 0.0])))
    with pytest.raises(ValueError, match="non-zero bias"):
        LavaIO().to_runtime_payload(graph)


# ---------------------------------------------------------------------------
# Remote session lifecycle
# ---------------------------------------------------------------------------


class _RecordingOpener:
    """Stands in for urlopen, recording which worker endpoints were called."""

    def __init__(self, *, fail_run: bool = False) -> None:
        self.calls: list[str] = []
        self.fail_run = fail_run

    def __call__(self, request: Any, timeout: float | None = None) -> Any:  # noqa: ANN001, ARG002
        url = request.full_url
        self.calls.append(url)
        if url.endswith("/run") and self.fail_run:
            raise RuntimeError("worker exploded")
        body: dict[str, object] = (
            {"session_id": "s1"} if url.endswith("/compile") else {"spikes": {}}
        )

        class _Response:
            def read(self_inner) -> bytes:  # noqa: ANN001, N805
                import json

                return json.dumps(body).encode()

            def __enter__(self_inner) -> "_Response":  # noqa: ANN001, N805
                return self_inner

            def __exit__(self_inner, *_: object) -> Literal[False]:  # noqa: ANN001, N805
                return False

        return _Response()


def _tiny_graph() -> nir.NIRGraph:
    return nir.NIRGraph(
        nodes={
            "inp": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.eye(2)),
            "cell": nir.LIF(
                tau=np.full(2, 0.02),
                r=np.ones(2),
                v_leak=np.zeros(2),
                v_threshold=np.ones(2),
            ),
            "outp": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("inp", "fc"), ("fc", "cell"), ("cell", "outp")],
    )


def test_remote_run_stops_the_session_afterwards() -> None:
    """Regression: a run that never stops leaks the worker's Lava runtime.

    Its processes are backed by POSIX shared memory that only /stop releases, so
    compile+run without stop exhausts the worker's file descriptors and every
    later run fails with "[Errno 24] Too many open files".
    """
    opener = _RecordingOpener()
    LavaIO().compile_and_run_remote(_tiny_graph(), base_url="http://w", opener=opener)
    assert [c.rsplit("/", 1)[-1] for c in opener.calls] == ["compile", "run", "stop"]


def test_remote_run_stops_the_session_even_when_the_run_fails() -> None:
    opener = _RecordingOpener(fail_run=True)
    with pytest.raises(Exception, match="worker exploded"):
        LavaIO().compile_and_run_remote(_tiny_graph(), base_url="http://w", opener=opener)
    assert opener.calls[-1].endswith("/stop")


def test_lava_lif_params_refuses_a_population_with_no_time_constant() -> None:
    """Lava must reject the same blank neurons snnTorch and SC-NeuroCore do."""
    from neurocnl.runtime.lava_simulator import LavaDispatchError, _lava_lif_params

    with pytest.raises(LavaDispatchError, match="no usable time constant"):
        _lava_lif_params({"name": "cell", "tau_rc": 0.0, "threshold": 1.0})


def test_lava_lif_params_maps_tau_to_dv() -> None:
    from neurocnl.runtime.lava_simulator import _lava_lif_params

    du, dv, vth = _lava_lif_params(
        {"name": "cell", "tau_rc": 0.002, "r": 1.0, "dt": 1e-4, "threshold": 1.0}
    )
    assert du == 1.0
    assert dv == pytest.approx(1e-4 / 0.002)  # dv = dt/tau = 1 - beta
    assert vth == pytest.approx(1.0 / (1.0 * 1e-4 / 0.002))
