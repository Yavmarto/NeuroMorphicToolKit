"""Materialize semantic IR into a quantitative NIR graph."""

from __future__ import annotations

import re
from typing import Any

import nir
import numpy as np

from neurocnl.ir.connection_lowering import (
    MaterializerError,
    effective_connection_delay,
    synthesise_weight,
    validate_connection_shapes,
)
from neurocnl.ir.graph_metadata import compact_metadata as _compact_metadata
from neurocnl.ir.graph_metadata import (
    connection_metadata,
    delay_metadata,
    population_metadata,
    serialise_learning_rule,
    serialise_metadata_rule_list,
    serialise_neuromodulation_rules,
    serialise_timing_declaration,
)
from neurocnl.ir.lowering_summary import NirLoweringSummary, summarize_network_lowering
from neurocnl.ir.metadata_schema import advisory_graph_semantics
from neurocnl.ir.timing_validator import (
    TimingValidationError,
    validate_timing_declarations,
)
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR

__all__ = ["MaterializerError", "Materializer", "NirLoweringSummary", "sanitize_label"]

DEFAULT_POPULATION_SIZE = 1
DEFAULT_MEMBRANE_TIME_CONSTANT = 0.02
DEFAULT_THRESHOLD = 1.0
DEFAULT_RESET = 0.0
DEFAULT_LEAK = 0.0
DEFAULT_RESISTANCE = 1.0


def sanitize_label(label: str) -> str:
    """Sanitize an IR identifier for NIR node naming."""
    if not label:
        return ""
    return re.sub(r"[^a-zA-Z0-9_]", "_", label)


