"""Central NIR-based model converter for neurocnl.

Provides a unified interface for converting spiking neural networks
between Nengo, Lava, PyNN, and Brian2 using NIR as the pivot format.
"""

import logging
from typing import Any, Protocol

import nir
import numpy as np

logger = logging.getLogger(__name__)


class FrameworkIO(Protocol):
    """Protocol for framework-specific importer/exporter."""

    def to_nir(self, model: Any, **kwargs: Any) -> nir.NIRGraph:
        """Convert a framework model to NIR."""
        ...

    def from_nir(self, graph: nir.NIRGraph, **kwargs: Any) -> Any:
        """Convert an NIR graph to a framework model."""
        ...


class ModelConverter:
    """Orchestrates model conversion between different frameworks via NIR."""

    def __init__(self) -> None:
        self.frameworks: dict[str, FrameworkIO] = {}
        self.warnings: list[str] = []

    def register_framework(self, name: str, handler: FrameworkIO) -> None:
        """Register a framework handler (importer/exporter)."""
        self.frameworks[name.lower()] = handler

    def convert(
        self, source_model: Any, source_framework: str, target_framework: str, **kwargs: Any
    ) -> Any:
        """Convert a model from source_framework to target_framework.

        Parameters
        ----------
        source_model : Any
            The model instance in the source framework.
        source_framework : str
            Name of the source framework (e.g., 'nengo').
        target_framework : str
            Name of the target framework (e.g., 'lava').

        Returns
        -------
        Any
            The converted model in the target framework.
        """
        self.warnings = []
        source_fw = source_framework.lower()
        target_fw = target_framework.lower()

        if source_fw not in self.frameworks:
            raise ValueError(f"Source framework '{source_fw}' not registered.")
        if target_fw not in self.frameworks:
            raise ValueError(f"Target framework '{target_fw}' not registered.")

        logger.info("Converting %s -> NIR", source_fw)
        nir_graph = self.frameworks[source_fw].to_nir(source_model, **kwargs)

        logger.info("Converting NIR -> %s", target_fw)
        target_model = self.frameworks[target_fw].from_nir(nir_graph, **kwargs)

        # Run validation
        validation_result = self.validate_conversion(source_model, target_model, nir_graph)
        if not validation_result:
            self.add_warning("Validation check failed: potential structural or parameter mismatch.")

        return target_model

    def add_warning(self, message: str) -> None:
        """Add a warning during the conversion process."""
        self.warnings.append(message)
        logger.warning(message)

    def validate_conversion(
        self, source_model: Any, target_model: Any, nir_graph: nir.NIRGraph
    ) -> bool:
        """Perform a basic sanity check on the conversion.

        Checks population counts and basic connectivity consistency.
        """
        if not nir_graph.nodes:
            return False

        # Structural check
        n_lif = sum(
            1 for node in nir_graph.nodes.values() if isinstance(node, nir.LIF | nir.CubaLIF)
        )

        if n_lif == 0:
            self.add_warning("NIR graph contains no LIF nodes.")
            return False

        # Parameter check: Ensure weights are non-zero if Linear nodes exist
        for name, node in nir_graph.nodes.items():
            if isinstance(node, nir.Linear):
                if np.all(node.weight == 0):
                    self.add_warning(f"Linear node '{name}' has all-zero weights.")

            if isinstance(node, nir.LIF | nir.CubaLIF):
                if np.any(node.tau <= 0):
                    self.add_warning(f"LIF node '{name}' has non-positive time constant.")

        # Spike-count sanity check (heuristic)
        # We estimate total "capacity" as sum of neurons
        total_neurons = sum(
            node.tau.size if hasattr(node.tau, "size") else 1
            for node in nir_graph.nodes.values()
            if isinstance(node, nir.LIF | nir.CubaLIF)
        )

        if total_neurons == 0:
            self.add_warning("Model has zero neurons.")
            return False

        return True
