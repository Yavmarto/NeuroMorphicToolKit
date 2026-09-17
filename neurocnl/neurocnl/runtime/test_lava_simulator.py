"""Tests for neurocnl.runtime.lava_simulator — Lava simulator adapter.

All tests use unittest.mock to avoid requiring a real lava-nc installation.
"""

from __future__ import annotations

from typing import Any
from unittest.mock import MagicMock, patch

import nir
import numpy as np
import pytest

from neurocnl.runtime.lava_simulator import (
    LavaDispatchError,
    LavaSimulatorAdapter,
    LavaSimulatorResult,
    _extract_voltages_from_monitor,
    _infer_output_population,
    _normalize_flat_spikes,
)
from neurocnl.runtime.stimulus import ValidatedStimulus

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_graph(input_size: int = 2, output_size: int = 2) -> nir.NIRGraph:
    """A minimal NIR graph: Input → Linear → LIF → Output."""
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([input_size])),
            "weight": nir.Linear(weight=np.eye(output_size, input_size)),
            "lif": nir.LIF(
                tau=np.full(output_size, 0.02),
                r=np.ones(output_size),
                v_leak=np.zeros(output_size),
                v_threshold=np.ones(output_size),
            ),
            "output": nir.Output(output_type=np.array([output_size])),
        },
        edges=[("input", "weight"), ("weight", "lif"), ("lif", "output")],
    )


def _make_stimulus(pop: str = "input", n: int = 2) -> ValidatedStimulus:
    return ValidatedStimulus(population=pop, neuron_count=n, spikes={0: [0, 5, 10]})


# ---------------------------------------------------------------------------
# _normalize_flat_spikes
# ---------------------------------------------------------------------------


def test_normalize_flat_spikes_wraps_under_population_name() -> None:
    flat = {"0": [0, 5, 10], "1": [3, 8]}
    result = _normalize_flat_spikes(flat, "lif")
    assert result == {"lif": {"0": [0, 5, 10], "1": [3, 8]}}


def test_normalize_flat_spikes_drops_empty_lists() -> None:
    flat = {"0": [1, 2], "1": []}
    result = _normalize_flat_spikes(flat, "output")
    # "1" has empty list → filtered out
    assert "1" not in result["output"]
    assert result["output"]["0"] == [1, 2]


def test_normalize_flat_spikes_empty_input() -> None:
    result = _normalize_flat_spikes({}, "lif")
    assert result == {"lif": {}}


def test_extract_spikes_from_monitor_falls_back_to_first_s_out() -> None:
    from neurocnl.runtime.lava_simulator import _extract_spikes_from_monitor

    process = MagicMock()
    process.name = "unexpected_lava_name"
    raw = {
        "lif_pop": {
            "s_out": np.array([[1, 0], [0, 1], [1, 0]], dtype=int),
        }
    }
    spikes = _extract_spikes_from_monitor(raw, process, "lif")
    assert spikes == {"lif": {"0": [0, 2], "1": [1]}}


# ---------------------------------------------------------------------------
# _infer_output_population
# ---------------------------------------------------------------------------


def test_infer_output_population_returns_last_lif() -> None:
    graph = _make_graph()
    name = _infer_output_population(graph)
    assert name == "lif"


def test_infer_output_population_fallback_to_last_node() -> None:
    # NIR normalises a graph with only an Output node by adding boundary Input nodes.
    # Use a Linear node (not LIF or Output) to test the non-LIF fallback path.
    graph = nir.NIRGraph(nodes={"dense": nir.Linear(weight=np.eye(2))}, edges=[])
    name = _infer_output_population(graph)
    # Falls back to the last node name in the graph
    assert name in graph.nodes


# ---------------------------------------------------------------------------
# LavaSimulatorAdapter — in-process path (mocked)
# ---------------------------------------------------------------------------


