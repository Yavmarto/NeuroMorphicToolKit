"""Notebook transport contracts are independent from generation internals."""

from backend.app.routers import notebook as notebook_router
from backend.app.schemas.notebook import (
    GenerateV2Request,
    PipelineCnlRequest,
    PipelineConfigPayload,
)
from backend.app.schemas.pipeline_dag import DagNodePayload
import pytest


def test_router_keeps_one_release_compatibility_reexports() -> None:
    assert notebook_router.GenerateV2Request is GenerateV2Request
    assert notebook_router.PipelineConfigPayload is PipelineConfigPayload


def test_nested_defaults_are_not_shared_between_requests() -> None:
    first = GenerateV2Request(spec="A")
    second = GenerateV2Request(spec="B")

    first.pipeline_config.eval_metrics.append("latency")
    first.pipeline_phases.train.nodes.append(DagNodePayload(id="node-a", type="dataLoader"))

    assert second.pipeline_config.eval_metrics == ["accuracy", "loss"]
    assert second.pipeline_phases.train.nodes == []
    assert PipelineCnlRequest().pipeline_config is not PipelineCnlRequest().pipeline_config


def test_unknown_pipeline_node_fails_instead_of_emitting_placeholder_code() -> None:
    node = DagNodePayload(id="future-node", type="notRegistered")

    with pytest.raises(ValueError, match="no notebook emitter is registered"):
        notebook_router._dag_node_code(node, PipelineConfigPayload(), "")
