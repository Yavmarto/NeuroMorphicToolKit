"""Unit tests for `neurocnl.training.dag_topology`.

Covers the shared Kahn's-algorithm topological sort (`topo_sort_nodes`) and
the setup/body node classification (`classify_phase`) extracted out of
`backend/app/routers/notebook.py` so both notebook codegen and future
live-execution code can share the same DAG-topology logic.
"""

from __future__ import annotations

import pytest

from neurocnl.training.dag_schema import DagEdgePayload, DagNodePayload
from neurocnl.training.dag_topology import CycleError, classify_phase, topo_sort_nodes


def _node(node_id: str, node_type: str = "dataLoader") -> DagNodePayload:
    return DagNodePayload(id=node_id, type=node_type, parameters={})


def _edge(edge_id: str, source: str, target: str) -> DagEdgePayload:
    return DagEdgePayload(
        id=edge_id,
        source_node_id=source,
        source_port="out",
        target_node_id=target,
        target_port="in",
    )


class TestTopoSortNodes:
    def test_linear_chain_orders_by_dependency(self) -> None:
        a, b, c = _node("a"), _node("b"), _node("c")
        edges = [_edge("e1", "a", "b"), _edge("e2", "b", "c")]
        result = topo_sort_nodes([c, a, b], edges)
        assert [n.id for n in result] == ["a", "b", "c"]

    def test_branching_dag_respects_all_dependencies(self) -> None:
        # a -> b, a -> c, b -> d, c -> d
        a, b, c, d = _node("a"), _node("b"), _node("c"), _node("d")
        edges = [
            _edge("e1", "a", "b"),
            _edge("e2", "a", "c"),
            _edge("e3", "b", "d"),
            _edge("e4", "c", "d"),
        ]
        result = topo_sort_nodes([a, b, c, d], edges)
        order = [n.id for n in result]
        assert order.index("a") < order.index("b")
        assert order.index("a") < order.index("c")
        assert order.index("b") < order.index("d")
        assert order.index("c") < order.index("d")
        assert set(order) == {"a", "b", "c", "d"}

    def test_disconnected_nodes_are_all_present(self) -> None:
        a, b = _node("a"), _node("b")
        result = topo_sort_nodes([a, b], [])
        assert {n.id for n in result} == {"a", "b"}

    def test_cycle_raises_cycle_error(self) -> None:
        a, b = _node("a"), _node("b")
        edges = [_edge("e1", "a", "b"), _edge("e2", "b", "a")]
        with pytest.raises(CycleError):
            topo_sort_nodes([a, b], edges)

    def test_cycle_error_is_a_value_error(self) -> None:
        a, b = _node("a"), _node("b")
        edges = [_edge("e1", "a", "b"), _edge("e2", "b", "a")]
        with pytest.raises(ValueError):
            topo_sort_nodes([a, b], edges)

    def test_cycle_error_message_identifies_offending_nodes(self) -> None:
        a, b = _node("a"), _node("b")
        edges = [_edge("e1", "a", "b"), _edge("e2", "b", "a")]
        with pytest.raises(CycleError) as exc_info:
            topo_sort_nodes([a, b], edges)
        message = str(exc_info.value)
        assert "a" in message
        assert "b" in message


class TestClassifyPhase:
    def test_splits_setup_and_body_nodes(self) -> None:
        loader = _node("loader", "dataLoader")
        optimiser = _node("opt", "adamOptimiser")
        scheduler = _node("sched", "stepLR")
        time_loop = _node("loop", "timeLoop")
        early_stop = _node("es", "earlyStopping")
        weight_clip = _node("clip", "weightClip")
        forward = _node("fwd", "forwardPass")
        loss = _node("loss", "mseCountLoss")

        result = classify_phase(
            [
                loader,
                optimiser,
                scheduler,
                time_loop,
                early_stop,
                weight_clip,
                forward,
                loss,
            ]
        )

        setup_ids = {n.id for n in result.setup_nodes}
        body_ids = {n.id for n in result.body_nodes}

        assert setup_ids == {"loader", "opt", "sched", "loop", "es"}
        assert body_ids == {"fwd", "loss"}
        # weightClip nodes belong to neither bucket — the caller (notebook
        # codegen) special-cases them for post-optimiser-step placement.
        assert "clip" not in setup_ids
        assert "clip" not in body_ids

    def test_empty_node_list_returns_empty_classification(self) -> None:
        result = classify_phase([])
        assert result.setup_nodes == []
        assert result.body_nodes == []
        assert result.post_training_nodes == []

    def test_exporters_run_after_training_not_per_batch(self) -> None:
        exporter = _node("export", "nirExporter")
        forward = _node("forward", "forwardPass")

        result = classify_phase([forward, exporter])

        assert result.body_nodes == [forward]
        assert result.post_training_nodes == [exporter]

    def test_akida_exporter_runs_after_training_not_per_batch(self) -> None:
        """Conversion is expensive and needs the finished weights.

        Left out of `post_training_types` it lands in the per-batch body, which
        would convert and evaluate the whole model once per minibatch.
        """
        exporter = _node("akida", "akidaExporter")
        forward = _node("forward", "forwardPass")

        result = classify_phase([forward, exporter])

        assert result.body_nodes == [forward]
        assert result.post_training_nodes == [exporter]

    def test_preserves_input_order_within_each_bucket(self) -> None:
        n1 = _node("n1", "dataLoader")
        n2 = _node("n2", "forwardPass")
        n3 = _node("n3", "adamOptimiser")
        n4 = _node("n4", "membraneLoss")

        result = classify_phase([n1, n2, n3, n4])

        assert [n.id for n in result.setup_nodes] == ["n1", "n3"]
        assert [n.id for n in result.body_nodes] == ["n2", "n4"]
