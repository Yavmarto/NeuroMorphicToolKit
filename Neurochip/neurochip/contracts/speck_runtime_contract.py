"""Speck 2 Runtime Artifact Contract — Neurochip-side defense-in-depth validation.

Validates payloads against SynSense Speck 2 limits before artifact generation
proceeds, and defines the expected package structure for the Speck export
pipeline.
"""

from __future__ import annotations

import io
import json
import zipfile
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator

# ---------------------------------------------------------------------------
# Hardware limits (from Speck Dev Kit Manual)
# ---------------------------------------------------------------------------

MAX_NEURONS: int = 320_000
CORE_COUNT: int = 11
CNN_CORE_COUNT: int = 9
MEMORY_BUDGET_KB: int = 2048
SUPPORTED_NEURON_MODELS: tuple[str, ...] = ("lif",)
SUPPORTED_WEIGHT_BIT_WIDTHS: tuple[int, ...] = (8,)
MAX_WEIGHT: float = 127.0

# ---------------------------------------------------------------------------
# Payload validation contract (runtime gate)
# ---------------------------------------------------------------------------


class SpeckMappedNetworkPayloadContract(BaseModel):
    """Validate the mapped-network payload accepted by the Speck runtime."""

    model_config = ConfigDict(frozen=True)

    populations: list[dict[str, Any]] = Field(...)
    connections: list[dict[str, Any]] = Field(default_factory=list)
    network_summary: dict[str, Any] | None = None

    @model_validator(mode="after")
    def validate_speck_limits(self) -> SpeckMappedNetworkPayloadContract:
        """Enforce basic Speck 2 runtime limits on the mapped payload."""
        if not self.populations:
            raise ValueError("populations must not be empty")

        total_neurons = 0
        for population in self.populations:
            size = population.get("size")
            if not isinstance(size, int) or size <= 0:
                raise ValueError(
                    f"Population '{population.get('id', '?')}' has invalid size {size!r}"
                )

            neuron_model = str(population.get("neuron_model", "lif")).lower()
            if neuron_model not in SUPPORTED_NEURON_MODELS:
                raise ValueError(
                    f"Population '{population.get('id', '?')}' uses unsupported neuron_model "
                    f"{neuron_model!r}; supported: {', '.join(SUPPORTED_NEURON_MODELS)}"
                )
            total_neurons += size

        if total_neurons > MAX_NEURONS:
            raise ValueError(
                f"Total neurons ({total_neurons:,}) exceeds Speck 2 max ({MAX_NEURONS:,})"
            )

        weight_bit_width = None
        if self.network_summary is not None:
            summary_width = self.network_summary.get("weight_bit_width")
            if isinstance(summary_width, int):
                weight_bit_width = summary_width
        if weight_bit_width is not None and weight_bit_width not in SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError(
                f"weight_bit_width ({weight_bit_width}) not in supported set "
                f"{SUPPORTED_WEIGHT_BIT_WIDTHS}"
            )

        for connection in self.connections:
            weight = connection.get("weight")
            if weight is None:
                continue
            if not isinstance(weight, (int, float)):
                raise ValueError(
                    f"Connection '{connection.get('source', '?')}' -> "
                    f"'{connection.get('target', '?')}' has non-numeric weight {weight!r}"
                )
            if abs(float(weight)) > MAX_WEIGHT:
                raise ValueError(f"Connection weight ({weight}) exceeds Speck 2 max ({MAX_WEIGHT})")

        return self


# ---------------------------------------------------------------------------
# Environment Diagnostics
# ---------------------------------------------------------------------------


class SpeckEnvironmentChecks(BaseModel):
    """Structured diagnostics for the local Speck runtime environment."""

    model_config = ConfigDict(frozen=True)

    host_supported: bool
    python_supported: bool
    sinabs_available: bool
    samna_available: bool
    device_discovery_supported: bool = False
    device_discovered: bool = False
    discovered_device_count: int = 0
    recommended_runtime: Literal["local_hw", "simulator", "not_available"] = Field(
        default="simulator"
    )