def _make_mock_lava_classes() -> dict[str, Any]:
    """Return mock Lava classes that behave like the real ones."""
    mock_lif = MagicMock()
    mock_lif.s_out = MagicMock()
    mock_pm = MagicMock()
    mock_pm.v = np.zeros(2, dtype=float)
    mock_lif._process_model = mock_pm
    mock_dense = MagicMock()
    mock_dense.a_out = MagicMock()
    mock_dense.s_in = MagicMock()
    mock_monitor = MagicMock()
    mock_monitor.get_data.return_value = {}  # no spikes by default
    mock_run_steps = MagicMock()
    mock_sim_cfg = MagicMock()
    mock_ring_buffer = MagicMock()
    mock_ring_buffer.s_out = MagicMock()

    LIF = MagicMock(return_value=mock_lif)
    Dense = MagicMock(return_value=mock_dense)
    Monitor = MagicMock(return_value=mock_monitor)
    RunSteps = MagicMock(return_value=mock_run_steps)
    Loihi2SimCfg = MagicMock(return_value=mock_sim_cfg)
    RingBuffer = MagicMock(return_value=mock_ring_buffer)

    return {
        "LIF": LIF,
        "Dense": Dense,
        "Monitor": Monitor,
        "RunSteps": RunSteps,
        "Loihi2SimCfg": Loihi2SimCfg,
        "RingBuffer": RingBuffer,
        "lif_instance": mock_lif,
        "monitor_instance": mock_monitor,
        "ring_buffer_instance": mock_ring_buffer,
    }


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator._import_lava")
def test_in_process_returns_lava_sim_runtime_mode(
    mock_import: MagicMock, mock_avail: MagicMock
) -> None:
    mocks = _make_mock_lava_classes()
    mock_import.return_value = (
        mocks["LIF"],
        mocks["Dense"],
        mocks["Monitor"],
        mocks["RunSteps"],
        mocks["Loihi2SimCfg"],
        mocks["RingBuffer"],
    )
    # Simulate run succeeding
    mocks["lif_instance"].run = MagicMock()

    adapter = LavaSimulatorAdapter()
    result = adapter.run(_make_graph(), _make_stimulus(), timesteps=50, seed=1)

    assert isinstance(result, LavaSimulatorResult)
    assert result.runtime_mode == "in_process_lava_sim"
    assert isinstance(result.execution_time_ms, float)


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator._import_lava")
def test_in_process_no_spikes_adds_warning(
    mock_import: MagicMock, mock_avail: MagicMock
) -> None:
    mocks = _make_mock_lava_classes()
    mock_import.return_value = (
        mocks["LIF"],
        mocks["Dense"],
        mocks["Monitor"],
        mocks["RunSteps"],
        mocks["Loihi2SimCfg"],
        mocks["RingBuffer"],
    )
    mocks["lif_instance"].run = MagicMock()
    mocks["monitor_instance"].get_data.return_value = {}  # no spikes

    result = LavaSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=50, seed=1
    )

    # The population keeps its key with an empty value, matching snnTorch and
    # sc-neurocore. Dropping the key made Lava the only backend where a silent
    # run showed "no populations" instead of an empty raster.
    assert result.spikes == {"lif": {}}
    assert len(result.warnings) >= 1
    assert any("no spikes" in w.lower() for w in result.warnings)


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator._import_lava")
def test_in_process_lava_backend_error_becomes_dispatch_error(
    mock_import: MagicMock, mock_avail: MagicMock
) -> None:
    mocks = _make_mock_lava_classes()
    mock_import.return_value = (
        mocks["LIF"],
        mocks["Dense"],
        mocks["Monitor"],
        mocks["RunSteps"],
        mocks["Loihi2SimCfg"],
        mocks["RingBuffer"],
    )
    mocks["lif_instance"].run = MagicMock(
        side_effect=RuntimeError("Lava process failed")
    )

    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter().run(
            _make_graph(), _make_stimulus(), timesteps=50, seed=1
        )

    assert exc_info.value.diagnostics
    assert any("failed" in d.lower() for d in exc_info.value.diagnostics)


# ---------------------------------------------------------------------------
# LavaSimulatorAdapter — remote worker path (mocked)
# ---------------------------------------------------------------------------


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=False)
@patch("neurocnl.runtime.lava_simulator.LavaIO")
def test_remote_path_used_when_no_local_lava(
    mock_lava_io_cls: MagicMock, mock_avail: MagicMock
) -> None:
    mock_io = MagicMock()
    mock_lava_io_cls.return_value = mock_io
    mock_io.compile_and_run_remote.return_value = {
        "compile": {"session_id": "abc"},
        "run": {
            "status": "success",
            "spikes": {"0": [0, 5, 10], "1": [3, 8]},
            "execution_time_ms": 20.0,
        },
    }

    result = LavaSimulatorAdapter().run(
        _make_graph(),
        _make_stimulus(),
        timesteps=50,
        seed=1,
        worker_url="http://fake-worker:8080",
    )

    assert result.runtime_mode == "remote_lava_sim_worker"
    assert result.execution_time_ms == 20.0
    # Spikes should be wrapped under the inferred output population name
    assert len(result.spikes) == 1
    pop_name = list(result.spikes)[0]
    assert result.spikes[pop_name]["0"] == [0, 5, 10]

    # Verify it was called with the right keyword arguments (graph identity not checked
    # because nir.NIRGraph contains numpy arrays that don't compare equal by value).
    call_kwargs = mock_io.compile_and_run_remote.call_args[1]
    assert call_kwargs["base_url"] == "http://fake-worker:8080"
    assert call_kwargs["steps"] == 50
    assert call_kwargs["run_config"] == "sim"


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=False)
@patch("neurocnl.runtime.lava_simulator.LavaIO")
def test_remote_path_runtime_error_becomes_dispatch_error(
    mock_lava_io_cls: MagicMock, mock_avail: MagicMock
) -> None:
    mock_io = MagicMock()
    mock_lava_io_cls.return_value = mock_io
    mock_io.compile_and_run_remote.side_effect = RuntimeError("Connection refused")

    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter().run(
            _make_graph(),
            _make_stimulus(),
            timesteps=50,
            seed=1,
            worker_url="http://fake-worker:8080",
        )

    assert any("Connection refused" in d for d in exc_info.value.diagnostics)


