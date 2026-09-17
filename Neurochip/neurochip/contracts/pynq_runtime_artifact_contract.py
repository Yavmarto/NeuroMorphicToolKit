"""PYNQ Runtime Artifact Contract — Neurochip-side defense-in-depth validation.

This module defines the fixed overlay-v2 contract used by the PYNQ Z2 hardware
path. The same values are mirrored in neurocnl so unsupported networks fail
early before they ever reach the real board.

Overlay-v1's register map was written by hand and disagreed with its own
bitstream on every scalar argument, so the host wrote each one to an address
the hardware did not decode. v2 therefore treats an *unresolved* register map
as a first-class state: offsets are ``None`` until
``hardware/pynq_z2/scripts/sync_manifest_offsets.py`` fills them in from the
generated ``.hwh``, and anything that would drive the hardware must refuse an
unresolved map rather than fall back to a plausible-looking default.
"""

from __future__ import annotations

import hashlib
import json
import zipfile
from io import BytesIO
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

PYNQ_OVERLAY_ID = "snn_overlay_v2"
PYNQ_OVERLAY_VERSION = "2.0.0"
PYNQ_TARGET_PART = "xc7z020clg400-1"

#: Mirrors ``OVERLAY_V2_MAX_NEURONS`` in ``hls/snn_overlay_engine.hpp``.
MAX_NEURONS_PER_LAYER: int = 1024
#: Mirrors ``OVERLAY_V2_MAX_LAYERS``. One weight matrix per layer.
MAX_LAYERS: int = 4
#: Mirrors ``OVERLAY_V2_MAX_SYNAPSES`` — the on-chip weight cache, in int8s.
WEIGHT_CACHE_BYTES: int = 262144

MAX_NEURONS: int = MAX_NEURONS_PER_LAYER * MAX_LAYERS
MAX_SYNAPSES: int = WEIGHT_CACHE_BYTES
#: A population is the output of one layer; the DMA-streamed input port is not
#: stored on the fabric and so does not consume one.
MAX_POPULATIONS: int = MAX_LAYERS

#: Weight cache plus per-neuron state (int32 membrane + uint8 refractory).
MEMORY_BUDGET_KB: int = 320
IO_PINS: int = 40
CORE_COUNT: int = 2
SUPPORTED_NEURON_MODELS: tuple[str, ...] = ("LIF",)
SUPPORTED_WEIGHT_BIT_WIDTHS: tuple[int, ...] = (8,)
DMA_IP_NAME = "axi_dma_0"
SNN_IP_NAME = "snn_engine_0"

#: Descriptor layout, mirroring the ``OVERLAY_V2_CFG_*`` constants in the HLS
#: header. Layer L's descriptor starts at word ``L * WORDS_PER_LAYER``.
CONFIG_WORDS_PER_LAYER: int = 8
CONFIG_FIELD_OFFSETS: dict[str, int] = {
    "input_size": 0,
    "output_size": 1,
    "weight_offset": 2,
    "threshold": 3,
    "leak_shift": 4,
    "refractory": 5,
}

#: The register offsets a host must know to drive the engine. There are no
#: sensible defaults: they are assigned by Vitis HLS and must be read back out
#: of the built ``.hwh``.
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

#: `CTRL` bit assignments, fixed by the Vitis HLS s_axilite protocol. v1's host
#: wrote a weight count over these bits and then poked an unmapped offset,
#: so the kernel was never deliberately started.
CTRL_AP_START_BIT: int = 0x1
CTRL_AP_DONE_BIT: int = 0x2
CTRL_AP_IDLE_BIT: int = 0x4