class SpeckRuntimeStatusContract(BaseModel):
    """Typed status payload shared by the Speck runtime routes."""

    model_config = ConfigDict(frozen=True)

    state: str
    sdk_available: bool
    sdk_status: str
    sdk_issues: list[str] = Field(default_factory=list)
    model_summary: dict[str, Any] | None = None
    runtime_target: str = "unknown"
    device_info: str | None = None
    sdk_issue_detail: str | None = None
    environment_checks: SpeckEnvironmentChecks


class SpeckSamnaConfigContract(BaseModel):
    """Typed payload stored in `config.samna` for the Speck runtime."""

    model_config = ConfigDict(frozen=True)

    device_type_name: str = Field(..., min_length=1)
    samna_configuration_type: Literal["samna.speck2f.configuration.SpeckConfiguration"]
    artifact_mode: Literal["scaffold", "samna_configured"] = "scaffold"
    monitor_enable: bool = True
    readout_enable: bool = False
    input_spike_layer: int = Field(..., ge=0, le=13)
    output_event_mode: Literal["readout_pin", "spike_monitor"] = "spike_monitor"
    configuration_json: str = Field(..., min_length=2)
    population_count: int = Field(..., ge=1)
    connection_count: int = Field(..., ge=0)


class SpeckDeploymentManifest(BaseModel):
    """Manifest for Speck deployment artifacts."""

    model_config = ConfigDict(frozen=True)

    target_device: Literal["SynSense Speck 2"] = "SynSense Speck 2"
    core_count: int = Field(..., ge=1, le=CORE_COUNT)
    firmware_version: str = Field(..., pattern=r"^\d+\.\d+\.\d+$")
    artifact_schema_version: str = Field(..., pattern=r"^\d+\.\d+\.\d+$")
    checksum_sha256: str = Field(..., pattern=r"^[a-fA-F0-9]{64}$")
    sdk_required: bool = True
    input_event_format: Literal["dvs_events"] = "dvs_events"


# ---------------------------------------------------------------------------
# Required artifact files
# ---------------------------------------------------------------------------

REQUIRED_ARTIFACT_FILES: tuple[str, ...] = (
    "speck_deploy/model.json",
    "speck_deploy/compile_plan.json",
    "speck_deploy/config.samna",
    "speck_deploy/manifest.json",
    "speck_deploy/README.md",
)


def validate_speck_runtime_artifact_archive(archive_bytes: bytes) -> SpeckDeploymentManifest:
    """Validate the Speck runtime archive structure and return its manifest."""
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        namelist = archive.namelist()
        missing = [filename for filename in REQUIRED_ARTIFACT_FILES if filename not in namelist]
        if missing:
            raise ValueError(f"Speck artifact archive is missing required files: {missing}")

        model_raw = json.loads(archive.read("speck_deploy/model.json").decode("utf-8"))
        SpeckMappedNetworkPayloadContract(**model_raw["mapped_network"])
        compile_plan_raw = json.loads(
            archive.read("speck_deploy/compile_plan.json").decode("utf-8")
        )
        if "deployable" not in compile_plan_raw:
            raise ValueError("speck_deploy/compile_plan.json is missing deployable")
        if "compiler_backend" not in compile_plan_raw:
            raise ValueError("speck_deploy/compile_plan.json is missing compiler_backend")

        config_raw = archive.read("speck_deploy/config.samna").decode("utf-8")
        config_json = json.loads(config_raw)
        SpeckSamnaConfigContract(**config_json)

        manifest_raw = json.loads(archive.read("speck_deploy/manifest.json").decode("utf-8"))
        try:
            manifest = SpeckDeploymentManifest(**manifest_raw)
        except ValidationError as exc:  # pragma: no cover - exercised in tests
            raise ValueError(f"Speck manifest validation failed: {exc}") from exc

    return manifest
