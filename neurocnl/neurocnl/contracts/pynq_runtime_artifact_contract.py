"""PYNQ Runtime Artifact Contract — overlay-v2 export package validation.

Mirrors ``Neurochip/neurochip/contracts/pynq_runtime_artifact_contract.py``
so an unsupported network is rejected before it ever reaches a board.
"""

from __future__ import annotations

import hashlib
import json
import zipfile
from io import BytesIO
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from .pynq_deployment_contract import DEFAULT_OVERLAY_MANIFEST, PYNQ_LIMITS

REQUIRED_ARTIFACT_FILES: tuple[str, ...] = (
    "pynq_deploy/overlay_config.json",
    "pynq_deploy/weights.bin",
    "pynq_deploy/register_map.json",
    "pynq_deploy/overlay_manifest.json",
    "pynq_deploy/manifest.json",
    "pynq_deploy/README.md",
)


def _overlay_manifest_path() -> Path:
    return (
        Path(__file__).resolve().parents[3]
        / "Neurochip"
        / "hardware"
        / "pynq_z2"
        / "overlay_manifest.json"
    )


def _overlay_manifest_defaults() -> dict[str, Any]:
    path = _overlay_manifest_path()
    if not path.exists():
        return dict(DEFAULT_OVERLAY_MANIFEST)
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload if isinstance(payload, dict) else dict(DEFAULT_OVERLAY_MANIFEST)


_OVERLAY = _overlay_manifest_defaults()


class PynqPopulationEntry(BaseModel):
    """A single population in the overlay configuration."""

    model_config = ConfigDict(frozen=True)

    id: str = Field(..., min_length=1)
    n_neurons: int = Field(..., gt=0)
    neuron_model: str = Field(...)
    params: dict[str, Any] = Field(default_factory=dict)

    @field_validator("neuron_model")
    @classmethod
    def validate_neuron_model(cls, value: str) -> str:
        if value not in PYNQ_LIMITS.SUPPORTED_NEURON_MODELS:
            raise ValueError(
                f"Neuron model '{value}' not supported. "
                f"Allowed: {', '.join(PYNQ_LIMITS.SUPPORTED_NEURON_MODELS)}"
            )
        return value


class PynqConnectionEntry(BaseModel):
    """A single connection in the overlay configuration."""

    model_config = ConfigDict(frozen=True)

    pre: str = Field(..., min_length=1)
    post: str = Field(..., min_length=1)
    weight: int = Field(...)


class PynqQuantisationInfo(BaseModel):
    """Quantization metadata for the overlay."""

    model_config = ConfigDict(frozen=True)

    bits: int = Field(..., gt=0)
    scale_factor: float = Field(..., gt=0)

    @field_validator("bits")
    @classmethod
    def validate_bits(cls, value: int) -> int:
        if value not in PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError(
                f"bits must be one of {PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS} for overlay-v1"
            )
        return value


#: Offsets a host must know to drive the engine. Vitis HLS assigns them, so
#: they are ``None`` until read back out of the built ``.hwh``. Overlay-v1
#: shipped hand-written offsets that disagreed with its own bitstream on every
#: scalar argument, and the host wrote each one to an address nothing decoded.
RESOLVED_REGISTER_FIELDS: tuple[str, ...] = (
    "base_address",
    "control_reg_offset",
    "global_interrupt_enable_offset",
    "interrupt_enable_offset",
    "interrupt_status_offset",
    "weights_ptr_offset",
    "layer_config_ptr_offset",
    "layer_count_offset",
    "weight_count_offset",
    "timestep_count_offset",
)


