from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

DetectedChipType = Literal["akida", "speck", "teensy"]


class DetectedHardwareEntry(BaseModel):
    """One piece of hardware discovered by a local scan.

    Returned by ``GET /hardware/detected``. ``already_registered`` reports
    whether the same physical device is already known to the saved-target
    store, so launchers can auto-register only the unregistered hits.

    PYNQ and SpiNNaker2 are intentionally absent: both are network-attached
    hardware with no local-scan surface, so they are never represented here.
    """

    model_config = ConfigDict(frozen=True)

    chip_type: DetectedChipType
    display_name: str = Field(..., description="Operator-facing device label.")
    identifier: str = Field(..., description="Stable device identifier (serial/USB/port).")
    already_registered: bool = Field(
        default=False, description="True when the device is already a saved target."
    )


class HardwareProfile(BaseModel):
    """
    Contract for hardware profiles defining core counts, memory, and clock speeds.
    """

    model_config = ConfigDict(extra="allow")

    id: str
    name: str
    manufacturer: str
    description: str
    core_count: int = Field(
        ..., ge=1, le=128, description="Number of cores, must be between 1 and 128."
    )
    neuron_capacity: int = Field(..., ge=1)
    synapse_capacity: int | None = Field(default=None, ge=1)
    max_populations: int | None = Field(default=None, ge=1)
    overlay_id: str | None = None
    overlay_version: str | None = None
    supported_neuron_models: list[str] = Field(..., min_length=1)
    weight_bit_widths: list[int] = Field(..., min_length=1)
    on_chip_memory_kb: int = Field(
        ..., ge=1, le=16384, description="On-chip memory in KB, must be between 1KB and 16MB."
    )
    io_pins: int = Field(..., ge=0)
    clock_speed_mhz: float = Field(
        ..., ge=1.0, le=1000.0, description="Clock speed in MHz, must be between 1MHz and 1GHz."
    )
    power_envelope_mw: float = Field(
        ..., ge=0, description="Power envelope in mW, must be non-negative."
    )
    pj_per_spike_op: float = Field(
        ..., ge=0, description="Energy per spike operation in pJ, must be non-negative."
    )
    access: str
    notes: str

    @model_validator(mode="after")
    def validate_memory_fit(self) -> "HardwareProfile":
        """
        Enforce invariant: neuron_capacity * 6 bytes <= on_chip_memory_kb * 1024.
        Each neuron requires at least 6 bytes of state memory on-chip.
        """
        required_bytes = self.neuron_capacity * 6
        available_bytes = self.on_chip_memory_kb * 1024
        if required_bytes > available_bytes:
            raise ValueError(
                f"Memory fit violation: {self.neuron_capacity} neurons require "
                f"{required_bytes} bytes, but only {available_bytes} bytes available."
            )
        return self

    @model_validator(mode="after")
    def validate_bit_widths(self) -> "HardwareProfile":
        """
        Enforce invariant: weight_bit_widths must contain only positive integers.
        """
        if any(bw <= 0 for bw in self.weight_bit_widths):
            raise ValueError("All weight bit-widths must be positive integers.")
        return self
