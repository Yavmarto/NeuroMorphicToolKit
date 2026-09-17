"""
NIR (Neuromorphic Intermediate Representation) integration service.
Handles conversion between NeuroSense EncodingConfig and NIR graphs.
"""

from __future__ import annotations

import importlib
import io
from pathlib import Path
from typing import Any, cast

import numpy as np

from ..schemas.encoding import EncodingConfig, build_encoding_config


def _load_nir() -> Any:
    """Load NIR lazily so type checking does not depend on external stubs."""
    return cast(Any, importlib.import_module("nir"))


class NIRService:
    """Service for NIR model export and import."""

    def encoding_config_to_nir(self, config: EncodingConfig) -> Any:
        """Convert an EncodingConfig into a NIR Graph.

        The NIR graph represents the spike encoding operation as NIR nodes.
        """
        nir = _load_nir()
        nodes: dict[str, Any] = {}
        edges: list[tuple[str, str]] = []

        # All graphs start with an Input node
        nodes["input"] = nir.Input(input_type={"input": np.array([1])})

        if config.method == "delta":
            # Delta modulation is conceptually similar to a threshold operation
            threshold = config.delta_threshold or 10.0
            nodes["encoder"] = nir.Threshold(threshold=np.array([threshold]))
            edges.append(("input", "encoder"))
            last_node = "encoder"
        elif config.method == "rate":
            # Rate encoding can be seen as a Scale operation (signal -> rate)
            # followed by an IF (integrator) if we want to model the accumulation.
            # For simplicity, we'll represent it as a Scale node here.
            scale = (config.rate_max_hz or 200.0) / 100.0  # arbitrary normalization
            nodes["encoder"] = nir.Scale(scale=np.array([scale]))
            edges.append(("input", "encoder"))
            last_node = "encoder"
        else:
            # Fallback for other methods or temporal encoding
            nodes["encoder"] = nir.Delay(delay=np.array([1.0]))
            edges.append(("input", "encoder"))
            last_node = "encoder"

        # All graphs end with an Output node
        nodes["output"] = nir.Output(output_type={"output": np.array([1])})
        edges.append((last_node, "output"))

        return nir.NIRGraph(nodes=nodes, edges=edges)

    def nir_to_encoding_config(self, graph: Any) -> EncodingConfig:
        """Convert a NIR Graph back into an EncodingConfig if possible.

        This looks for specific node types to infer the encoding method.
        """
        nir = _load_nir()
        # Look for a Threshold node for Delta encoding
        for _name, node in graph.nodes.items():
            if isinstance(node, nir.Threshold):
                threshold_val = (
                    float(node.threshold[0])
                    if hasattr(node.threshold, "__getitem__")
                    else float(node.threshold)
                )
                return build_encoding_config("delta", delta_threshold=threshold_val)

        # Look for a Scale node for Rate encoding
        for _name, node in graph.nodes.items():
            if isinstance(node, nir.Scale):
                scale_val = (
                    float(node.scale[0])
                    if hasattr(node.scale, "__getitem__")
                    else float(node.scale)
                )
                return build_encoding_config("rate", rate_max_hz=scale_val * 100.0)

        # Default fallback
        return build_encoding_config("rate", rate_max_hz=200.0)

    def write_nir(self, graph: Any, filepath: Path | str | io.IOBase) -> None:
        """Write a NIR graph to a file."""
        nir = _load_nir()
        nir.write(filepath, graph)

    def read_nir(self, filepath: Path | str) -> Any:
        """Read a NIR graph from a file."""
        nir = _load_nir()
        return nir.read(filepath)


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
nir_service = NIRService()