class PynqRegisterMap(BaseModel):
    """Typed AXI-Lite contract for the overlay-v2 register map."""

    model_config = ConfigDict(frozen=True)

    resolved_from_hwh: bool = Field(default=False)
    base_address: int | None = Field(default=None)
    control_reg_offset: int | None = Field(default=None)
    global_interrupt_enable_offset: int | None = Field(default=None)
    interrupt_enable_offset: int | None = Field(default=None)
    interrupt_status_offset: int | None = Field(default=None)
    weights_ptr_offset: int | None = Field(default=None)
    layer_config_ptr_offset: int | None = Field(default=None)
    layer_count_offset: int | None = Field(default=None)
    weight_count_offset: int | None = Field(default=None)
    timestep_count_offset: int | None = Field(default=None)
    dma_channel: str = Field(default=str(_OVERLAY["dma_ip_name"]), min_length=1)
    timestep_us: int = Field(default=1000, gt=0)

    @field_validator(
        "control_reg_offset",
        "global_interrupt_enable_offset",
        "interrupt_enable_offset",
        "interrupt_status_offset",
        "weights_ptr_offset",
        "layer_config_ptr_offset",
        "layer_count_offset",
        "weight_count_offset",
        "timestep_count_offset",
    )
    @classmethod
    def validate_alignment(cls, value: int | None) -> int | None:
        if value is not None and value % 4 != 0:
            raise ValueError(f"Register offset 0x{value:X} is not 4-byte aligned")
        return value

    @model_validator(mode="after")
    def validate_resolution_is_all_or_nothing(self) -> PynqRegisterMap:
        present = [name for name in RESOLVED_REGISTER_FIELDS if getattr(self, name) is not None]
        if self.resolved_from_hwh:
            missing = [name for name in RESOLVED_REGISTER_FIELDS if getattr(self, name) is None]
            if missing:
                raise ValueError(
                    "register map claims to be resolved from a built overlay but "
                    f"is missing {', '.join(missing)}"
                )
        elif present:
            raise ValueError(
                "register map has offsets but was never resolved from a built "
                f"overlay ({', '.join(present)}); run "
                "hardware/pynq_z2/scripts/sync_manifest_offsets.py --write"
            )
        return self

    def require_resolved(self) -> PynqRegisterMap:
        """Return self, or raise if these offsets cannot be used on hardware."""
        if not self.resolved_from_hwh:
            raise ValueError(
                "This overlay's register offsets were never resolved from a built "
                "bitstream, so the host does not know where to write the engine's "
                "arguments."
            )
        return self


class PynqOverlayManifestContract(BaseModel):
    """Fixed overlay-v1 hardware contract embedded in exported artifacts."""

    model_config = ConfigDict(frozen=True)

    overlay_id: str = Field(default=str(_OVERLAY["overlay_id"]), min_length=1)
    overlay_version: str = Field(default=str(_OVERLAY["overlay_version"]), min_length=1)
    target_part: str = Field(default=str(_OVERLAY["target_part"]), min_length=1)
    supported_neuron_models: tuple[str, ...] = Field(
        default=tuple(_OVERLAY["supported_neuron_models"])
    )
    supported_weight_bit_widths: tuple[int, ...] = Field(
        default=tuple(_OVERLAY["supported_weight_bit_widths"])
    )
    max_neurons: int = Field(default=int(_OVERLAY["max_neurons"]), gt=0)
    max_neurons_per_layer: int = Field(
        default=int(_OVERLAY.get("max_neurons_per_layer", 1024)), gt=0
    )
    max_synapses: int = Field(default=int(_OVERLAY["max_synapses"]), gt=0)
    max_populations: int = Field(default=int(_OVERLAY["max_populations"]), gt=0)
    max_layers: int = Field(
        default=int(_OVERLAY.get("max_layers", _OVERLAY["max_populations"])), gt=0
    )
    dma_ip_name: str = Field(default=str(_OVERLAY["dma_ip_name"]), min_length=1)
    snn_ip_name: str = Field(default=str(_OVERLAY["snn_ip_name"]), min_length=1)
    register_map: PynqRegisterMap = Field(
        default_factory=lambda: PynqRegisterMap(**_OVERLAY["register_map"])
    )
    weight_layout: dict[str, Any] = Field(default_factory=lambda: dict(_OVERLAY["weight_layout"]))
    layer_config_layout: dict[str, Any] = Field(
        default_factory=lambda: dict(_OVERLAY.get("layer_config_layout", {}))
    )

    @model_validator(mode="after")
    def validate_overlay_v2(self) -> PynqOverlayManifestContract:
        if self.overlay_id != PYNQ_LIMITS.OVERLAY_ID:
            raise ValueError(f"overlay_id must be '{PYNQ_LIMITS.OVERLAY_ID}'")
        if self.overlay_version != PYNQ_LIMITS.OVERLAY_VERSION:
            raise ValueError(f"overlay_version must be '{PYNQ_LIMITS.OVERLAY_VERSION}'")
        if tuple(self.supported_neuron_models) != PYNQ_LIMITS.SUPPORTED_NEURON_MODELS:
            raise ValueError("supported_neuron_models must match the overlay contract")
        if tuple(self.supported_weight_bit_widths) != PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError("supported_weight_bit_widths must match the overlay contract")
        if self.max_neurons != PYNQ_LIMITS.MAX_NEURONS:
            raise ValueError("max_neurons must match the overlay contract")
        if self.max_neurons_per_layer != PYNQ_LIMITS.MAX_NEURONS_PER_LAYER:
            raise ValueError("max_neurons_per_layer must match the overlay contract")
        if self.max_synapses != PYNQ_LIMITS.MAX_SYNAPSES:
            raise ValueError("max_synapses must match the overlay contract")
        if self.max_populations != PYNQ_LIMITS.MAX_POPULATIONS:
            raise ValueError("max_populations must match the overlay contract")
        if self.max_layers != PYNQ_LIMITS.MAX_LAYERS:
            raise ValueError("max_layers must match the overlay contract")
        if self.register_map.dma_channel != self.dma_ip_name:
            raise ValueError("register_map.dma_channel must match dma_ip_name")

        weight_entries = int(self.weight_layout.get("max_entries", -1))
        if weight_entries != self.max_synapses:
            raise ValueError("weight_layout.max_entries must match max_synapses")
        if self.weight_layout.get("storage") != "dma_ddr":
            raise ValueError(
                "weight_layout.storage must be 'dma_ddr' — overlay-v1's MMIO "
                "weight window was never wired to the engine"
            )
        return self


