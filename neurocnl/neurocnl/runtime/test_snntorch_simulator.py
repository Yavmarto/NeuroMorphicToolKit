"""Tests for neurocnl.runtime.snntorch_simulator — snnTorch simulator adapter.

All tests use unittest.mock to avoid requiring a real torch/snntorch installation.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import nir
import numpy as np
import pytest

from neurocnl.runtime.snntorch_simulator import (
    SnnTorchDispatchError,
    SnnTorchSimulatorAdapter,
    SnnTorchSimulatorResult,
    _discretize,
    _lif_threshold,
    _topological_sort,
)
from neurocnl.runtime.stimulus import ValidatedStimulus

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _lif_node(n: int = 2, tau: float = 2.0, threshold: float = 1.0) -> nir.LIF:
    return nir.LIF(
        tau=np.full(n, tau),
        r=np.ones(n),
        v_leak=np.zeros(n),
        v_threshold=np.full(n, threshold),
    )


def _make_graph(input_size: int = 2, output_size: int = 2) -> nir.NIRGraph:
    """Minimal: Input → Linear → LIF → Output."""
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([input_size])),
            "weight": nir.Linear(weight=np.eye(output_size, input_size)),
            "lif": _lif_node(output_size),
            "output": nir.Output(output_type=np.array([output_size])),
        },
        edges=[("input", "weight"), ("weight", "lif"), ("lif", "output")],
    )


def _make_stimulus(pop: str = "input", n: int = 2) -> ValidatedStimulus:
    return ValidatedStimulus(population=pop, neuron_count=n, spikes={0: [0, 2]})


def _make_mock_snntorch(
    spk_values: list[float] | None = None,
    mem_values: list[float] | None = None,
) -> tuple[MagicMock, MagicMock, MagicMock]:
    """Build (torch, nn, snntorch) mocks.

    The key pattern: use ``MagicMock(return_value=...)`` so that calling the
    mock instance directly (``module(x, mem)``) returns the right value.
    MagicMock's ``__call__`` special method is managed by the class, not the
    instance — so ``obj.__call__ = ...`` does NOT affect ``obj()``.
    """
    if spk_values is None:
        spk_values = [0.0, 0.0]
    if mem_values is None:
        mem_values = [0.5, 0.5]

    mock_torch = MagicMock()
    mock_torch.float32 = float
    mock_torch.manual_seed = MagicMock()

    # zeros() returns a tensor-like that supports __setitem__ and tolist()
    zeros_tensor = MagicMock()
    zeros_tensor.tolist.return_value = [0.0] * len(spk_values)
    mock_torch.zeros.return_value = zeros_tensor

    # no_grad() context manager
    no_grad_ctx = MagicMock()
    no_grad_ctx.__enter__ = MagicMock(return_value=None)
    no_grad_ctx.__exit__ = MagicMock(return_value=False)
    mock_torch.no_grad.return_value = no_grad_ctx

    mock_torch.tensor.return_value = MagicMock()

    mock_nn = MagicMock()
    # nn.Linear(...) → linear instance
    # Calling the linear instance returns zeros_tensor
    linear_instance = MagicMock(return_value=zeros_tensor)
    linear_instance.weight = MagicMock()
    linear_instance.weight.copy_ = MagicMock()
    linear_instance.weight.requires_grad_ = MagicMock()
    mock_nn.Linear.return_value = linear_instance

    mock_snntorch = MagicMock()
    # snntorch.Leaky(...) → leaky instance
    # Calling the leaky instance returns (spk_tensor, mem_tensor)
    spk_tensor = MagicMock()
    spk_tensor.tolist.return_value = spk_values
    mem_tensor = MagicMock()
    mem_tensor.tolist.return_value = mem_values

    leaky_instance = MagicMock(return_value=(spk_tensor, mem_tensor))
    leaky_instance.init_leaky.return_value = MagicMock()
    mock_snntorch.Leaky.return_value = leaky_instance

    return mock_torch, mock_nn, mock_snntorch


# ---------------------------------------------------------------------------
# _topological_sort
# ---------------------------------------------------------------------------


def test_topological_sort_valid_graph() -> None:
    graph = _make_graph()
    order = _topological_sort(graph)
    assert order.index("weight") < order.index("lif")


def test_topological_sort_all_nodes_present() -> None:
    graph = _make_graph()
    order = _topological_sort(graph)
    assert set(order) == set(graph.nodes)


def test_topological_sort_cycle_raises() -> None:
    # Use type_check=False so NIR accepts the cycle graph
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([2])),
            "a": nir.Linear(weight=np.eye(2)),
            "b": nir.Linear(weight=np.eye(2)),
        },
        edges=[("input", "a"), ("a", "b"), ("b", "a")],
        type_check=False,
    )
    with pytest.raises(SnnTorchDispatchError, match="cycle"):
        _topological_sort(graph)


# ---------------------------------------------------------------------------
# _discretize / _lif_threshold
# ---------------------------------------------------------------------------


def test_discretize_uses_seconds_and_graph_timestep() -> None:
    """tau is seconds; beta = 1 - dt/tau at the default 1e-4 s timestep."""
    assert _discretize(_lif_node(tau=0.002), None).beta == pytest.approx(0.95)
    assert _discretize(_lif_node(tau=0.02), None).beta == pytest.approx(0.995)


def test_discretize_rescales_threshold_like_snntorch_import_nir() -> None:
    """Threshold divides by r*dt/tau, matching the model the network trained under."""
    d = _discretize(_lif_node(tau=0.002), None)
    assert d.input_scale == pytest.approx(0.05)
    assert d.threshold == pytest.approx(20.0)


def test_discretize_honours_graph_timestep() -> None:
    graph = nir.NIRGraph(nodes={}, edges=[], metadata={"dt": 0.001})
    assert _discretize(_lif_node(tau=0.02), graph).beta == pytest.approx(0.95)


def test_discretize_rejects_timestep_at_or_above_tau() -> None:
    """No silent clamp: a tau below the timestep is a dispatch error, not beta=0.01.

    The previous exp(-1/tau) + [0.01, 0.99] clamp mapped every realistic tau to
    0.01, which is what saturated the raster.
    """
    graph = nir.NIRGraph(nodes={}, edges=[], metadata={"dt": 0.01})
    with pytest.raises(SnnTorchDispatchError, match="unstable"):
        _discretize(_lif_node(tau=0.002), graph)


def test_discretize_rejects_non_positive_tau() -> None:
    with pytest.raises(SnnTorchDispatchError):
        _discretize(_lif_node(tau=0.0), None)


def test_discretize_reads_tau_mem_on_cubalif() -> None:
    """Regression: CubaLIF has no .tau, so it used to fall back to beta=0.9."""
    node = nir.CubaLIF(
        tau_mem=np.full(2, 0.002),
        tau_syn=np.full(2, 0.001),
        r=np.ones(2),
        v_leak=np.zeros(2),
        v_threshold=np.ones(2),
        w_in=np.ones(2),
    )
    d = _discretize(node, None)
    assert d.beta == pytest.approx(0.95)
    assert d.alpha == pytest.approx(0.9)
    assert d.beta != pytest.approx(0.9)


def test_lif_threshold_mean() -> None:
    node = nir.LIF(
        tau=np.full(2, 2.0),
        r=np.ones(2),
        v_leak=np.zeros(2),
        v_threshold=np.array([1.0, 2.0]),
    )
    assert _lif_threshold(node) == pytest.approx(1.5)


# ---------------------------------------------------------------------------
# SnnTorchSimulatorAdapter — full mocked run
# ---------------------------------------------------------------------------


@patch("neurocnl.runtime.snntorch_simulator._import_snntorch")
def test_run_returns_in_process_runtime_mode(mock_import: MagicMock) -> None:
    mock_torch, mock_nn, mock_snntorch = _make_mock_snntorch()
    mock_import.return_value = (mock_torch, mock_nn, mock_snntorch)

    result = SnnTorchSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=5, seed=1
    )

    assert isinstance(result, SnnTorchSimulatorResult)
    assert result.runtime_mode == "in_process_snntorch_sim"
    assert isinstance(result.execution_time_ms, float)


@patch("neurocnl.runtime.snntorch_simulator._import_snntorch")
def test_run_returns_voltages_dict(mock_import: MagicMock) -> None:
    mock_torch, mock_nn, mock_snntorch = _make_mock_snntorch(mem_values=[0.42, 0.42])
    mock_import.return_value = (mock_torch, mock_nn, mock_snntorch)

    result = SnnTorchSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=3, seed=0
    )

    assert isinstance(result.voltages, dict)
    # voltages must contain the output population
    if result.voltages:
        for pop, neurons in result.voltages.items():
            assert isinstance(pop, str)
            for idx_str, traces in neurons.items():
                assert isinstance(idx_str, str)
                assert isinstance(traces, list)


@patch("neurocnl.runtime.snntorch_simulator._import_snntorch")
def test_no_spikes_adds_warning(mock_import: MagicMock) -> None:
    mock_torch, mock_nn, mock_snntorch = _make_mock_snntorch(spk_values=[0.0, 0.0])
    mock_import.return_value = (mock_torch, mock_nn, mock_snntorch)

    result = SnnTorchSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=5, seed=1
    )

    assert any("no spikes" in w.lower() for w in result.warnings)


@patch("neurocnl.runtime.snntorch_simulator._import_snntorch")
def test_spikes_recorded_in_shared_schema(mock_import: MagicMock) -> None:
    mock_torch, mock_nn, mock_snntorch = _make_mock_snntorch(spk_values=[1.0, 1.0])
    mock_import.return_value = (mock_torch, mock_nn, mock_snntorch)

    result = SnnTorchSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=3, seed=1
    )

    # spikes must be {pop_name: {neuron_idx_str: [timestep, ...]}}
    for pop, neurons in result.spikes.items():
        assert isinstance(pop, str)
        for idx_str, times in neurons.items():
            assert isinstance(idx_str, str)
            assert all(isinstance(t, int) for t in times)


@patch("neurocnl.runtime.snntorch_simulator._import_snntorch")
def test_cubalf_adds_approximate_warning(mock_import: MagicMock) -> None:
    mock_torch, mock_nn, mock_snntorch = _make_mock_snntorch()
    mock_import.return_value = (mock_torch, mock_nn, mock_snntorch)

    n = 2
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([n])),
            "weight": nir.Linear(weight=np.eye(n)),
            "cuba": nir.CubaLIF(
                tau_mem=np.full(n, 2.0),
                tau_syn=np.full(n, 1.0),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.ones(n),
            ),
            "output": nir.Output(output_type=np.array([n])),
        },
        edges=[("input", "weight"), ("weight", "cuba"), ("cuba", "output")],
    )

    result = SnnTorchSimulatorAdapter().run(
        graph, _make_stimulus(), timesteps=3, seed=1
    )

    assert any("CubaLIF" in w or "approximate" in w.lower() for w in result.warnings)


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


def test_import_error_raises_dispatch_error() -> None:
    with (
        patch(
            "neurocnl.runtime.snntorch_simulator._import_snntorch",
            side_effect=ImportError("No module named 'snntorch'"),
        ),
        pytest.raises(SnnTorchDispatchError) as exc_info,
    ):
        SnnTorchSimulatorAdapter().run(
            _make_graph(), _make_stimulus(), timesteps=5, seed=1
        )
    assert any(
        "snntorch" in d.lower() or "torch" in d.lower()
        for d in exc_info.value.diagnostics
    )


@patch("neurocnl.runtime.snntorch_simulator._import_snntorch")
def test_runtime_error_wrapped_as_dispatch_error(mock_import: MagicMock) -> None:
    mock_torch, mock_nn, mock_snntorch = _make_mock_snntorch()
    # Make the Leaky forward raise
    mock_snntorch.Leaky.return_value.side_effect = RuntimeError("CUDA out of memory")
    mock_import.return_value = (mock_torch, mock_nn, mock_snntorch)

    with pytest.raises(SnnTorchDispatchError) as exc_info:
        SnnTorchSimulatorAdapter().run(
            _make_graph(), _make_stimulus(), timesteps=5, seed=1
        )
    assert exc_info.value.diagnostics


@patch("neurocnl.runtime.snntorch_simulator._import_snntorch")
def test_empty_graph_raises_dispatch_error(mock_import: MagicMock) -> None:
    """A graph with no LIF/Linear layers must raise SnnTorchDispatchError."""
    mock_torch, mock_nn, mock_snntorch = _make_mock_snntorch()
    mock_import.return_value = (mock_torch, mock_nn, mock_snntorch)

    empty_graph = nir.NIRGraph(nodes={}, edges=[])

    with pytest.raises(SnnTorchDispatchError):
        SnnTorchSimulatorAdapter().run(
            empty_graph, _make_stimulus(), timesteps=5, seed=1
        )
