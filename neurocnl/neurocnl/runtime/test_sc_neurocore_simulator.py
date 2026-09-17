"""Tests for neurocnl.runtime.sc_neurocore_simulator.

All tests use unittest.mock to avoid requiring a real sc-neurocore installation.
The tests verify that the adapter:

- Correctly handles a basic feed-forward NIR graph (Input → Linear → LIF → Output).
- Builds Population / SpikeMonitor objects from LIF nodes.
- Properly returns the shared SimulatorRunResult spike/voltage schema.
- Degrades gracefully when sc-neurocore is missing.
- Wraps unexpected runtime errors as ScNeuroCoreDispatchError.
"""

from __future__ import annotations

from typing import Any
from unittest.mock import MagicMock, patch

import nir
import numpy as np
import pytest

from neurocnl.runtime.sc_neurocore_simulator import (
    ScNeuroCoreDispatchError,
    ScNeuroCoreSimulatorAdapter,
    ScNeuroCoreSimulatorResult,
    _build_spike_record,
    _infer_output_population,
    _lif_params_for_node,
    _topological_sort,
    sc_neurocore_nir_bridge_available,
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
    """Minimal feed-forward graph: Input -> Linear -> LIF -> Output."""
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


def _make_mock_sc_neurocore(
    spike_raster: tuple[Any, Any] | None = None,
    voltage: np.ndarray[Any, Any] | None = None,
) -> MagicMock:
    """Return a mock sc_neurocore module configured for the network API."""
    if spike_raster is None:
        spike_raster = (np.array([0, 1]), np.array([0, 1]))
    if voltage is None:
        voltage = np.array([0.3, 0.5])

    mock_pop = MagicMock()
    mock_pop.n = 2
    mock_pop.step_all = MagicMock(return_value=np.array([1, 0], dtype=np.int8))
    mock_pop.get_states = MagicMock(return_value={"v": voltage.copy()})

    mock_mon = MagicMock()
    mock_mon.record = MagicMock()
    mock_mon.raster_data = MagicMock(return_value=spike_raster)

    sc = MagicMock()
    sc.network.Population = MagicMock(return_value=mock_pop)
    sc.network.SpikeMonitor = MagicMock(return_value=mock_mon)
    sc.neurons.StochasticLIFNeuron = MagicMock()
    return sc


# ---------------------------------------------------------------------------
# _lif_params_for_node
# ---------------------------------------------------------------------------


def test_lif_params_maps_tau_and_threshold() -> None:
    """tau arrives in seconds and is converted to timesteps for sc-neurocore.

    sc-neurocore integrates at ``dt = 1``, so a 5 s time constant at the default
    1e-4 s timestep is 50000 steps. Passing the raw 5.0 through would have made
    the neuron 10000x leakier than the network it came from.
    """
    node = _lif_node(n=3, tau=5.0, threshold=0.8)
    params = _lif_params_for_node(node, seed=42)
    assert params["tau_mem"] == pytest.approx(5.0 / 1e-4)
    assert params["v_threshold"] == pytest.approx(0.8)
    assert params["dt"] == 1.0
    assert params["seed"] == 42


def test_lif_params_folds_input_gain_into_resistance() -> None:
    """resistance carries r*dt/tau so the recurrence matches snnTorch's Leaky.

    Scaling resistance rather than the threshold keeps v_threshold, v_reset and
    the reported membrane trace in true NIR voltage units, directly comparable
    to the other backends' panels.
    """
    node = _lif_node(n=3, tau=0.002, threshold=1.0)
    params = _lif_params_for_node(node, seed=0)
    assert params["resistance"] == pytest.approx(1.0 * 1e-4 / 0.002)
    assert params["v_threshold"] == pytest.approx(1.0)
    # beta implied by tau_steps must be the trained 0.95, not -499.
    assert 1.0 - 1.0 / params["tau_mem"] == pytest.approx(0.95)


def test_lif_params_rejects_non_positive_tau() -> None:
    """A zero time constant is a hard error, not a silently clamped 1e-6."""
    with pytest.raises(ValueError, match="time constant"):
        _lif_params_for_node(_lif_node(tau=0.0), seed=0)


# ---------------------------------------------------------------------------
# _topological_sort
# ---------------------------------------------------------------------------


def test_topological_sort_feedforward() -> None:
    graph = _make_graph()
    order, in_edges = _topological_sort(graph)
    assert order.index("input") < order.index("weight")
    assert order.index("weight") < order.index("lif")


# ---------------------------------------------------------------------------
# _infer_output_population
# ---------------------------------------------------------------------------


def test_infer_output_population_finds_last_lif() -> None:
    graph = _make_graph()
    assert _infer_output_population(graph) == "lif"


def test_infer_output_population_fallback_to_last_node() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([2])),
            "weight": nir.Linear(weight=np.eye(2)),
        },
        edges=[("input", "weight")],
    )
    result = _infer_output_population(graph)
    assert result in graph.nodes