class PynqOverlayConfigContract(BaseModel):
    """Validates the ``overlay_config.json`` file produced for overlay-v1."""

    model_config = ConfigDict(frozen=True)

    network_name: str = Field(..., min_length=1)
    populations: list[PynqPopulationEntry] = Field(..., min_length=1)
    connections: list[PynqConnectionEntry] = Field(default_factory=list)
    quantisation: PynqQuantisationInfo
    overlay_id: str = Field(default=PYNQ_LIMITS.OVERLAY_ID)
    overlay_version: str = Field(default=PYNQ_LIMITS.OVERLAY_VERSION)

    @model_validator(mode="after")
    def validate_capacity(self) -> PynqOverlayConfigContract:
        total_neurons = sum(population.n_neurons for population in self.populations)
        if total_neurons > PYNQ_LIMITS.MAX_NEURONS:
            raise ValueError(
                f"Total neurons ({total_neurons}) exceeds the overlay max "
                f"({PYNQ_LIMITS.MAX_NEURONS})"
            )
        oversized = [
            population.id
            for population in self.populations
            if population.n_neurons > PYNQ_LIMITS.MAX_NEURONS_PER_LAYER
        ]
        if oversized:
            raise ValueError(
                f"Population(s) {', '.join(oversized)} exceed the "
                f"{PYNQ_LIMITS.MAX_NEURONS_PER_LAYER}-neuron per-layer limit"
            )
        total_synapses = len(self.connections)
        max_synapses = PYNQ_LIMITS.max_synapses_for_bit_width(self.quantisation.bits)
        if total_synapses > max_synapses:
            raise ValueError(
                f"Total synapses ({total_synapses}) exceeds the overlay max "
                f"({max_synapses}) at {self.quantisation.bits}-bit weights"
            )
        if len(self.populations) > PYNQ_LIMITS.MAX_POPULATIONS:
            raise ValueError(
                f"The overlay supports at most {PYNQ_LIMITS.MAX_POPULATIONS} populations"
            )
        if self.overlay_id != PYNQ_LIMITS.OVERLAY_ID:
            raise ValueError(f"overlay_id must be '{PYNQ_LIMITS.OVERLAY_ID}'")
        if self.overlay_version != PYNQ_LIMITS.OVERLAY_VERSION:
            raise ValueError(f"overlay_version must be '{PYNQ_LIMITS.OVERLAY_VERSION}'")
        return self

    @model_validator(mode="after")
    def validate_population_refs(self) -> PynqOverlayConfigContract:
        population_ids = {population.id for population in self.populations}
        for connection in self.connections:
            if connection.pre not in population_ids:
                raise ValueError(
                    f"Connection references unknown source population '{connection.pre}'"
                )
            if connection.post not in population_ids:
                raise ValueError(
                    f"Connection references unknown target population '{connection.post}'"
                )
        # v1 could hold exactly one dense matrix. v2 holds up to MAX_LAYERS, but
        # the engine walks them in order, so they must form one unbranched chain.
        unique_pairs = {(connection.pre, connection.post) for connection in self.connections}
        if len(unique_pairs) > PYNQ_LIMITS.MAX_LAYERS:
            raise ValueError(
                f"The overlay supports at most {PYNQ_LIMITS.MAX_LAYERS} weight "
                f"matrices, got {len(unique_pairs)}"
            )
        sources = [pre for pre, _ in unique_pairs]
        targets = [post for _, post in unique_pairs]
        if len(set(sources)) != len(sources) or len(set(targets)) != len(targets):
            raise ValueError(
                "The overlay runs one feedforward chain of layers; a branching or "
                "merging topology has nowhere to go"
            )
        return self