DEFAULT_REGISTER_MAP: dict[str, Any] = {
    "resolved_from_hwh": False,
    "base_address": None,
    "control_reg_offset": None,
    "global_interrupt_enable_offset": None,
    "interrupt_enable_offset": None,
    "interrupt_status_offset": None,
    "weights_ptr_offset": None,
    "layer_config_ptr_offset": None,
    "layer_count_offset": None,
    "weight_count_offset": None,
    "timestep_count_offset": None,
    "dma_channel": DMA_IP_NAME,
    "timestep_us": 1000,
}
DEFAULT_WEIGHT_LAYOUT: dict[str, Any] = {
    "format": "int8_dense_row_major_ddr",
    "storage": "dma_ddr",
    "element_bytes": 1,
    "max_entries": MAX_SYNAPSES,
    "matrix_order": "post_by_pre",
}
DEFAULT_LAYER_CONFIG_LAYOUT: dict[str, Any] = {
    "format": "uint32_words",
    "storage": "dma_ddr",
    "words_per_layer": CONFIG_WORDS_PER_LAYER,
    "max_layers": MAX_LAYERS,
    "fields": dict(CONFIG_FIELD_OFFSETS),
}
DEFAULT_STREAM_PROTOCOL: dict[str, Any] = {
    "input_words_per_timestep": "layer_config[0].input_size",
    "output_words_per_timestep": "layer_config[layer_count - 1].output_size",
    "input_encoding": "nonzero_is_spike",
    "output_encoding": "one_word_per_neuron_value_1_is_spike",
    "tlast": "final_word_of_run_only",
}
DEFAULT_OVERLAY_MANIFEST: dict[str, Any] = {
    "overlay_id": PYNQ_OVERLAY_ID,
    "overlay_version": PYNQ_OVERLAY_VERSION,
    "target_part": PYNQ_TARGET_PART,
    "supported_neuron_models": list(SUPPORTED_NEURON_MODELS),
    "supported_weight_bit_widths": list(SUPPORTED_WEIGHT_BIT_WIDTHS),
    "max_neurons": MAX_NEURONS,
    "max_neurons_per_layer": MAX_NEURONS_PER_LAYER,
    "max_synapses": MAX_SYNAPSES,
    "max_populations": MAX_POPULATIONS,
    "max_layers": MAX_LAYERS,
    "dma_ip_name": DMA_IP_NAME,
    "snn_ip_name": SNN_IP_NAME,
    "register_map": dict(DEFAULT_REGISTER_MAP),
    "weight_layout": dict(DEFAULT_WEIGHT_LAYOUT),
    "layer_config_layout": dict(DEFAULT_LAYER_CONFIG_LAYOUT),
    "stream_protocol": dict(DEFAULT_STREAM_PROTOCOL),
}


#: Per-neuron on-chip state: int32 membrane potential + uint8 refractory
#: counter. v1's estimate also charged 8 bytes per synapse for pre/post index
#: pairs, which a dense row-major matrix does not store.
NEURON_STATE_BYTES: int = 5


def estimate_fabric_memory_kb(
    *, num_neurons: int, num_synapses: int, weight_bit_width: int
) -> float:
    """Estimate on-chip memory for a network, in KB."""
    weight_bytes = num_synapses * (weight_bit_width / 8)
    neuron_bytes = num_neurons * NEURON_STATE_BYTES
    return (weight_bytes + neuron_bytes) / 1024


def max_synapses_for_bit_width(bit_width: int) -> int:
    """Return how many weights of this width fit in the on-chip cache.

    The cache is sized in bytes, so this genuinely computes rather than
    returning a constant regardless of the width it was asked about.
    """
    if bit_width not in SUPPORTED_WEIGHT_BIT_WIDTHS:
        return 0
    return (WEIGHT_CACHE_BYTES * 8) // bit_width