# ---------------------------------------------------------------------------
# _build_spike_record
# ---------------------------------------------------------------------------


def test_build_spike_record_flat_dict() -> None:
    raw = {"0": [0, 1], "1": [2]}
    result = _build_spike_record(raw, "lif", 5)
    assert "lif" in result
    assert result["lif"]["0"] == [0, 1]
    assert result["lif"]["1"] == [2]


def test_build_spike_record_nested_dict() -> None:
    raw = {"lif": {"0": [0], "1": [1, 2]}}
    result = _build_spike_record(raw, "lif", 5)
    assert result["lif"]["0"] == [0]
    assert result["lif"]["1"] == [1, 2]


def test_build_spike_record_2d_matrix() -> None:
    raw = np.array([[1, 0], [0, 1], [0, 1]], dtype=np.uint8)
    result = _build_spike_record(raw, "lif", 3)
    assert result["lif"]["0"] == [0]
    assert result["lif"]["1"] == [1, 2]


def test_build_spike_record_none_returns_empty() -> None:
    result = _build_spike_record(None, "lif", 5)
    assert result == {}


# ---------------------------------------------------------------------------
# ScNeuroCoreSimulatorAdapter -- mocked runs using new network API
# ---------------------------------------------------------------------------


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_run_returns_correct_runtime_mode(mock_import: MagicMock) -> None:
    mock_import.return_value = _make_mock_sc_neurocore()
    result = ScNeuroCoreSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=5, seed=1
    )
    assert isinstance(result, ScNeuroCoreSimulatorResult)
    assert result.runtime_mode == "in_process_sc_neurocore_sim"


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_run_returns_spikes_in_shared_schema(mock_import: MagicMock) -> None:
    spike_raster = (np.array([0, 2]), np.array([0, 1]))
    mock_import.return_value = _make_mock_sc_neurocore(spike_raster=spike_raster)
    result = ScNeuroCoreSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=5, seed=1
    )
    for pop, neurons in result.spikes.items():
        assert isinstance(pop, str)
        for idx_str, times in neurons.items():
            assert isinstance(idx_str, str)
            assert all(isinstance(t, int) for t in times)


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_run_returns_voltages_dict(mock_import: MagicMock) -> None:
    mock_import.return_value = _make_mock_sc_neurocore(voltage=np.array([0.7, 0.3]))
    result = ScNeuroCoreSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=3, seed=1
    )
    assert isinstance(result.voltages, dict)


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_run_no_spikes_adds_warning(mock_import: MagicMock) -> None:
    empty_raster = (np.array([]), np.array([]))
    mock_import.return_value = _make_mock_sc_neurocore(spike_raster=empty_raster)
    result = ScNeuroCoreSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=5, seed=1
    )
    assert any("no spikes" in w.lower() for w in result.warnings)


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_run_execution_time_is_float(mock_import: MagicMock) -> None:
    mock_import.return_value = _make_mock_sc_neurocore()
    result = ScNeuroCoreSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=10, seed=0
    )
    assert isinstance(result.execution_time_ms, float)
    assert result.execution_time_ms >= 0.0