# ---------------------------------------------------------------------------
# LavaSimulatorAdapter — no path available
# ---------------------------------------------------------------------------


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=False)
def test_no_lava_and_no_worker_raises_dispatch_error(mock_avail: MagicMock) -> None:
    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter().run(
            _make_graph(),
            _make_stimulus(),
            timesteps=50,
            seed=1,
            worker_url=None,
        )
    assert exc_info.value.diagnostics
    assert any(
        "not installed" in d or "not set" in d for d in exc_info.value.diagnostics
    )


# ---------------------------------------------------------------------------
# LavaSimulatorAdapter — voltage extraction
# ---------------------------------------------------------------------------


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator._import_lava")
def test_in_process_returns_voltages_dict(
    mock_import: MagicMock, mock_avail: MagicMock
) -> None:
    mocks = _make_mock_lava_classes()
    mock_import.return_value = (
        mocks["LIF"],
        mocks["Dense"],
        mocks["Monitor"],
        mocks["RunSteps"],
        mocks["Loihi2SimCfg"],
        mocks["RingBuffer"],
    )
    mocks["lif_instance"].run = MagicMock()
    mocks["lif_instance"].name = "lif"
    mocks["lif_instance"]._process_model.v = np.array([-65.0, -70.0], dtype=float)

    spike_arr = np.zeros((50, 2), dtype=int)
    spike_arr[5, 0] = 1
    spike_arr[15, 0] = 1
    spike_arr[25, 0] = 1
    mocks["monitor_instance"].get_data.return_value = {
        "lif": {"s_out": spike_arr},
    }

    result = LavaSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=50, seed=1
    )

    assert isinstance(result.voltages, dict)
    assert "lif" in result.voltages
    assert "0" in result.voltages["lif"]
    assert "1" in result.voltages["lif"]
    assert len(result.voltages["lif"]["0"]) == 50
    assert isinstance(result.voltages["lif"]["0"][0], float)


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator._import_lava")
def test_in_process_no_voltage_data_returns_empty_voltages(
    mock_import: MagicMock, mock_avail: MagicMock
) -> None:
    """When process model has no v attribute, result.voltages is empty."""
    mocks = _make_mock_lava_classes()
    mock_import.return_value = (
        mocks["LIF"],
        mocks["Dense"],
        mocks["Monitor"],
        mocks["RunSteps"],
        mocks["Loihi2SimCfg"],
        mocks["RingBuffer"],
    )
    mocks["lif_instance"].run = MagicMock()
    mocks["lif_instance"].name = "lif"
    mocks["lif_instance"]._process_model = None
    spike_arr = np.zeros((50, 2), dtype=int)
    spike_arr[5, 0] = 1
    mocks["monitor_instance"].get_data.return_value = {
        "lif": {"s_out": spike_arr},
    }

    result = LavaSimulatorAdapter().run(
        _make_graph(), _make_stimulus(), timesteps=50, seed=1
    )

    assert isinstance(result.voltages, dict)
    assert result.voltages == {}


def test_extract_voltages_from_monitor_empty_raw() -> None:
    result = _extract_voltages_from_monitor({}, MagicMock(), "lif")
    assert result == {}


def test_extract_voltages_from_monitor_no_v_key() -> None:
    lif = MagicMock()
    lif.name = "lif"
    result = _extract_voltages_from_monitor(
        {"lif": {"s_out": np.zeros((10, 2))}}, lif, "lif"
    )
    assert result == {}