class PynqRegisterMapContract(BaseModel):
    """Typed register-map contract shared by the generator and runtime.

    Every offset is ``None`` until resolved from a built overlay. Reading an
    unresolved map is legal — describing an overlay that has not been built yet
    is a real state — but driving hardware from one is not; see
    :meth:`require_resolved`.
    """

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
    dma_channel: str = Field(default=DMA_IP_NAME, min_length=1)
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
    def validate_resolution_is_all_or_nothing(self) -> PynqRegisterMapContract:
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
                f"overlay ({', '.join(present)}). Overlay-v1 shipped hand-written "
                "offsets that pointed at nothing; run "
                "hardware/pynq_z2/scripts/sync_manifest_offsets.py --write."
            )
        return self

    def require_resolved(self) -> PynqRegisterMapContract:
        """Return self, or raise if these offsets cannot be used on hardware."""
        if not self.resolved_from_hwh:
            raise ValueError(
                "This overlay's register offsets were never resolved from a built "
                "bitstream, so the host does not know where to write the engine's "
                "arguments. Rebuild the overlay with "
                "hardware/pynq_z2/scripts/build_overlay.sh."
            )
        return self


class PynqOverlayManifestContract(BaseModel):
    """Overlay-v2 manifest contract shared by hardware, generator, and runtime."""

    model_config = ConfigDict(frozen=True)

    overlay_id: str = Field(default=PYNQ_OVERLAY_ID, min_length=1)
    overlay_version: str = Field(default=PYNQ_OVERLAY_VERSION, min_length=1)
    target_part: str = Field(default=PYNQ_TARGET_PART, min_length=1)
    supported_neuron_models: tuple[str, ...] = Field(default=SUPPORTED_NEURON_MODELS)
    supported_weight_bit_widths: tuple[int, ...] = Field(default=SUPPORTED_WEIGHT_BIT_WIDTHS)
    max_neurons: int = Field(default=MAX_NEURONS, gt=0)
    max_neurons_per_layer: int = Field(default=MAX_NEURONS_PER_LAYER, gt=0)
    max_synapses: int = Field(default=MAX_SYNAPSES, gt=0)
    max_populations: int = Field(default=MAX_POPULATIONS, gt=0)
    max_layers: int = Field(default=MAX_LAYERS, gt=0)
    dma_ip_name: str = Field(default=DMA_IP_NAME, min_length=1)
    snn_ip_name: str = Field(default=SNN_IP_NAME, min_length=1)
    register_map: PynqRegisterMapContract = Field(
        default_factory=lambda: PynqRegisterMapContract(**DEFAULT_REGISTER_MAP)
    )
    weight_layout: dict[str, Any] = Field(default_factory=lambda: dict(DEFAULT_WEIGHT_LAYOUT))
    layer_config_layout: dict[str, Any] = Field(
        default_factory=lambda: dict(DEFAULT_LAYER_CONFIG_LAYOUT)
    )
    stream_protocol: dict[str, Any] = Field(default_factory=lambda: dict(DEFAULT_STREAM_PROTOCOL))

    @model_validator(mode="before")
    @classmethod
    def require_contract_register_keys(cls, payload: Any) -> Any:
        """Reject a parsed manifest whose ``register_map`` lost a contract key.

        ``PynqRegisterMapContract.dma_channel`` has a default so the runtime can
        build a register map from a live overlay without restating it. Applied to
        a manifest *file*, that default silently repaired an absent key here while
        the launcher's own validator refused the same file — v2 shipped with the
        key dropped by ``sync_manifest_offsets.py --write`` and every board
        reported "Overlay Missing" with a working bitstream on disk. A manifest
        that names a register_map must name its contract keys too.
        """
        if not isinstance(payload, dict):
            return payload
        register_map = payload.get("register_map")
        if isinstance(register_map, dict) and "dma_channel" not in register_map:
            raise ValueError("register_map.dma_channel is missing from the manifest")
        return payload

    @model_validator(mode="after")
    def validate_overlay_v2(self) -> PynqOverlayManifestContract:
        if self.overlay_id != PYNQ_OVERLAY_ID:
            raise ValueError(
                f"overlay_id must be '{PYNQ_OVERLAY_ID}' for the fixed overlay-v2 runtime"
            )
        if self.overlay_version != PYNQ_OVERLAY_VERSION:
            raise ValueError(
                f"overlay_version must be '{PYNQ_OVERLAY_VERSION}' for the fixed overlay-v2 runtime"
            )
        if self.target_part != PYNQ_TARGET_PART:
            raise ValueError(f"target_part must be '{PYNQ_TARGET_PART}' for the PYNQ Z2 build")
        if tuple(self.supported_neuron_models) != SUPPORTED_NEURON_MODELS:
            raise ValueError(
                f"supported_neuron_models must be {SUPPORTED_NEURON_MODELS} for overlay-v2"
            )
        if tuple(self.supported_weight_bit_widths) != SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError("supported_weight_bit_widths must match the fixed overlay-v2 contract")
        if self.max_neurons_per_layer != MAX_NEURONS_PER_LAYER:
            raise ValueError(
                f"max_neurons_per_layer must be {MAX_NEURONS_PER_LAYER} for overlay-v2"
            )
        if self.max_layers != MAX_LAYERS:
            raise ValueError(f"max_layers must be {MAX_LAYERS} for overlay-v2")
        if self.max_neurons != MAX_NEURONS:
            raise ValueError(f"max_neurons must be {MAX_NEURONS} for overlay-v2")
        if self.max_synapses != MAX_SYNAPSES:
            raise ValueError(f"max_synapses must be {MAX_SYNAPSES} for overlay-v2")
        if self.max_populations != MAX_POPULATIONS:
            raise ValueError(f"max_populations must be {MAX_POPULATIONS} for overlay-v2")
        if self.register_map.dma_channel != self.dma_ip_name:
            raise ValueError("register_map.dma_channel must match dma_ip_name")

        weight_entries = int(self.weight_layout.get("max_entries", -1))
        if weight_entries != self.max_synapses:
            raise ValueError("weight_layout.max_entries must match max_synapses")
        if self.weight_layout.get("storage") != DEFAULT_WEIGHT_LAYOUT["storage"]:
            raise ValueError(
                "weight_layout.storage must be 'dma_ddr' — overlay-v1's MMIO "
                "weight window was never wired to the engine"
            )

        words_per_layer = int(self.layer_config_layout.get("words_per_layer", -1))
        if words_per_layer != CONFIG_WORDS_PER_LAYER:
            raise ValueError(
                f"layer_config_layout.words_per_layer must be {CONFIG_WORDS_PER_LAYER}"
            )
        if dict(self.layer_config_layout.get("fields", {})) != CONFIG_FIELD_OFFSETS:
            raise ValueError("layer_config_layout.fields must match the HLS descriptor layout")
        return self


