"""Per-converter and integration regression tests for NIR support classification.

Split from ``test_nir_support.py``: targeted unit tests for ``cnl.Synaptic``/
``cnl.RSynaptic`` classification, codegen converter regression tests pinning
down Brian2/PyNN/Lava/Sinabs behavior against the verdict table, and the
snnTorch end-to-end simulator integration test.
"""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl._nir_compat import make_nir_graph
from neurocnl.converter.brian2_io import Brian2IO
from neurocnl.converter.lava_io import LavaIO
from neurocnl.converter.pynn_io import PyNNIO
from neurocnl.converter.sinabs_io import SinabsIO
from neurocnl.runtime.cnl_nodes import RSynaptic, Synaptic
from neurocnl.runtime.nir_support import classify_nir_graph, get_supported_node_types

# ---------------------------------------------------------------------------
# cnl.Synaptic / cnl.RSynaptic — targeted unit tests
# ---------------------------------------------------------------------------


def test_synaptic_classified_as_exact_for_snntorch() -> None:
    """cnl.Synaptic node in a NIRGraph must classify as exact for snntorch_sim."""
    synaptic = Synaptic(n_neurons=2, alpha=0.9, beta=0.8)
    input_node = nir.Input(input_type=np.array([2]))
    output_node = nir.Output(output_type=np.array([2]))
    graph = make_nir_graph(
        nodes={"input": input_node, "syn": synaptic, "output": output_node},
        edges=[("input", "syn"), ("syn", "output")],
    )
    result = classify_nir_graph(graph, "snntorch_sim")
    assert result.level == "exact", (
        f"Expected 'exact' for cnl.Synaptic on snntorch_sim, got {result.level!r}. "
        f"unsupported={result.unsupported_nodes!r}"
    )
    assert "Synaptic" not in result.unsupported_nodes
    assert "Synaptic" not in result.approximate_nodes


def test_rsynaptic_classified_as_exact_for_snntorch() -> None:
    """cnl.RSynaptic node in a NIRGraph must classify as exact for snntorch_sim."""
    rsynaptic = RSynaptic(n_neurons=2, alpha=0.9, beta=0.8)
    input_node = nir.Input(input_type=np.array([2]))
    output_node = nir.Output(output_type=np.array([2]))
    graph = make_nir_graph(
        nodes={"input": input_node, "rsyn": rsynaptic, "output": output_node},
        edges=[("input", "rsyn"), ("rsyn", "output")],
    )
    result = classify_nir_graph(graph, "snntorch_sim")
    assert result.level == "exact", (
        f"Expected 'exact' for cnl.RSynaptic on snntorch_sim, got {result.level!r}. "
        f"unsupported={result.unsupported_nodes!r}"
    )
    assert "RSynaptic" not in result.unsupported_nodes
    assert "RSynaptic" not in result.approximate_nodes


def test_synaptic_unsupported_for_lava() -> None:
    """cnl.Synaptic must be unsupported on lava_sim (no Lava equivalent)."""
    table = get_supported_node_types("lava_sim")
    assert (
        table.get("Synaptic") == "unsupported"
    ), f"Expected 'unsupported' for Synaptic on lava_sim, got {table.get('Synaptic')!r}"


# ---------------------------------------------------------------------------
# Codegen converter regression tests — pin down the "Input"/"Output" and
# "CubaLIF" verdicts above with the actual converter behavior they describe.
# ---------------------------------------------------------------------------


def _make_affine_lif_graph() -> nir.NIRGraph:
    """Minimal Input -> Affine -> LIF -> Output graph, as used by lif_*.ipynb."""
    n = 2
    input_node = nir.Input(input_type=np.array([n]))
    affine = nir.Affine(weight=np.eye(n), bias=np.zeros(n))
    lif = nir.LIF(
        tau=np.array([0.02] * n),
        r=np.array([1.0] * n),
        v_leak=np.array([0.0] * n),
        v_threshold=np.array([1.0] * n),
    )
    output_node = nir.Output(output_type=np.array([n]))
    return nir.NIRGraph(
        nodes={
            "input": input_node,
            "affine": affine,
            "lif": lif,
            "output": output_node,
        },
        edges=[("input", "affine"), ("affine", "lif"), ("lif", "output")],
    )


def test_sinabs_from_nir_handles_boundary_nodes() -> None:
    """Regression test for the Input/Output prerequisite fix in sinabs_io.py.

    Before the fix, SinabsIO.from_nir raised NotImplementedError on the very
    first node (Input) of every real compiled graph, since Input/Output were
    absent from its `_SUPPORTED` dispatch. This must now succeed.
    """
    graph = _make_affine_lif_graph()
    code = SinabsIO().from_nir(graph)
    assert "sinabs_nir.from_nir" in code
    assert "nir.LIF" in code


