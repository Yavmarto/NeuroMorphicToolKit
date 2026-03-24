"""Domain contracts for NeuroSim visual network designer.

Converts neurosim_spec.md functional requirements into contracts.

Source: Neurosim/neurosim_spec.md (NS-D1 through NS-E2)
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class ComponentBlockContract(BaseModel):
    """Contract for a canvas component block (NS-D1)."""

    model_config = ConfigDict(frozen=True)

    id: str
    name: str
    category: Literal["Neurons", "Synapses", "Encoders", "Patterns"]
    neuron_count: int | None = None
    neuron_model: str | None = None
    threshold: float | None = None
    tau_rc: float | None = None
    tau_ref: float | None = None

    @field_validator("neuron_count")
    @classmethod
    def positive_if_present(cls, v: int | None) -> int | None:
        if v is not None and v < 1:
            raise ValueError(f"Neuron count must be >= 1, got {v}")
        return v


class ConnectionContract(BaseModel):
    """Contract for a visual connection between populations (NS-D2)."""

    model_config = ConfigDict(frozen=True)

    source_id: str
    target_id: str
    weight: float = 1.0
    synapse_type: str = "Lowpass"

    @model_validator(mode="after")
    def no_self_connection(self) -> ConnectionContract:
        if self.source_id == self.target_id:
            raise ValueError(
                f"Self-connections not allowed: {self.source_id} → {self.target_id}"
            )
        return self


class CanvasGraphContract(BaseModel):
    """Contract for the complete canvas graph."""

    model_config = ConfigDict(frozen=True)

    nodes: list[dict]
    edges: list[dict]

    @field_validator("nodes")
    @classmethod
    def at_least_one_node(cls, v: list[dict]) -> list[dict]:
        if len(v) < 1:
            raise ValueError("Canvas must have at least 1 node.")
        return v

    @model_validator(mode="after")
    def edges_reference_existing_nodes(self) -> CanvasGraphContract:
        node_ids = {n.get("id") for n in self.nodes}
        for edge in self.edges:
            src = edge.get("source") or edge.get("source_id")
            tgt = edge.get("target") or edge.get("target_id")
            if src not in node_ids:
                raise ValueError(f"Edge source '{src}' not in node set.")
            if tgt not in node_ids:
                raise ValueError(f"Edge target '{tgt}' not in node set.")
        return self


class PreviewContract(BaseModel):
    """Contract for simulation preview (NS-S1).

    Preview must be <=500ms simulated time, update within 2s wall time.
    """

    model_config = ConfigDict(frozen=True)

    simulated_duration_ms: float
    wall_time_ms: float

    @field_validator("simulated_duration_ms")
    @classmethod
    def under_500ms(cls, v: float) -> float:
        if v > 500:
            raise ValueError(
                f"Preview duration {v}ms exceeds 500ms limit (NS-S1)."
            )
        return v

    @field_validator("wall_time_ms")
    @classmethod
    def under_2s_wall(cls, v: float) -> float:
        if v > 2000:
            raise ValueError(
                f"Preview wall time {v}ms exceeds 2000ms target (NS-S1)."
            )
        return v


class ParameterSweepContract(BaseModel):
    """Contract for parameter sweep mode (NS-S2)."""

    model_config = ConfigDict(frozen=True)

    param_name: str
    start: float
    stop: float
    n_steps: int

    @field_validator("n_steps")
    @classmethod
    def max_20_steps(cls, v: int) -> int:
        if v < 1 or v > 20:
            raise ValueError(
                f"Sweep steps {v} outside range [1, 20] (NS-S2 limit)."
            )
        return v

    @model_validator(mode="after")
    def start_before_stop(self) -> ParameterSweepContract:
        if self.start >= self.stop:
            raise ValueError(
                f"Sweep start ({self.start}) must be < stop ({self.stop})."
            )
        return self


class ExportFormatContract(BaseModel):
    """Contract for multi-format export (NS-E1)."""

    model_config = ConfigDict(frozen=True)

    format: Literal["cnl", "nengo_python", "c_header", "neuroml", "svg"]
    content: str

    @field_validator("content")
    @classmethod
    def non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Export content must not be empty.")
        return v
