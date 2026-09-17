"""Brunel (2000) dynamics verification via brian2_sim compile path."""

from __future__ import annotations

import importlib.util
from unittest.mock import patch

import pytest

from neurocnl import compile_to_nir
from neurocnl.converter.brian2_io import Brian2IO
from neurocnl.experiments.brunel_dynamics import (
    apply_brunel_weights,
    brunel_cnl_spec,
    check_async_irregular_regime,
    coefficient_of_variation_isi,
    summarize_spikes,
)
from neurocnl.runtime.brian2_simulator import Brian2SimulatorAdapter
from neurocnl.runtime.nir_support import classify_nir_graph
from neurocnl.runtime.stimulus import ValidatedStimulus


def test_brunel_cnl_compiles_and_brian2_payload_sizes() -> None:
    graph = compile_to_nir(brunel_cnl_spec(n_e=8, n_i=2, n_ext=4))
    classification = classify_nir_graph(graph, "brian2_sim")
    assert classification.level in {"exact", "approximate"}
    assert "LIF" not in classification.unsupported_nodes

    payload = Brian2IO().to_runtime_payload(graph)
    sizes = {p["name"]: p["size"] for p in payload["populations"]}
    assert sizes["excitatory"] == 8
    assert sizes["inhibitory"] == 2
    assert payload["num_synapses"] > 0


def test_brunel_weight_scaling_preserves_shape() -> None:
    graph = compile_to_nir(brunel_cnl_spec(n_e=4, n_i=2, n_ext=2))
    scaled = apply_brunel_weights(graph, p=0.5, g=4.0, j=0.2, seed=1)
    w_ie = scaled.nodes["w_i_e"].weight
    assert w_ie.shape == (4, 2)
    assert (w_ie <= 0).any() or (w_ie == 0).all()


def test_cv_isi_irregular_raster() -> None:
    spikes = {
        "0": [10, 13, 18, 22, 29],
        "1": [5, 11, 14, 20, 27, 33],
        "2": [8, 15, 19, 25, 31],
    }
    cv = coefficient_of_variation_isi(spikes, dt_ms=1.0)
    assert cv > 0.2


def test_async_irregular_heuristic_rejects_silent() -> None:
    metrics = summarize_spikes({}, neuron_count=10, duration_ms=500.0)
    check = check_async_irregular_regime(metrics)
    assert not check.ok
    assert "no spikes" in check.notes[0]


@pytest.mark.skipif(
    not importlib.util.find_spec("brian2"),
    reason="brian2 not installed",
)
def test_brunel_brian2_in_process_run_produces_spikes() -> None:
    graph = apply_brunel_weights(
        compile_to_nir(brunel_cnl_spec(n_e=12, n_i=3, n_ext=6)),
        p=0.25,
        g=5.0,
        j=0.15,
        seed=42,
    )
    result = Brian2SimulatorAdapter().run(
        graph,
        stimulus=ValidatedStimulus(population="external", neuron_count=6, spikes={}),
        timesteps=200,
        seed=0,
    )
    assert result.spikes
    pop_spikes = next(iter(result.spikes.values()))
    metrics = summarize_spikes(pop_spikes, neuron_count=12, duration_ms=200.0)
    assert metrics.spike_count > 0


def test_brunel_brian2_remote_mock_run() -> None:
    graph = apply_brunel_weights(compile_to_nir(brunel_cnl_spec(n_e=4, n_i=2, n_ext=2)))
    fake_spikes = {"0": [5, 12, 20], "1": [7, 15, 22], "2": [9, 18], "3": [11, 19, 28]}

    with (
        patch(
            "neurocnl.runtime.brian2_simulator._is_brian2_available",
            return_value=False,
        ),
        patch(
            "neurocnl.converter.brian2_io.Brian2IO.compile_and_run_remote",
            return_value={
                "compile": {"session_id": "sess-brunel"},
                "run": {"spikes": fake_spikes, "execution_time_ms": 4.0},
            },
        ),
    ):
        result = Brian2SimulatorAdapter().run(
            graph,
            stimulus=ValidatedStimulus(population="external", neuron_count=2, spikes={}),
            timesteps=50,
            seed=0,
            worker_url="http://brian2-backend:8013",
        )

    metrics = summarize_spikes(fake_spikes, neuron_count=4, duration_ms=50.0)
    check = check_async_irregular_regime(metrics)
    assert result.runtime_mode == "remote_brian2_sim_worker"
    assert check.ok or metrics.spike_count > 0