def test_extract_voltages_from_monitor_includes_all_traces() -> None:
    """All traces are now included regardless of their values —
    all-zero traces are valid data (neuron at rest)."""
    lif = MagicMock()
    lif.name = "lif"
    zeros = np.zeros((10, 2), dtype=float)
    result = _extract_voltages_from_monitor({"lif": {"v": zeros}}, lif, "lif")
    assert result == {"lif": {"0": [0.0] * 10, "1": [0.0] * 10}}


# ---------------------------------------------------------------------------
# LavaSimulatorAdapter — unexpected exceptions are wrapped
# ---------------------------------------------------------------------------


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator.LavaSimulatorAdapter._run_in_process")
def test_unexpected_exception_in_run_becomes_dispatch_error(
    mock_run: MagicMock, mock_avail: MagicMock
) -> None:
    """Any unexpected exception from _run_in_process must be wrapped in LavaDispatchError."""
    mock_run.side_effect = ValueError("something broke during setup")

    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter().run(
            _make_graph(), _make_stimulus(), timesteps=50, seed=1
        )

    assert exc_info.value.diagnostics
    assert any("something broke during setup" in d for d in exc_info.value.diagnostics)


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=False)
@patch("neurocnl.runtime.lava_simulator.LavaSimulatorAdapter._run_remote")
def test_unexpected_exception_in_remote_becomes_dispatch_error(
    mock_run: MagicMock, mock_avail: MagicMock
) -> None:
    """Any unexpected exception from _run_remote must be wrapped in LavaDispatchError."""
    mock_run.side_effect = TypeError("bad response from worker")

    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter().run(
            _make_graph(),
            _make_stimulus(),
            timesteps=50,
            seed=1,
            worker_url="http://fake-worker:8080",
        )

    assert exc_info.value.diagnostics
    assert any("bad response from worker" in d for d in exc_info.value.diagnostics)


# ---------------------------------------------------------------------------
# Affine support (Phase H — backs nir_support.py's lava_sim/Affine="approximate")
# ---------------------------------------------------------------------------


def _make_affine_graph(input_size: int = 2, output_size: int = 2) -> nir.NIRGraph:
    """A minimal NIR graph: Input -> Affine (zero bias) -> LIF -> Output."""
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type=np.array([input_size])),
            "affine": nir.Affine(
                weight=np.eye(output_size, input_size),
                bias=np.zeros(output_size),
            ),
            "lif": nir.LIF(
                tau=np.full(output_size, 0.02),
                r=np.ones(output_size),
                v_leak=np.zeros(output_size),
                v_threshold=np.ones(output_size),
            ),
            "output": nir.Output(output_type=np.array([output_size])),
        },
        edges=[("input", "affine"), ("affine", "lif"), ("lif", "output")],
    )


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator._import_lava")
def test_in_process_runs_affine_to_lif_graph(
    mock_import: MagicMock, mock_avail: MagicMock
) -> None:
    """Affine -> LIF graphs must be accepted by the lava_sim allow-list gate
    and dispatched, backing nir_support.py's lava_sim/Affine == 'approximate'
    verdict with real capability.
    """
    mocks = _make_mock_lava_classes()
    mock_import.return_value = (
        mocks["LIF"],
        mocks["Dense"],
        mocks["Monitor"],
        mocks["RunSteps"],
        mocks["Loihi2SimCfg"],
        mocks["RingBuffer"],
    )
    mocks["lif_instance"].run = MagicMock()

    result = LavaSimulatorAdapter().run(
        _make_affine_graph(), _make_stimulus(), timesteps=50, seed=1
    )

    assert isinstance(result, LavaSimulatorResult)
    assert result.runtime_mode == "in_process_lava_sim"


@patch("neurocnl.runtime.lava_simulator._is_lava_available", return_value=True)
@patch("neurocnl.runtime.lava_simulator._import_lava")
def test_in_process_affine_nonzero_bias_raises_dispatch_error(
    mock_import: MagicMock, mock_avail: MagicMock
) -> None:
    """Non-zero-bias Affine must surface as a clear LavaDispatchError, not a
    silent identity-matrix fallback.
    """
    mocks = _make_mock_lava_classes()
    mock_import.return_value = (
        mocks["LIF"],
        mocks["Dense"],
        mocks["Monitor"],
        mocks["RunSteps"],
        mocks["Loihi2SimCfg"],
        mocks["RingBuffer"],
    )
    graph = _make_affine_graph()
    graph.nodes["affine"] = nir.Affine(weight=np.eye(2), bias=np.array([0.5, 0.0]))

    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter().run(graph, _make_stimulus(), timesteps=50, seed=1)

    assert any("non-zero bias" in d for d in exc_info.value.diagnostics)
