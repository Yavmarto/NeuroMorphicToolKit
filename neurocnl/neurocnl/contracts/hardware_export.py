"""Pydantic contracts for hardware-specific export constraints.

LoihiExportContract and TeensyExportContract were removed 2026-07-04 as dead
code — both were only used by layer1_validator.validate()'s hardware-backend
branches, which had no live caller (see
current tasks/2026-07-04/validation-deploy-readiness/audit.md).
"""

from pydantic import BaseModel, ConfigDict, Field, model_validator


class SpiNNakerExportContract(BaseModel):
    """Contract for SpiNNaker hardware export constraints."""

    model_config = ConfigDict(extra="allow")

    timestep: float = Field(1.0, ge=0.1, description="SpiNNaker simulation timestep in ms")
    v_thresh: float = Field(-50.0, description="Firing threshold in mV")
    v_reset: float = Field(-65.0, description="Reset potential in mV")
    v_rest: float = Field(-65.0, description="Resting potential in mV")

    @model_validator(mode="after")
    def validate_spinnaker_constraints(self) -> "SpiNNakerExportContract":
        """Validate SpiNNaker-specific invariants."""
        if self.v_thresh <= self.v_rest:
            raise ValueError(f"v_thresh ({self.v_thresh}) must be > v_rest ({self.v_rest})")
        return self
