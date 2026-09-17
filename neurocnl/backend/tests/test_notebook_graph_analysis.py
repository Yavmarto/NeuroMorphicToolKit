"""Focused unit tests for backend.app.services.notebook_graph_analysis.

These exercise the graph-analysis service directly (flattening, ordering,
naming, width propagation, dataset-width validation, LIF diagnostics)
without going through the full /api/notebook/from-spec HTTP surface — the
HTTP-level scenarios for these same behaviors already live in
test_notebook_generate_v2.py and test_deploy_targets_and_preview.py.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from unittest.mock import patch

import nir
import numpy as np
import pytest

from backend.app.schemas.pipeline_dag import DagNodePayload, PhaseDAGPayload, PipelinePhasesPayload
from backend.app.services.notebook_graph_analysis import (
    GraphWidthMismatchError,
    check_input_width_against_datasets,
    flatten_and_classify,
    graph_needs_cnl_flatten,
    graph_weighted_node_names,
    implausible_lif_thresholds,
    node_order_key,
    ordered_graph_node_names,
    propagate_graph_widths,
)
from neurocnl.runtime.cnl_nodes import Leaky


def _empty_phases() -> PipelinePhasesPayload:
    return PipelinePhasesPayload(
        train=PhaseDAGPayload(nodes=[], edges=[]),
        eval=PhaseDAGPayload(nodes=[], edges=[]),
    )


# ── flattening decisions ─────────────────────────────────────────────────────


def test_graph_needs_cnl_flatten_true_for_flatten_target_with_cnl_node() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "leaky": Leaky(n_neurons=2),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "leaky"), ("leaky", "output")],
        type_check=False,
    )
    assert graph_needs_cnl_flatten(graph, "sinabs") is True


def test_graph_needs_cnl_flatten_false_for_non_flatten_target() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "leaky": Leaky(n_neurons=2),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "leaky"), ("leaky", "output")],
        type_check=False,
    )
    # lava is deliberately excluded from _CNL_FLATTEN_TARGETS.
    assert graph_needs_cnl_flatten(graph, "lava") is False


def test_flatten_and_classify_unknown_target_returns_no_classification() -> None:
    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "output")],
        type_check=False,
    )
    result_graph, classification, flattened = flatten_and_classify(graph, "not_a_real_target")
    assert result_graph is graph
    assert classification is None
    assert flattened is False


# ── ordering ─────────────────────────────────────────────────────────────────


def test_node_order_key_sorts_numeric_ids_naturally() -> None:
    names = ["10", "2", "1"]
    assert sorted(names, key=node_order_key) == ["1", "2", "10"]


def test_node_order_key_sorts_non_numeric_after_numeric() -> None:
    names = ["b", "1", "a"]
    assert sorted(names, key=node_order_key) == ["1", "a", "b"]


def test_ordered_graph_node_names_follows_topology() -> None:
    graph = nir.NIRGraph(
        nodes={
            "2": nir.Input(input_type={"input": np.array([2])}),
            "1": Leaky(n_neurons=2),
            "0": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("2", "1"), ("1", "0")],
        type_check=False,
    )
    assert ordered_graph_node_names(graph) == ["2", "1", "0"]


def test_ordered_graph_node_names_handles_cycle_without_dropping_nodes() -> None:
    graph = nir.NIRGraph(
        nodes={
            "a": nir.Input(input_type={"input": np.array([2])}),
            "b": Leaky(n_neurons=2),
            "c": Leaky(n_neurons=2),
        },
        edges=[("a", "b"), ("b", "c"), ("c", "b")],
        type_check=False,
    )
    ordered = ordered_graph_node_names(graph)
    assert set(ordered) == {"a", "b", "c"}
    assert len(ordered) == 3


def test_graph_weighted_node_names_orders_by_topology() -> None:
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([2])}),
            "lin2": nir.Linear(weight=np.ones((2, 2))),
            "lin1": nir.Linear(weight=np.ones((2, 2))),
            "out": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("in", "lin1"), ("lin1", "lin2"), ("lin2", "out")],
        type_check=False,
    )
    assert graph_weighted_node_names(graph) == ["lin1", "lin2"]


# ── width propagation ────────────────────────────────────────────────────────


def test_propagate_graph_widths_stops_at_spatial_node() -> None:
    """A Conv2d/unmodelled node ends width tracking rather than guessing."""
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([32])}),
            "conv": nir.Conv2d(
                input_shape=(10, 10),
                weight=np.ones((1, 1, 3, 3)),
                stride=1,
                padding=0,
                dilation=1,
                groups=1,
                bias=np.zeros(1),
            ),
            "lin": nir.Linear(weight=np.ones((16, 8))),
        },
        edges=[("in", "conv"), ("conv", "lin")],
        type_check=False,
    )
    conflicts = propagate_graph_widths(graph, {"in": 32})
    assert conflicts == []


def test_propagate_graph_widths_reports_mismatch_at_first_weighted_node() -> None:
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([32])}),
            "lin": nir.Linear(weight=np.ones((16, 8))),
        },
        edges=[("in", "lin")],
        type_check=False,
    )
    conflicts = propagate_graph_widths(graph, {"in": 32})
    assert conflicts == [("lin", 32, 8)]


# ── dataset-width validation ─────────────────────────────────────────────────


def _pt_loader_phases(dataset_path: str) -> PipelinePhasesPayload:
    return PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(
                    id="loader",
                    type="dataLoader",
                    parameters={"format": "pt", "dataset_path": dataset_path},
                )
            ],
            edges=[],
        ),
        eval=PhaseDAGPayload(nodes=[], edges=[]),
    )


def test_check_input_width_matching_dataset_passes(tmp_path: Path) -> None:
    dataset = tmp_path / "matches.pt"
    dataset.write_bytes(b"placeholder")
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([8])}),
            "out": nir.Output(output_type={"output": np.array([8])}),
        },
        edges=[("in", "out")],
        type_check=False,
    )
    with patch("backend.app.services.notebook_graph_analysis.pt_feature_width", return_value=8):
        check_input_width_against_datasets(graph, _pt_loader_phases(str(dataset)))


def test_check_input_width_mismatched_dataset_raises(tmp_path: Path) -> None:
    dataset = tmp_path / "mismatch.pt"
    dataset.write_bytes(b"placeholder")
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([32])}),
            "out": nir.Output(output_type={"output": np.array([32])}),
        },
        edges=[("in", "out")],
        type_check=False,
    )
    with (
        patch("backend.app.services.notebook_graph_analysis.pt_feature_width", return_value=784),
        pytest.raises(GraphWidthMismatchError) as exc_info,
    ):
        check_input_width_against_datasets(graph, _pt_loader_phases(str(dataset)))
    assert "784" in exc_info.value.detail
    assert "32" in exc_info.value.detail


def test_check_input_width_unreadable_dataset_is_silent(tmp_path: Path) -> None:
    dataset = tmp_path / "unreadable.pt"
    dataset.write_bytes(b"placeholder")
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([32])}),
            "out": nir.Output(output_type={"output": np.array([32])}),
        },
        edges=[("in", "out")],
        type_check=False,
    )
    with patch("backend.app.services.notebook_graph_analysis.pt_feature_width", return_value=None):
        check_input_width_against_datasets(graph, _pt_loader_phases(str(dataset)))


def test_check_input_width_multiple_inputs_skips_dataset_attribution() -> None:
    """With more than one Input port, the check falls back to declared widths only."""
    graph = nir.NIRGraph(
        nodes={
            "in1": nir.Input(input_type={"input": np.array([8])}),
            "in2": nir.Input(input_type={"input": np.array([8])}),
            "out": nir.Output(output_type={"output": np.array([8])}),
        },
        edges=[("in1", "out"), ("in2", "out")],
        type_check=False,
    )
    # No pt loader at all: nothing to attribute, nothing to check — must not raise.
    check_input_width_against_datasets(graph, _empty_phases())


# ── LIF-threshold diagnostics ────────────────────────────────────────────────


def test_implausible_lif_thresholds_flags_unreachable_threshold() -> None:
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([1])}),
            "lif": nir.LIF(
                tau=np.array([0.02]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([500.0]),
            ),
            "out": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("in", "lif"), ("lif", "out")],
        type_check=False,
    )
    warnings = implausible_lif_thresholds(graph)
    assert len(warnings) == 1
    assert "lif" in warnings[0]


def test_implausible_lif_thresholds_silent_for_plausible_threshold() -> None:
    graph = nir.NIRGraph(
        nodes={
            "in": nir.Input(input_type={"input": np.array([1])}),
            "lif": nir.LIF(
                tau=np.array([0.02]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([1.0]),
            ),
            "out": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("in", "lif"), ("lif", "out")],
        type_check=False,
        # A network timestep close to tau keeps the effective threshold near 1.0
        # (see resolve_dt) — without it the 1e-4s default makes even thr=1.0 flag.
        metadata={"dt": 0.02},
    )
    assert implausible_lif_thresholds(graph) == []


# ── compatibility aliases ────────────────────────────────────────────────────


def test_router_compatibility_aliases_are_the_service_functions() -> None:
    """The router's private names must be the exact same objects as the
    service's public ones — a one-release compatibility shim, not a copy
    that could silently drift.
    """
    import backend.app.routers.notebook as router_module
    import backend.app.services.notebook_graph_analysis as service_module

    assert router_module._flatten_and_classify is service_module.flatten_and_classify
    assert router_module._graph_weighted_node_names is service_module.graph_weighted_node_names
    assert router_module._python_identifier is service_module.python_identifier
    assert (
        router_module._check_input_width_against_datasets
        is service_module.check_input_width_against_datasets
    )


# ── golden notebook hashes ───────────────────────────────────────────────────
# Regression guard: moving graph-analysis code out of the router must not
# change one byte of generated notebook output. Each hash is the sha256 of
# json.dumps(nb, sort_keys=True) for a representative target family.


_GOLDEN_SPEC = "\n".join(
    [
        "Define a network named feedforward.",
        "Define an input port named input with shape (4,).",
        "Define a linear transformation named w_input_hidden with weight matrix shape (3, 4).",
        "Define a LIF neuron named hidden"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define a linear transformation named w_hidden_output with weight matrix shape (2, 3).",
        "Define a LIF neuron named output_layer"
        " with time constant 0.02, resistance 1.0, leak voltage 0.0,"
        " and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_input_hidden.",
        "w_input_hidden connects to hidden.",
        "hidden connects to w_hidden_output.",
        "w_hidden_output connects to output_layer.",
        "output_layer connects to output.",
    ]
)


def _notebook_hash(target_framework: str) -> str:
    from backend.app.routers.notebook import (
        PipelineConfigPayload,
        _build_v2_notebook,
        compile_to_nir,
    )

    graph = compile_to_nir(_GOLDEN_SPEC)
    nb, _ = _build_v2_notebook(
        _GOLDEN_SPEC,
        graph,
        PipelineConfigPayload(framework=target_framework),
        "2026-01-01 00:00 UTC",
        pipeline_phases=_empty_phases(),
    )
    return hashlib.sha256(json.dumps(nb, sort_keys=True).encode()).hexdigest()


@pytest.mark.parametrize(
    "target_framework, expected_hash",
    [
        # snnTorch: the direct-codegen (non-converter, non-flatten) target.
        ("snntorch_sim", "c9f0bf7acb1c7657583fe6dcd9db791cf0b5ac03569e53dacf21b890d41b1844"),
        # sinabs: a converter target that also needs cnl.* flattening.
        ("sinabs", "132ec3b655a95f3ba948232b711e66849b6e10c7b3f4cad7445a268aa99650e7"),
        # akida: a flattened-CNL target (member of CNL_FLATTEN_TARGETS).
        ("akida", "57bf7f4ea570600e6b13fd86f99ec08cb8ad765cef341f5cdb3f176a78f95088"),
        # rockpool: a generic converter target.
        ("rockpool", "710f45f9b03ad42054d66e308ace23dfdc9859785b1a609edc8b5fe708d0cdd8"),
    ],
)
def test_generated_notebook_hash_is_unchanged(target_framework: str, expected_hash: str) -> None:
    assert _notebook_hash(target_framework) == expected_hash