class PynqNetworkPayloadContract(BaseModel):
    """Validates a NetworkInput payload before PYNQ artifact generation."""

    model_config = ConfigDict(frozen=True)

    num_neurons: int = Field(..., gt=0)
    num_synapses: int = Field(..., ge=0)
    neuron_model: str = Field(...)
    weight_bit_width: int = Field(..., gt=0)
    network_depth: int = Field(..., ge=1)
    n_populations: int = Field(default=2, ge=1)

    @model_validator(mode="after")
    def validate_pynq_limits(self) -> PynqNetworkPayloadContract:
        if self.num_neurons > MAX_NEURONS:
            raise ValueError(
                f"num_neurons ({self.num_neurons}) exceeds overlay-v2 max ({MAX_NEURONS})"
            )
        if self.n_populations > MAX_POPULATIONS:
            raise ValueError(
                f"n_populations ({self.n_populations}) exceeds overlay-v2 max ({MAX_POPULATIONS})"
            )
        if self.neuron_model.upper() not in SUPPORTED_NEURON_MODELS:
            raise ValueError(
                f"neuron_model '{self.neuron_model}' not supported by overlay-v2. "
                f"Supported: {', '.join(SUPPORTED_NEURON_MODELS)}"
            )
        if self.weight_bit_width not in SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError(
                f"weight_bit_width ({self.weight_bit_width}) not in supported set "
                f"{SUPPORTED_WEIGHT_BIT_WIDTHS}"
            )
        max_syn = max_synapses_for_bit_width(self.weight_bit_width)
        if self.num_synapses > max_syn:
            raise ValueError(
                f"num_synapses ({self.num_synapses}) exceeds overlay-v2 max "
                f"({max_syn}) at {self.weight_bit_width}-bit weights"
            )
        if self.num_neurons > 0:
            memory_kb = estimate_fabric_memory_kb(
                num_neurons=self.num_neurons,
                num_synapses=self.num_synapses,
                weight_bit_width=self.weight_bit_width,
            )
            if memory_kb > MEMORY_BUDGET_KB:
                raise ValueError(
                    f"Estimated memory ({memory_kb:.1f} KB) exceeds PYNQ Z2 budget "
                    f"({MEMORY_BUDGET_KB} KB)"
                )
        return self


