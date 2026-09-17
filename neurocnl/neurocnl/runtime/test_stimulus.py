"""Tests for neurocnl.runtime.stimulus — spike-train stimulus helpers."""

from __future__ import annotations

import nir
import numpy as np
import pytest

from neurocnl.runtime.stimulus import (
    StimulusError,
    ValidatedStimulus,
    generate_default_stimulus,
    parse_stimulus,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_simple_graph(input_size: int = 2, output_size: int = 2) -> nir.NIRGraph:
    input_node = nir.Input(input_type=np.array([input_size]))
    lif = nir.LIF(
        tau=np.array([0.02] * output_size),
        r=np.array([1.0] * output_size),
        v_leak=np.array([0.0] * output_size),
        v_threshold=np.array([1.0] * output_size),
    )
    output_node = nir.Output(output_type=np.array([output_size]))
    weight = nir.Linear(weight=np.ones((output_size, input_size)))
    return nir.NIRGraph(
        nodes={
            "input": input_node,
            "weight": weight,
            "lif": lif,
            "output": output_node,
        },
        edges=[("input", "weight"), ("weight", "lif"), ("lif", "output")],
    )


# ---------------------------------------------------------------------------
# generate_default_stimulus
# ---------------------------------------------------------------------------


def test_default_stimulus_is_deterministic() -> None:
    """Same seed + timesteps must produce identical spike trains."""
    graph = _make_simple_graph()
    stim1 = generate_default_stimulus(graph, timesteps=100, seed=42)
    stim2 = generate_default_stimulus(graph, timesteps=100, seed=42)
    assert stim1.spikes == stim2.spikes


def test_default_stimulus_changes_with_seed() -> None:
    graph = _make_simple_graph()
    stim1 = generate_default_stimulus(graph, timesteps=200, seed=1)
    stim2 = generate_default_stimulus(graph, timesteps=200, seed=999)
    # With 200 timesteps it's very unlikely both seeds produce identical trains
    assert stim1.spikes != stim2.spikes


def test_default_stimulus_targets_first_input_node() -> None:
    graph = _make_simple_graph()
    stim = generate_default_stimulus(graph, timesteps=100, seed=0)
    assert isinstance(stim, ValidatedStimulus)
    assert stim.population == "input"
    assert stim.neuron_count == 2


def test_default_stimulus_spike_times_in_range() -> None:
    graph = _make_simple_graph()
    stim = generate_default_stimulus(graph, timesteps=50, seed=1)
    for ts_list in stim.spikes.values():
        for t in ts_list:
            assert 0 <= t < 50, f"Spike time {t} out of [0, 50)"


def test_default_stimulus_no_input_nodes_raises() -> None:
    # An empty graph has no Input nodes.
    # (A graph with only Output nodes is avoided here because NIR normalises it
    # by automatically adding boundary Input nodes — an empty graph is the safe
    # way to exercise the "no inputs" error path.)
    graph = nir.NIRGraph(nodes={}, edges=[])
    with pytest.raises(StimulusError, match="no nir.Input"):
        generate_default_stimulus(graph, timesteps=10, seed=0)


# ---------------------------------------------------------------------------
# parse_stimulus
# ---------------------------------------------------------------------------


def test_parse_stimulus_valid() -> None:
    graph = _make_simple_graph()
    spec: dict[str, object] = {
        "type": "spike_train",
        "population": "input",
        "spikes": {"0": [0, 10, 20], "1": [5, 15]},
    }
    stim = parse_stimulus(spec, graph)
    assert isinstance(stim, ValidatedStimulus)
    assert stim.population == "input"
    assert stim.spikes[0] == [0, 10, 20]
    assert stim.spikes[1] == [5, 15]


def test_parse_stimulus_invalid_population_raises() -> None:
    graph = _make_simple_graph()
    spec: dict[str, object] = {
        "type": "spike_train",
        "population": "does_not_exist",
        "spikes": {"0": [1, 2]},
    }
    with pytest.raises(StimulusError) as exc_info:
        parse_stimulus(spec, graph)
    assert any("does_not_exist" in msg for msg in exc_info.value.diagnostics)


def test_parse_stimulus_out_of_range_neuron_raises() -> None:
    graph = _make_simple_graph(input_size=2)
    spec: dict[str, object] = {
        "type": "spike_train",
        "population": "input",
        "spikes": {"99": [1, 2]},  # neuron 99 does not exist in a 2-neuron population
    }
    with pytest.raises(StimulusError) as exc_info:
        parse_stimulus(spec, graph)
    assert any("out of range" in msg for msg in exc_info.value.diagnostics)


def test_parse_stimulus_negative_neuron_index_raises() -> None:
    graph = _make_simple_graph(input_size=3)
    spec: dict[str, object] = {
        "type": "spike_train",
        "population": "input",
        "spikes": {"-1": [1, 2]},
    }
    with pytest.raises(StimulusError):
        parse_stimulus(spec, graph)


def test_parse_stimulus_empty_spikes_accepted() -> None:
    graph = _make_simple_graph()
    spec: dict[str, object] = {
        "type": "spike_train",
        "population": "input",
        "spikes": {},
    }
    stim = parse_stimulus(spec, graph)
    assert stim.spikes == {}


def test_parse_stimulus_spike_times_sorted() -> None:
    graph = _make_simple_graph()
    spec: dict[str, object] = {
        "type": "spike_train",
        "population": "input",
        "spikes": {"0": [20, 5, 10]},  # unsorted input
    }
    stim = parse_stimulus(spec, graph)
    assert stim.spikes[0] == [5, 10, 20]


def test_parse_stimulus_missing_population_key_raises() -> None:
    graph = _make_simple_graph()
    spec: dict[str, object] = {"type": "spike_train", "spikes": {"0": [1]}}
    with pytest.raises(StimulusError):
        parse_stimulus(spec, graph)
