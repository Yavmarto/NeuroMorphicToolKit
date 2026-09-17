"""Dataclass-based intermediate representation for normalized CNL semantics."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Literal

import numpy as np


def normalize_identifier(value: str) -> str:
    """Normalize a user-facing label into a stable IR identifier."""
    return " ".join(value.strip().lower().split())


PORT_POPULATION_TYPES = frozenset({"input", "output"})
"""``PopulationIR.population_type`` values marking declared I/O port
boundaries. NIR-native lowering represents input/output ports as
``PopulationIR`` entries so they can be named/connected like populations, but
they carry no neuron model and are not real hardware neuron populations —
backend planners and exporters must exclude them from neuron-model checks and
population/connection topology limits."""


@dataclass(slots=True)
class SourceProvenance:
    """Original source location for a lowered IR node."""

    line: int | None = None
    raw: str | None = None
    concept: str | None = None


@dataclass(slots=True)
class TimingDeclarationIR:
    """Generic timing declaration for future pipeline stages."""

    kind: str
    value: float | None = None
    unit: str | None = None
    provenance: list[SourceProvenance] = field(default_factory=list)
    attributes: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.kind = normalize_identifier(self.kind).replace(" ", "_")


@dataclass(slots=True)
class BackendHintIR:
    """Generic backend hint for future planning stages."""

    backend: str | None = None
    note: str | None = None
    provenance: list[SourceProvenance] = field(default_factory=list)
    attributes: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.backend is not None:
            self.backend = normalize_identifier(self.backend)


@dataclass(slots=True)
class PopulationIR:
    """Normalized population-level semantics."""

    name: str
    size: int | None = None
    dimensions: int | None = None
    shape: tuple[int, ...] | None = None
    role: str | None = None
    population_type: str | None = None
    threshold: float | None = None
    refractory_period: float | None = None
    membrane_time_constant: float | None = None
    provenance: list[SourceProvenance] = field(default_factory=list)
    attributes: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.name = normalize_identifier(self.name)
        if self.shape is not None:
            self.shape = tuple(int(axis) for axis in self.shape)
            if not self.shape or any(axis <= 0 for axis in self.shape):
                raise ValueError("Population shape must contain only positive axes.")
            flattened_size = 1
            for axis in self.shape:
                flattened_size *= axis
            if self.size is not None and self.size != flattened_size:
                raise ValueError(
                    f"Population size {self.size} does not match shape product {flattened_size}."
                )
        if self.role is not None:
            self.role = normalize_identifier(self.role)
            if self.role in {"sensory", "input"}:
                self.role = "input"
            elif self.role in {"motor", "output"}:
                self.role = "output"
        if self.population_type is not None:
            self.population_type = normalize_identifier(self.population_type)


@dataclass(slots=True)
class ConnectionIR:
    """Normalized connection semantics between populations."""

    source: str
    target: str
    weight: float | list[float] | list[list[float]] | np.ndarray[Any, Any] | None = None
    delay: float | None = None
    polarity: str | None = None
    connectivity_pattern: str | None = None
    connectivity_mask: tuple[tuple[int, ...], ...] | None = None
    locality_radius: float | None = None
    connection_density: float | None = None
    provenance: list[SourceProvenance] = field(default_factory=list)
    attributes: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.source = normalize_identifier(self.source)
        self.target = normalize_identifier(self.target)
        if self.weight is not None and not isinstance(self.weight, int | float):
            weight_array = np.asarray(self.weight, dtype=float)
            if weight_array.ndim == 0:
                self.weight = float(weight_array.item())
            elif weight_array.ndim in {1, 2}:
                self.weight = weight_array
            else:
                raise ValueError("Connection weight must be scalar, vector, or matrix shaped.")
        if self.polarity is not None:
            self.polarity = normalize_identifier(self.polarity)
        if self.connectivity_pattern is not None:
            self.connectivity_pattern = normalize_identifier(self.connectivity_pattern).replace(
                " ", "_"
            )
        if self.connectivity_mask is not None:
            mask = np.asarray(self.connectivity_mask, dtype=int)
            if mask.ndim != 2 or mask.size == 0:
                raise ValueError("Connectivity mask must be a non-empty 2D binary matrix.")
            if np.any((mask != 0) & (mask != 1)):
                raise ValueError("Connectivity mask must contain only binary 0/1 values.")
            self.connectivity_mask = tuple(tuple(int(value) for value in row) for row in mask)
            if self.connectivity_pattern is None:
                self.connectivity_pattern = "binary_mask"
        if self.locality_radius is not None:
            self.locality_radius = float(self.locality_radius)
            if self.locality_radius <= 0:
                raise ValueError("Locality radius must be positive.")
            if self.connectivity_pattern is None:
                self.connectivity_pattern = "local_radius"
        if self.connection_density is not None:
            self.connection_density = float(self.connection_density)
            if not 0 < self.connection_density <= 1:
                raise ValueError("Connection density must be within (0, 1].")


@dataclass(slots=True)
class LearningRuleIR:
    """Normalized learning rule scoped to an optional connection."""

    kind: str
    source: str | None = None
    target: str | None = None
    rate: float | None = None
    window: float | None = None
    weight_min: float | None = None
    weight_max: float | None = None
    deployment_mode: Literal["offline_train", "online_learn", "deploy_only"] = "offline_train"
    provenance: list[SourceProvenance] = field(default_factory=list)
    attributes: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.kind = normalize_identifier(self.kind)
        if self.source is not None:
            self.source = normalize_identifier(self.source)
        if self.target is not None:
            self.target = normalize_identifier(self.target)


class AkidaBlockType(StrEnum):
    """Supported Akida block types."""

    SPATIAL = "spatial"
    TEMPORAL = "temporal"


@dataclass(slots=True)
class AkidaHardwareIR:
    """Akida target hardware declaration."""

    version: str
    provenance: list[SourceProvenance] = field(default_factory=list)
    attributes: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class AkidaConnectionPropertyIR:
    """Akida connection property, mapping to spatiotemporal blocks."""

    block_type: AkidaBlockType
    source: str | None = None
    target: str | None = None
    provenance: list[SourceProvenance] = field(default_factory=list)
    attributes: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.source is not None:
            self.source = normalize_identifier(self.source)
        if self.target is not None:
            self.target = normalize_identifier(self.target)


@dataclass(slots=True)
class NetworkIR:
    """Top-level normalized network representation."""

    populations: dict[str, PopulationIR] = field(default_factory=dict)
    connections: list[ConnectionIR] = field(default_factory=list)
    learning_rules: list[LearningRuleIR] = field(default_factory=list)
    timing_declarations: list[TimingDeclarationIR] = field(default_factory=list)
    backend_hints: list[BackendHintIR] = field(default_factory=list)
    akida_hardware: AkidaHardwareIR | None = None
    akida_connection_properties: list[AkidaConnectionPropertyIR] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)