REQUIRED_ARTIFACT_FILES: tuple[str, ...] = (
    "pynq_deploy/overlay_config.json",
    "pynq_deploy/weights.bin",
    "pynq_deploy/register_map.json",
    "pynq_deploy/overlay_manifest.json",
    "pynq_deploy/manifest.json",
    "pynq_deploy/README.md",
)


class PynqOverlayPopulationContract(BaseModel):
    """Population entry embedded in ``overlay_config.json``."""

    model_config = ConfigDict(frozen=True)

    id: str = Field(..., min_length=1)
    n_neurons: int = Field(..., gt=0)
    neuron_model: str = Field(...)
    params: dict[str, Any] = Field(default_factory=dict)

    @field_validator("neuron_model")
    @classmethod
    def validate_neuron_model(cls, value: str) -> str:
        if value.upper() not in SUPPORTED_NEURON_MODELS:
            raise ValueError(
                f"neuron_model '{value}' not supported by overlay-v2. "
                f"Supported: {', '.join(SUPPORTED_NEURON_MODELS)}"
            )
        return value


class PynqOverlayConnectionContract(BaseModel):
    """Connection entry embedded in ``overlay_config.json``."""

    model_config = ConfigDict(frozen=True)

    pre: str = Field(..., min_length=1)
    post: str = Field(..., min_length=1)
    weight: int = Field(...)


class PynqOverlayQuantisationContract(BaseModel):
    """Quantisation metadata embedded in ``overlay_config.json``."""

    model_config = ConfigDict(frozen=True)

    bits: int = Field(..., gt=0)
    scale_factor: float = Field(..., gt=0)

    @field_validator("bits")
    @classmethod
    def validate_bits(cls, value: int) -> int:
        if value not in SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError(f"bits must be one of {SUPPORTED_WEIGHT_BIT_WIDTHS} for overlay-v2")
        return value


class PynqOverlayConfigArtifactContract(BaseModel):
    """Validated contents of an exported ``overlay_config.json``."""

    model_config = ConfigDict(frozen=True)

    network_name: str = Field(..., min_length=1)
    populations: list[PynqOverlayPopulationContract] = Field(..., min_length=1)
    connections: list[PynqOverlayConnectionContract] = Field(default_factory=list)
    quantisation: PynqOverlayQuantisationContract
    overlay_id: str = Field(default=PYNQ_OVERLAY_ID, min_length=1)
    overlay_version: str = Field(default=PYNQ_OVERLAY_VERSION, min_length=1)

    @model_validator(mode="after")
    def validate_overlay_contract(self) -> PynqOverlayConfigArtifactContract:
        total_neurons = sum(pop.n_neurons for pop in self.populations)
        if total_neurons > MAX_NEURONS:
            raise ValueError(
                f"Total neurons ({total_neurons}) exceeds overlay-v2 max ({MAX_NEURONS})"
            )

        total_synapses = len(self.connections)
        max_synapses = max_synapses_for_bit_width(self.quantisation.bits)
        if total_synapses > max_synapses:
            raise ValueError(
                f"Total synapses ({total_synapses}) exceeds overlay-v2 max "
                f"({max_synapses}) at {self.quantisation.bits}-bit weights"
            )

        if len(self.populations) > MAX_POPULATIONS:
            raise ValueError(f"Overlay-v2 supports at most {MAX_POPULATIONS} populations")

        if self.overlay_id != PYNQ_OVERLAY_ID:
            raise ValueError(f"overlay_id must be '{PYNQ_OVERLAY_ID}'")
        if self.overlay_version != PYNQ_OVERLAY_VERSION:
            raise ValueError(f"overlay_version must be '{PYNQ_OVERLAY_VERSION}'")

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
        return self


