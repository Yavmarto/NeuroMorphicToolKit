"""Tests for NIR integration: export and import of NIR graphs."""

import importlib
from pathlib import Path
from typing import Any, cast

import numpy as np

from neurosense.app.schemas.encoding import build_encoding_config
from neurosense.app.services.nir_service import nir_service

nir = cast(Any, importlib.import_module("nir"))


def test_encoding_config_to_nir_delta() -> None:
    """Verify delta encoding config is correctly mapped to NIR Threshold node."""
    config = build_encoding_config("delta", delta_threshold=15.0)
    graph = nir_service.encoding_config_to_nir(config)

    assert isinstance(graph, nir.NIRGraph)
    # Check for Threshold node
    threshold_nodes = [node for node in graph.nodes.values() if isinstance(node, nir.Threshold)]
    assert len(threshold_nodes) == 1
    assert threshold_nodes[0].threshold[0] == 15.0


def test_encoding_config_to_nir_rate() -> None:
    """Verify rate encoding config is correctly mapped to NIR Scale node."""
    config = build_encoding_config("rate", rate_max_hz=300.0)
    graph = nir_service.encoding_config_to_nir(config)

    assert isinstance(graph, nir.NIRGraph)
    # Check for Scale node
    scale_nodes = [node for node in graph.nodes.values() if isinstance(node, nir.Scale)]
    assert len(scale_nodes) == 1
    assert scale_nodes[0].scale[0] == 3.0  # 300.0 / 100.0


def test_nir_to_encoding_config_delta() -> None:
    """Verify NIR graph with Threshold is mapped back to delta encoding."""
    nodes = {
        "input": nir.Input(input_type={"input": np.array([1])}),
        "encoder": nir.Threshold(threshold=np.array([25.0])),
        "output": nir.Output(output_type={"output": np.array([1])}),
    }
    edges = [("input", "encoder"), ("encoder", "output")]
    graph = nir.NIRGraph(nodes=nodes, edges=edges)

    config = nir_service.nir_to_encoding_config(graph)
    assert config.method == "delta"
    assert config.delta_threshold == 25.0


def test_nir_to_encoding_config_rate() -> None:
    """Verify NIR graph with Scale is mapped back to rate encoding."""
    nodes = {
        "input": nir.Input(input_type={"input": np.array([1])}),
        "encoder": nir.Scale(scale=np.array([4.5])),
        "output": nir.Output(output_type={"output": np.array([1])}),
    }
    edges = [("input", "encoder"), ("encoder", "output")]
    graph = nir.NIRGraph(nodes=nodes, edges=edges)

    config = nir_service.nir_to_encoding_config(graph)
    assert config.method == "rate"
    assert config.rate_max_hz == 450.0


def test_nir_file_persistence(tmp_path: Path) -> None:
    """Verify writing and reading a NIR file."""
    config = build_encoding_config("delta", delta_threshold=10.0)
    graph = nir_service.encoding_config_to_nir(config)

    file_path = tmp_path / "test_model.nir"
    nir_service.write_nir(graph, str(file_path))

    assert file_path.exists()

    read_graph = nir_service.read_nir(str(file_path))
    assert isinstance(read_graph, nir.NIRGraph)
    assert len(read_graph.nodes) == len(graph.nodes)

    # Check mapped config from read graph
    read_config = nir_service.nir_to_encoding_config(read_graph)
    assert read_config.method == "delta"
    assert read_config.delta_threshold == 10.0