class PynqRuntimeArtifact(BaseModel):
    """Top-level contract for a complete overlay-v1 runtime artifact."""

    model_config = ConfigDict(frozen=True)

    target_device: str = Field(default="PYNQ-Z2")
    overlay_manifest: PynqOverlayManifestContract
    overlay_config: PynqOverlayConfigContract
    register_map: PynqRegisterMap
    weight_bit_width: int = Field(..., gt=0)
    weights_checksum_sha256: str = Field(..., pattern=r"^[a-fA-F0-9]{64}$")
    manifest_checksum_sha256: str = Field(..., pattern=r"^[a-fA-F0-9]{64}$")
    total_neurons: int = Field(..., gt=0)
    total_synapses: int = Field(..., ge=0)

    @model_validator(mode="after")
    def validate_target(self) -> PynqRuntimeArtifact:
        if self.target_device != "PYNQ-Z2":
            raise ValueError(f"target_device must be 'PYNQ-Z2', got '{self.target_device}'")
        if self.weight_bit_width != self.overlay_config.quantisation.bits:
            raise ValueError("weight_bit_width must match overlay_config.quantisation.bits")
        if self.weight_bit_width not in self.overlay_manifest.supported_weight_bit_widths:
            raise ValueError("weight_bit_width is not supported by the overlay manifest")
        if self.total_neurons > self.overlay_manifest.max_neurons:
            raise ValueError("total_neurons exceeds overlay manifest limits")
        if self.total_synapses > self.overlay_manifest.max_synapses:
            raise ValueError("total_synapses exceeds overlay manifest limits")
        if self.register_map.model_dump() != self.overlay_manifest.register_map.model_dump():
            raise ValueError("register_map must match the overlay manifest register map")
        return self


def validate_pynq_artifact_completeness(
    zip_source: str | Path | bytes | BytesIO,
) -> PynqRuntimeArtifact:
    """Open a PYNQ artifact ZIP and validate all contents against contracts."""
    if isinstance(zip_source, str | Path):
        zip_source = Path(zip_source)
        if not zip_source.exists():
            raise FileNotFoundError(f"Artifact not found: {zip_source}")
        fh: Path | BytesIO = zip_source
    elif isinstance(zip_source, bytes):
        fh = BytesIO(zip_source)
    else:
        fh = zip_source

    with zipfile.ZipFile(fh, "r") as archive:
        namelist = set(archive.namelist())
        missing = [filename for filename in REQUIRED_ARTIFACT_FILES if filename not in namelist]
        if missing:
            raise ValueError(f"Artifact ZIP is missing required files: {', '.join(missing)}")

        overlay_manifest_raw = json.loads(
            archive.read("pynq_deploy/overlay_manifest.json").decode("utf-8")
        )
        overlay_manifest = PynqOverlayManifestContract.model_validate(overlay_manifest_raw)

        overlay_raw = json.loads(archive.read("pynq_deploy/overlay_config.json").decode("utf-8"))
        overlay_config = PynqOverlayConfigContract.model_validate(overlay_raw)

        register_map_raw = json.loads(archive.read("pynq_deploy/register_map.json").decode("utf-8"))
        register_map = PynqRegisterMap.model_validate(register_map_raw)

        manifest_raw = json.loads(archive.read("pynq_deploy/manifest.json").decode("utf-8"))
        manifest_checksum = manifest_raw.get("checksum_sha256", "")

        weights_data = archive.read("pynq_deploy/weights.bin")
        weights_checksum = hashlib.sha256(weights_data).hexdigest()
        total_neurons = sum(population.n_neurons for population in overlay_config.populations)
        total_synapses = len(overlay_config.connections)

        return PynqRuntimeArtifact(
            target_device=manifest_raw.get("target_device", "PYNQ-Z2"),
            overlay_manifest=overlay_manifest,
            overlay_config=overlay_config,
            register_map=register_map,
            weight_bit_width=overlay_config.quantisation.bits,
            weights_checksum_sha256=weights_checksum,
            manifest_checksum_sha256=manifest_checksum,
            total_neurons=total_neurons,
            total_synapses=total_synapses,
        )
