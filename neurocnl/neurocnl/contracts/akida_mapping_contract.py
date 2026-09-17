"""Shared Akida mapping contract for scaffold generation and future handoff.

Defines the canonical representation produced after NeuroCNL IR has been
validated and lowered into Akida-specific deployment semantics.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from neurocnl.contracts.akida_deployment_contract import normalize_akida_version


class AkidaMappedProvenance(BaseModel):
    """Serializable provenance entry attached to mapped Akida elements."""

    model_config = ConfigDict(frozen=True)

    line: int | None = None
    raw: str | None = None
    concept: str | None = None


class AkidaMappedPopulation(BaseModel):
    """Population entry in the shared Akida mapping representation."""

    model_config = ConfigDict(frozen=True)

    id: str = Field(..., min_length=1)
    size: int = Field(..., gt=0)
    role: str | None = None
    population_type: str | None = None
    provenance: list[AkidaMappedProvenance] = Field(default_factory=list)
    attributes: dict[str, Any] = Field(default_factory=dict)


class AkidaMappedConnection(BaseModel):
    """Connection entry in the shared Akida mapping representation."""

    model_config = ConfigDict(frozen=True)

    source: str = Field(..., min_length=1)
    target: str = Field(..., min_length=1)
    units: int = Field(..., gt=0)
    weight: float | None = None
    block_type: str | None = None
    provenance: list[AkidaMappedProvenance] = Field(default_factory=list)
    property_provenance: list[AkidaMappedProvenance] = Field(default_factory=list)
    attributes: dict[str, Any] = Field(default_factory=dict)

    @field_validator("block_type")
    @classmethod
    def validate_block_type(cls, value: str | None) -> str | None:
        if value is None:
            return None

        normalized = value.strip().lower()
        if normalized not in {"spatial", "temporal"}:
            raise ValueError(
                f"Unsupported Akida block_type {value!r}; expected 'spatial' or 'temporal'."
            )
        return normalized


class AkidaMappedNetwork(BaseModel):
    """Top-level shared Akida mapping representation."""

    model_config = ConfigDict(frozen=True)

    akida_version: str = Field(..., description="Canonical Akida version.")
    input_population: str | None = Field(default=None)
    populations: list[AkidaMappedPopulation] = Field(default_factory=list)
    connections: list[AkidaMappedConnection] = Field(default_factory=list)
    topology_verdict: str = Field(default="faithful")
    warnings: list[str] = Field(default_factory=list)
    network_summary: dict[str, Any] = Field(default_factory=dict)
    metadata_provenance: list[AkidaMappedProvenance] = Field(default_factory=list)

    @field_validator("akida_version", mode="before")
    @classmethod
    def normalize_version(cls, value: str | None) -> str:
        return normalize_akida_version(value)

    @model_validator(mode="after")
    def validate_references(self) -> AkidaMappedNetwork:
        population_ids = [population.id for population in self.populations]
        population_id_set = set(population_ids)

        if len(population_ids) != len(population_id_set):
            raise ValueError("Mapped populations must have unique ids.")

        if self.input_population is not None and self.input_population not in population_id_set:
            raise ValueError(
                f"input_population {self.input_population!r} is not present in populations."
            )

        for connection in self.connections:
            if connection.source not in population_id_set:
                raise ValueError(
                    f"Mapped connection references unknown source {connection.source!r}."
                )
            if connection.target not in population_id_set:
                raise ValueError(
                    f"Mapped connection references unknown target {connection.target!r}."
                )

        return self