class Materializer:
    """Convert a semantic ``NetworkIR`` into a tensor-backed ``nir.NIRGraph``."""

    def __init__(self, default_population_size: int = DEFAULT_POPULATION_SIZE) -> None:
        self.default_population_size = default_population_size

    def materialize(self, network: NetworkIR) -> nir.NIRGraph:
        """Materialize the provided ``NetworkIR`` into a ``nir.NIRGraph``."""
        try:
            validate_timing_declarations(network)
        except TimingValidationError as exc:
            raise MaterializerError(str(exc)) from exc
        dimensions = {
            name: self._infer_population_dimension(population)
            for name, population in network.populations.items()
        }
        population_shapes = {
            name: list(population.shape)
            for name, population in network.populations.items()
            if population.shape is not None
        }
        node_labels = {
            name: sanitize_label(name) or f"population_{index}"
            for index, name in enumerate(network.populations)
        }

        nodes: dict[str, Any] = {}
        edges: list[tuple[str, str]] = []

        for name, population in network.populations.items():
            label = node_labels[name]
            size = dimensions[name]
            nodes[label] = self._materialize_population_node(population, size)

        for index, connection in enumerate(network.connections):
            source_label = node_labels.get(connection.source)
            target_label = node_labels.get(connection.target)
            if source_label is None or target_label is None:
                raise MaterializerError(
                    f"Connection references unknown populations: "
                    f"{connection.source!r} -> {connection.target!r}."
                )

            weight_label = self._connection_label(connection, index)
            source_size = dimensions[connection.source]
            target_size = dimensions[connection.target]
            validate_connection_shapes(
                network=network,
                connection=connection,
                source_size=source_size,
                target_size=target_size,
            )
            nodes[weight_label] = nir.Linear(
                weight=synthesise_weight(network, connection, source_size, target_size),
                metadata=connection_metadata(
                    network,
                    connection,
                    source_size=source_size,
                    target_size=target_size,
                ),
            )
            edges.append((source_label, weight_label))
            effective_delay = effective_connection_delay(network, connection)
            if effective_delay is not None:
                delay_label = self._delay_label(connection, index)
                nodes[delay_label] = nir.Delay(
                    delay=np.full(target_size, effective_delay, dtype=float),
                    metadata=delay_metadata(network, connection, effective_delay),
                )
                edges.append((weight_label, delay_label))
                edges.append((delay_label, target_label))
            else:
                edges.append((weight_label, target_label))

        self._add_entry_inputs_for_source_populations(
            network=network,
            dimensions=dimensions,
            node_labels=node_labels,
            nodes=nodes,
            edges=edges,
        )
        self._add_exit_outputs_for_closed_graphs(
            network=network,
            dimensions=dimensions,
            node_labels=node_labels,
            nodes=nodes,
            edges=edges,
        )

        timing_declarations = [
            serialise_timing_declaration(declaration)
            for declaration in network.timing_declarations
        ]
        unscoped_learning_rules = [
            serialise_learning_rule(rule)
            for rule in network.learning_rules
            if rule.source is None or rule.target is None
        ]
        neuromodulation_rules = serialise_neuromodulation_rules(
            network.metadata.get("neuromodulation_rules", [])
        )
        short_term_plasticity_rules = serialise_metadata_rule_list(
            network.metadata.get("short_term_plasticity_rules", [])
        )

        return nir.NIRGraph(
            nodes=nodes,
            edges=edges,
            metadata=_compact_metadata(
                {
                    "source": "neurocnl.ir.materializer",
                    "population_dimensions": dimensions,
                    "population_shapes": population_shapes,
                    "dt": network.metadata.get("dt"),
                    "nir_lowering_summary": self.summarize_lowering(
                        network
                    ).to_metadata(),
                    "global_receptor_dynamics": network.metadata.get(
                        "global_receptor_dynamics"
                    ),
                    "timing_declarations": timing_declarations,
                    "unscoped_learning_rules": unscoped_learning_rules,
                    "neuromodulation_rules": neuromodulation_rules,
                    "short_term_plasticity_rules": short_term_plasticity_rules,
                    "advisory_semantics": advisory_graph_semantics(
                        timing_declarations=timing_declarations,
                        global_receptor_dynamics=network.metadata.get(
                            "global_receptor_dynamics"
                        ),
                        unscoped_learning_rules=unscoped_learning_rules,
                        population_shapes=population_shapes,
                        neuromodulation_rules=neuromodulation_rules,
                        short_term_plasticity_rules=short_term_plasticity_rules,
                    ),
                }
            ),
        )

    def summarize_lowering(self, network: NetworkIR) -> NirLoweringSummary:
        """Summarize which IR semantics become executable, advisory, or approximate in NIR."""
        return summarize_network_lowering(
            network, default_population_size=self.default_population_size
        )

    def _infer_population_dimension(self, population: PopulationIR) -> int:
        if population.shape is not None:
            flattened_size = 1
            for axis in population.shape:
                flattened_size *= axis
            if population.size is not None and population.size != flattened_size:
                raise MaterializerError(
                    f"Population {population.name!r} size {population.size} does not match "
                    f"shape product {flattened_size}."
                )
            return flattened_size
        if population.size is not None and population.size > 0:
            return population.size
        if population.dimensions is not None and population.dimensions > 0:
            return population.dimensions
        return self.default_population_size

    def _materialize_population_node(self, population: PopulationIR, size: int) -> Any:
        metadata = population_metadata(population)
        if population.role == "input":
            return nir.Input(input_type={"input": np.array([size])}, metadata=metadata)
        if population.role == "output":
            return nir.Output(
                output_type={"output": np.array([size])}, metadata=metadata
            )

        tau_scalar = (
            population.membrane_time_constant
            if population.membrane_time_constant is not None
            else DEFAULT_MEMBRANE_TIME_CONSTANT
        )
        tau = self._expand_scalar(
            population.membrane_time_constant,
            size,
            default=DEFAULT_MEMBRANE_TIME_CONSTANT,
        )
        resistance = self._expand_scalar(None, size, default=DEFAULT_RESISTANCE)
        leak = self._expand_scalar(None, size, default=DEFAULT_LEAK)
        reset = self._expand_scalar(None, size, default=DEFAULT_RESET)

        homeostatic_rate = population.attributes.get("homeostatic_target_rate_hz")
        if isinstance(homeostatic_rate, int | float):
            adjusted_threshold = float(homeostatic_rate) * tau_scalar
            threshold = np.full(size, adjusted_threshold)
            metadata["homeostatic_target_rate_hz"] = homeostatic_rate
            metadata["default_v_threshold"] = float(DEFAULT_THRESHOLD)
        else:
            threshold = self._expand_scalar(
                population.threshold, size, default=DEFAULT_THRESHOLD
            )

        if population.refractory_period is not None:
            metadata["refractory_period"] = population.refractory_period

        return nir.LIF(
            tau=tau,
            r=resistance,
            v_leak=leak,
            v_threshold=threshold,
            v_reset=reset,
            metadata=metadata,
        )

    def _add_entry_inputs_for_source_populations(
        self,
        *,
        network: NetworkIR,
        dimensions: dict[str, int],
        node_labels: dict[str, str],
        nodes: dict[str, Any],
        edges: list[tuple[str, str]],
    ) -> None:
        for name, population in network.populations.items():
            if population.role == "input":
                continue
            has_external_source = any(
                connection.target == name and connection.source != name
                for connection in network.connections
            )
            if has_external_source:
                continue

            label = node_labels[name]
            input_label = self._unique_node_label(f"input_{label}", nodes)
            nodes[input_label] = nir.Input(
                input_type={"input": np.array([dimensions[name]])}
            )
            edges.append((input_label, label))

    def _unique_node_label(self, candidate: str, nodes: dict[str, Any]) -> str:
        if candidate not in nodes:
            return candidate
        index = 1
        while f"{candidate}_{index}" in nodes:
            index += 1
        return f"{candidate}_{index}"

    def _add_exit_outputs_for_closed_graphs(
        self,
        *,
        network: NetworkIR,
        dimensions: dict[str, int],
        node_labels: dict[str, str],
        nodes: dict[str, Any],
        edges: list[tuple[str, str]],
    ) -> None:
        leaf_nodes = set(nodes) - {source for source, _target in edges}
        if leaf_nodes:
            return

        for name, population in network.populations.items():
            if population.role == "output":
                continue
            label = node_labels[name]
            output_label = self._unique_node_label(f"output_{label}", nodes)
            nodes[output_label] = nir.Output(
                output_type={"output": np.array([dimensions[name]])}
            )
            edges.append((label, output_label))

    def _expand_scalar(
        self, value: float | None, size: int, *, default: float
    ) -> np.ndarray[Any, Any]:
        return np.full(size, default if value is None else value, dtype=float)

    def _connection_label(self, connection: ConnectionIR, index: int) -> str:
        source = sanitize_label(connection.source) or "source"
        target = sanitize_label(connection.target) or "target"
        return f"weight_{source}_to_{target}_{index}"

    def _delay_label(self, connection: ConnectionIR, index: int) -> str:
        source = sanitize_label(connection.source) or "source"
        target = sanitize_label(connection.target) or "target"
        return f"delay_{source}_to_{target}_{index}"
