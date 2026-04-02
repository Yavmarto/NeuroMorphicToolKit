"""Domain contracts for hardware export targets.

Each contract encodes the physical constraints of a specific
neuromorphic hardware platform. The agent's export code must
produce outputs that satisfy these contracts.

Sources:
- Intel Loihi 2 Programming Guide, Chapter 4
- SpiNNaker Architecture Reference Manual
- BrainChip Akida Developer Guide
- Teensy 4.1 Technical Reference
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class LoihiExportContract(BaseModel):
    """Contract for Intel Loihi 2 hardware export.

    Loihi uses 8-bit signed integer weights, up to 1024 compartments
    per neurocore, and programmable delays of 0-62 timesteps.
    """

    model_config = ConfigDict(frozen=True)

    weight: float
    n_neurons: int
    axonal_delay: float = 0.0
    max_weight: float = 10.0
    max_neurons_per_core: int = 1024
    max_delay: float = 0.062  # 62ms at 1ms timestep

    @field_validator("weight")
    @classmethod
    def weight_quantizable(cls, v: float) -> float:
        # Loihi maps to 8-bit signed integer [-256, 254]
        # We validate raw weight is within scalable range
        if abs(v) > 10.0:
            raise ValueError(
                f"Weight {v} exceeds Loihi quantization range. "
                f"Max abs weight: 10.0 (maps to 8-bit [-256, 254])."
            )
        return v

    @field_validator("n_neurons")
    @classmethod
    def fits_in_neurocore(cls, v: int) -> int:
        if v < 1 or v > 1024:
            raise ValueError(
                f"Neuron count {v} outside Loihi 2 neurocore range [1, 1024]."
            )
        return v

    @model_validator(mode="after")
    def delay_in_hardware_range(self) -> LoihiExportContract:
        if self.axonal_delay < 0 or self.axonal_delay > self.max_delay:
            raise ValueError(
                f"Delay {self.axonal_delay}s outside Loihi range "
                f"[0, {self.max_delay}s] (0-62 timesteps at 1ms)."
            )
        return self


class SpiNNakerExportContract(BaseModel):
    """Contract for SpiNNaker hardware export.

    SpiNNaker uses fixed-point arithmetic (s16.15 format),
    up to 255 neurons per core, and multicast packet routing.
    """

    model_config = ConfigDict(frozen=True)

    weight: float
    n_neurons: int
    max_neurons_per_core: int = 255

    @field_validator("weight")
    @classmethod
    def within_fixed_point_range(cls, v: float) -> float:
        # s16.15 format: range approx [-65536, 65535.99997]
        if abs(v) > 65536:
            raise ValueError(
                f"Weight {v} exceeds SpiNNaker s16.15 range [-65536, 65535]."
            )
        return v

    @field_validator("n_neurons")
    @classmethod
    def fits_in_core(cls, v: int) -> int:
        if v < 1 or v > 255:
            raise ValueError(f"Neuron count {v} outside SpiNNaker range [1, 255].")
        return v


class TeensyExportContract(BaseModel):
    """Contract for Teensy 4.1 C header export.

    Teensy 4.1 has 1MB RAM, 600MHz ARM Cortex-M7.
    Network must fit in available SRAM.
    """

    model_config = ConfigDict(frozen=True)

    n_neurons: int
    n_connections: int
    weight_bit_width: int = 8
    max_ram_bytes: int = 1_048_576  # 1MB

    @model_validator(mode="after")
    def fits_in_memory(self) -> TeensyExportContract:
        # Estimate: each neuron ~32 bytes state, each connection ~4 bytes
        estimated_bytes = (self.n_neurons * 32) + (
            self.n_connections * (self.weight_bit_width // 8)
        )
        if estimated_bytes > self.max_ram_bytes:
            raise ValueError(
                f"Estimated memory {estimated_bytes} bytes exceeds "
                f"Teensy 4.1 RAM ({self.max_ram_bytes} bytes). "
                f"Neurons: {self.n_neurons}, Connections: {self.n_connections}."
            )
        return self

    @field_validator("weight_bit_width")
    @classmethod
    def valid_bit_width(cls, v: int) -> int:
        if v not in {4, 8, 16, 32}:
            raise ValueError(
                f"Bit width {v} not supported on Teensy. Use 4, 8, 16, or 32."
            )
        return v


class CHeaderContract(BaseModel):
    """Contract for C header export format.

    Validates that generated C code has required sections.
    """

    model_config = ConfigDict(frozen=True)

    has_include_guard: bool
    has_neuron_params: bool
    has_weight_array: bool
    has_topology_array: bool
    neuron_count: int
    connection_count: int

    @model_validator(mode="after")
    def all_sections_present(self) -> CHeaderContract:
        missing = []
        if not self.has_include_guard:
            missing.append("include guard")
        if not self.has_neuron_params:
            missing.append("neuron parameters struct")
        if not self.has_weight_array:
            missing.append("weight array")
        if not self.has_topology_array:
            missing.append("topology/connection array")
        if missing:
            raise ValueError(
                f"C header missing required sections: {', '.join(missing)}"
            )
        return self