class PynqCompileArtifactContract(BaseModel):
    """Contract view of an exported NeuroCNL PYNQ artifact ZIP."""

    model_config = ConfigDict(frozen=True)

    target_device: str = Field(default="PYNQ-Z2")
    overlay_manifest: PynqOverlayManifestContract
    overlay_config: PynqOverlayConfigArtifactContract
    register_map: PynqRegisterMapContract
    weight_bit_width: int = Field(..., gt=0)
    weights_checksum_sha256: str = Field(..., pattern=r"^[a-fA-F0-9]{64}$")
    manifest_checksum_sha256: str = Field(..., pattern=r"^[a-fA-F0-9]{64}$")
    total_neurons: int = Field(..., gt=0)
    total_synapses: int = Field(..., ge=0)

    @model_validator(mode="after")
    def validate_target(self) -> PynqCompileArtifactContract:
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


def validate_pynq_compile_artifact(
    zip_source: str | Path | bytes | BytesIO,
) -> PynqCompileArtifactContract:
    """Validate a NeuroCNL-exported PYNQ artifact ZIP before compilation."""
    if isinstance(zip_source, (str, Path)):
        artifact_path = Path(zip_source)
        if not artifact_path.exists():
            raise FileNotFoundError(f"Artifact not found: {artifact_path}")
        handle: Path | BytesIO = artifact_path
    elif isinstance(zip_source, bytes):
        handle = BytesIO(zip_source)
    else:
        handle = zip_source

    with zipfile.ZipFile(handle, "r") as archive:
        namelist = set(archive.namelist())
        missing = [filename for filename in REQUIRED_ARTIFACT_FILES if filename not in namelist]
        if missing:
            raise ValueError(f"Artifact ZIP is missing required files: {', '.join(missing)}")

        overlay_manifest_raw = json.loads(
            archive.read("pynq_deploy/overlay_manifest.json").decode("utf-8")
        )
        overlay_manifest = PynqOverlayManifestContract.model_validate(overlay_manifest_raw)

        overlay_config_raw = json.loads(
            archive.read("pynq_deploy/overlay_config.json").decode("utf-8")
        )
        overlay_config = PynqOverlayConfigArtifactContract.model_validate(overlay_config_raw)

        register_map_raw = json.loads(archive.read("pynq_deploy/register_map.json").decode("utf-8"))
        register_map = PynqRegisterMapContract.model_validate(register_map_raw)

        manifest_raw = json.loads(archive.read("pynq_deploy/manifest.json").decode("utf-8"))
        manifest_checksum = str(manifest_raw.get("checksum_sha256", ""))

        weights_data = archive.read("pynq_deploy/weights.bin")
        weights_checksum = hashlib.sha256(weights_data).hexdigest()

        total_neurons = sum(pop.n_neurons for pop in overlay_config.populations)
        total_synapses = len(overlay_config.connections)

        return PynqCompileArtifactContract(
            target_device=str(manifest_raw.get("target_device", "PYNQ-Z2")),
            overlay_manifest=overlay_manifest,
            overlay_config=overlay_config,
            register_map=register_map,
            weight_bit_width=overlay_config.quantisation.bits,
            weights_checksum_sha256=weights_checksum,
            manifest_checksum_sha256=manifest_checksum,
            total_neurons=total_neurons,
            total_synapses=total_synapses,
        )