def test_scalar_tau_lif_graph_uses_linear_weight_width() -> None:
    """Regression: CNL graphs with scalar tau must not simulate as n=1.

    Without width reconciliation, a 30-neuron hidden layer is built as a single
    neuron, input currents are truncated to one synapse, and the run returns 0
    spikes while snnTorch on the same graph fires normally.
    """
    pytest.importorskip("sc_neurocore")

    n = 4
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([n])),
            "weight": nir.Linear(weight=np.eye(n, dtype=float) * 0.5),
            "lif": nir.LIF(
                tau=np.float64(0.02),
                r=np.ones(1),
                v_leak=np.zeros(1),
                v_threshold=np.full(1, 0.2),
            ),
            "output": nir.Output(output_type=np.array([n])),
        },
        edges=[("input", "weight"), ("weight", "lif"), ("lif", "output")],
        type_check=False,
    )
    stimulus = ValidatedStimulus(
        population="input",
        neuron_count=n,
        spikes={i: [0, 1, 2] for i in range(n)},
    )

    result = ScNeuroCoreSimulatorAdapter().run(graph, stimulus, timesteps=5, seed=0)
    total = sum(len(times) for pop in result.spikes.values() for times in pop.values())
    assert total > 0, f"expected spikes after width reconciliation, got {result.spikes}"


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_run_population_step_called_each_timestep(mock_import: MagicMock) -> None:
    """Population.step_all() must be called once per timestep."""
    sc = _make_mock_sc_neurocore()
    mock_import.return_value = sc
    timesteps = 4
    ScNeuroCoreSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=timesteps, seed=1
    )
    mock_pop = sc.network.Population.return_value
    assert mock_pop.step_all.call_count == timesteps


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_run_cubalf_adds_approximation_warning(mock_import: MagicMock) -> None:
    sc = _make_mock_sc_neurocore()
    mock_import.return_value = sc
    n = 2
    cuba_graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([n])),
            "weight": nir.Linear(weight=np.eye(n)),
            "cuba": nir.CubaLIF(
                tau_mem=np.full(n, 5.0),
                tau_syn=np.full(n, 2.0),
                r=np.ones(n),
                v_leak=np.zeros(n),
                v_threshold=np.ones(n),
            ),
            "output": nir.Output(output_type=np.array([n])),
        },
        edges=[("input", "weight"), ("weight", "cuba"), ("cuba", "output")],
    )
    result = ScNeuroCoreSimulatorAdapter().run(
        cuba_graph, _make_stimulus(), timesteps=3, seed=1
    )
    assert any("CubaLIF" in w for w in result.warnings)


# ---------------------------------------------------------------------------
# sc_neurocore_nir_bridge_available
# ---------------------------------------------------------------------------


def test_nir_bridge_available_returns_true_when_from_nir_present() -> None:
    with patch.dict(
        "sys.modules",
        {
            "sc_neurocore": MagicMock(),
            "sc_neurocore.nir_bridge": MagicMock(),
        },
    ):
        assert sc_neurocore_nir_bridge_available() is True


def test_nir_bridge_available_returns_false_when_not_installed() -> None:
    with patch.dict(
        "sys.modules",
        {
            "sc_neurocore": None,
            "sc_neurocore.nir_bridge": None,
        },
    ):
        assert sc_neurocore_nir_bridge_available() is False


def test_nir_bridge_available_returns_false_when_nir_bridge_missing() -> None:
    with patch.dict(
        "sys.modules",
        {
            "sc_neurocore": MagicMock(),
            "sc_neurocore.nir_bridge": None,
        },
    ):
        assert sc_neurocore_nir_bridge_available() is False


def test_nir_bridge_available_returns_false_when_from_nir_missing() -> None:
    with patch.dict(
        "sys.modules",
        {
            "sc_neurocore": MagicMock(),
            "sc_neurocore.nir_bridge": MagicMock(spec=[]),  # from_nir absent
        },
    ):
        assert sc_neurocore_nir_bridge_available() is False


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


def test_import_error_raises_dispatch_error() -> None:
    with (
        patch(
            "neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore",
            side_effect=ImportError("No module named 'sc_neurocore'"),
        ),
        pytest.raises(ScNeuroCoreDispatchError) as exc_info,
    ):
        ScNeuroCoreSimulatorAdapter().run(
            _make_graph(), _make_stimulus(), timesteps=5, seed=1
        )
    assert any("sc-neurocore" in d.lower() for d in exc_info.value.diagnostics)


@patch("neurocnl.runtime.sc_neurocore_simulator._import_sc_neurocore")
def test_step_all_failure_raises_dispatch_error(mock_import: MagicMock) -> None:
    sc = _make_mock_sc_neurocore()
    sc.network.Population.return_value.step_all.side_effect = RuntimeError("OOM")
    mock_import.return_value = sc

    with pytest.raises(ScNeuroCoreDispatchError, match="simulation failed"):
        ScNeuroCoreSimulatorAdapter().run(
            _make_graph(), _make_stimulus(), timesteps=5, seed=1
        )