def _make_cubalif_graph() -> nir.NIRGraph:
    """Minimal Input -> CubaLIF -> Output graph."""
    n = 2
    input_node = nir.Input(input_type=np.array([n]))
    cubalif = nir.CubaLIF(
        tau_mem=np.array([0.02] * n),
        tau_syn=np.array([0.01] * n),
        r=np.array([1.0] * n),
        v_leak=np.array([0.0] * n),
        v_threshold=np.array([1.0] * n),
        w_in=np.array([1.0] * n),
    )
    output_node = nir.Output(output_type=np.array([n]))
    return nir.NIRGraph(
        nodes={"input": input_node, "cubalif": cubalif, "output": output_node},
        edges=[("input", "cubalif"), ("cubalif", "output")],
    )


@pytest.mark.parametrize(
    "converter_cls", [Brian2IO, PyNNIO, LavaIO], ids=["brian2", "pynn", "lava"]
)
def test_cubalif_crashes_brian2_pynn_lava(converter_cls: type) -> None:
    """Documents why CubaLIF is 'unsupported' (not 'approximate') for these
    three codegen converters: nir.CubaLIF has no `.tau` attribute (only
    tau_syn/tau_mem), but from_nir()'s `isinstance(node, nir.LIF | nir.CubaLIF)`
    branch unconditionally accesses `node.tau`, crashing with AttributeError.

    Once a future hardening phase fixes this to raise a clean diagnostic
    instead of crashing, this test should be updated to assert that instead.
    """
    graph = _make_cubalif_graph()
    with pytest.raises(AttributeError):
        converter_cls().from_nir(graph)


def test_rsynaptic_unsupported_for_lava() -> None:
    """cnl.RSynaptic must be unsupported on lava_sim (no Lava equivalent)."""
    table = get_supported_node_types("lava_sim")
    assert (
        table.get("RSynaptic") == "unsupported"
    ), f"Expected 'unsupported' for RSynaptic on lava_sim, got {table.get('RSynaptic')!r}"


# ---------------------------------------------------------------------------
# Integration test: cnl.RSynaptic + cnl.Synaptic through snnTorch simulator
# ---------------------------------------------------------------------------


def test_snntorch_simulator_runs_rsynaptic_and_synaptic() -> None:
    """Minimal RSynaptic→Synaptic graph runs 10 timesteps without error.

    Verifies:
    - make_nir_graph accepts cnl nodes with skip_type_check=True
    - SnnTorchSimulatorAdapter constructs modules for cnl.RSynaptic and cnl.Synaptic
    - Result contains spike and voltage records for both spiking populations
    """
    try:
        from neurocnl.runtime.snntorch_simulator import SnnTorchSimulatorAdapter
        from neurocnl.runtime.stimulus import ValidatedStimulus
    except ImportError:
        pytest.skip("snntorch_simulator not importable in this environment")

    try:
        import snntorch  # noqa: F401
        import torch  # noqa: F401
    except ImportError:
        pytest.skip("torch or snntorch not installed")

    n = 4
    T = 10

    input_node = nir.Input(input_type=np.array([n]))
    linear = nir.Linear(weight=np.eye(n, dtype=np.float32))
    rsynaptic = RSynaptic(n_neurons=n, alpha=0.9, beta=0.8, threshold=1.0)
    synaptic = Synaptic(n_neurons=n, alpha=0.9, beta=0.8, threshold=1.0)
    output_node = nir.Output(output_type=np.array([n]))

    graph = make_nir_graph(
        nodes={
            "input": input_node,
            "linear": linear,
            "rsyn": rsynaptic,
            "syn": synaptic,
            "output": output_node,
        },
        edges=[
            ("input", "linear"),
            ("linear", "rsyn"),
            ("rsyn", "syn"),
            ("syn", "output"),
        ],
    )

    # Spike on every even timestep for all neurons
    stimulus = ValidatedStimulus(
        population="input",
        neuron_count=n,
        spikes={i: list(range(0, T, 2)) for i in range(n)},
    )

    adapter = SnnTorchSimulatorAdapter()
    result = adapter.run(graph=graph, stimulus=stimulus, timesteps=T, seed=0)

    assert result is not None, "Adapter returned None"
    # Both spiking populations must appear in spike and voltage records
    assert (
        "rsyn" in result.spikes
    ), f"rsyn missing from spikes; got keys: {list(result.spikes)}"
    assert (
        "syn" in result.spikes
    ), f"syn missing from spikes; got keys: {list(result.spikes)}"
    assert "rsyn" in result.voltages, "rsyn missing from voltages"
    assert "syn" in result.voltages, "syn missing from voltages"
    # Each population must have n neuron traces
    assert len(result.voltages["rsyn"]) == n
    assert len(result.voltages["syn"]) == n
