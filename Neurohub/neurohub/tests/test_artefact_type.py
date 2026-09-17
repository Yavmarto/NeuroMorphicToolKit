"""Tests for ArtefactType enum members."""

from neurohub.app.utils.uri_parser import ArtefactType


def test_custom_node_artefact_type_exists():
    """The custom_node type must exist and round-trip through the enum."""
    assert ArtefactType.custom_node == "custom_node"
    assert ArtefactType("custom_node") is ArtefactType.custom_node


def test_benchmark_result_artefact_type_exists():
    """The benchmark_result type must exist and round-trip through the enum."""
    assert ArtefactType.benchmark_result == "benchmark_result"
    assert ArtefactType("benchmark_result") is ArtefactType.benchmark_result
