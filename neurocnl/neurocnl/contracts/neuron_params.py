"""Pydantic contracts for LIF neuron parameters and physical invariants."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class LIFNeuronContract(BaseModel):
    """Contract for Leaky Integrate-and-Fire (LIF) neuron parameters."""

    model_config = ConfigDict(extra="allow")

    threshold: float = Field(..., description="Firing threshold")
    resting_potential: float = Field(..., description="Resting membrane potential")
    refractory_period: float = Field(..., gt=0, description="Refractory period in seconds")
    tau: float = Field(..., gt=0, description="Membrane time constant in seconds")
    reset_potential: float = Field(..., description="Reset potential after firing")
    current_voltage: float | None = Field(None, description="Current membrane voltage")
    adaptation_tau: float | None = Field(
        default=None, gt=0, description="Adaptation time constant in seconds"
    )

    @model_validator(mode="after")
    def validate_invariants(self) -> "LIFNeuronContract":
        """Validate physical invariants for LIF neurons."""
        # 1. Threshold must be greater than resting potential
        if self.threshold <= self.resting_potential:
            raise ValueError(
                f"threshold ({self.threshold}) must be greater than "
                f"resting_potential ({self.resting_potential})"
            )

        # 4. Reset potential must be less than or equal to threshold
        if self.reset_potential > self.threshold:
            raise ValueError(
                f"reset_potential ({self.reset_potential}) must be less than or "
                f"equal to threshold ({self.threshold})"
            )

        # 5. Membrane potential must decay toward resting potential
        v = (
            self.current_voltage
            if self.current_voltage is not None
            else self.resting_potential + 0.1
        )
        dv_dt = (self.resting_potential - v) / self.tau
        if v > self.resting_potential and not dv_dt < 0:
            raise ValueError("Membrane potential does not decay toward rest (v > rest)")
        if v < self.resting_potential and not dv_dt > 0:
            raise ValueError("Membrane potential does not decay toward rest (v < rest)")

        return self


class SynapticContract(BaseModel):
    """Contract for synaptic connection parameters."""

    model_config = ConfigDict(extra="allow")

    synaptic_weight: float = Field(default=1.0, description="Base synaptic weight")
    inhibitory_weight: float | None = Field(
        default=None, description="Inhibitory weight (must be <= 0)"
    )
    axonal_delay: float | None = Field(default=None, ge=0, description="Axonal delay in seconds")
    max_axonal_delay: float = Field(default=0.150, description="Maximum allowed axonal delay")

    @field_validator("inhibitory_weight")
    @classmethod
    def validate_inhibitory(cls, v: float | None) -> float | None:
        """9. Inhibitory connection weight must be negative (or zero)."""
        if v is not None and v > 0:
            raise ValueError(f"inhibitory_weight ({v}) must be negative or zero")
        return v

    @model_validator(mode="after")
    def validate_delay(self) -> "SynapticContract":
        """6. Axonal/synaptic transmission delay must be non-negative and bounded."""
        if self.axonal_delay is not None:
            if self.axonal_delay > self.max_axonal_delay:
                raise ValueError(
                    f"axonal_delay ({self.axonal_delay}) exceeds "
                    f"max_axonal_delay ({self.max_axonal_delay})"
                )
        return self


class STDPContract(BaseModel):
    """Contract for Spike-Timing Dependent Plasticity (STDP) parameters."""

    model_config = ConfigDict(extra="allow")

    stdp_window: float | None = Field(
        default=None, gt=0, description="STDP timing window in seconds"
    )
    max_stdp_window: float = Field(default=0.100, description="Maximum allowed STDP window")
    stdp_weight_min: float | None = Field(default=None, ge=0, description="Minimum synaptic weight")
    stdp_weight_max: float | None = Field(default=None, description="Maximum synaptic weight")
    learning_rate: float | None = Field(default=None, gt=0, description="Learning rate")
    learning_rule_type: Literal["PES", "BCM", "OJA", "STDP"] | None = Field(
        default=None, description="Learning rule type"
    )

    @model_validator(mode="after")
    def validate_stdp(self) -> "STDPContract":
        """7. STDP window positive and 8. Weight bounds valid."""
        if self.stdp_window is not None:
            if self.stdp_window > self.max_stdp_window:
                raise ValueError(
                    f"stdp_window ({self.stdp_window}) exceeds "
                    f"max_stdp_window ({self.max_stdp_window})"
                )

        if self.stdp_weight_min is not None and self.stdp_weight_max is not None:
            if self.stdp_weight_min >= self.stdp_weight_max:
                raise ValueError(
                    f"stdp_weight_min ({self.stdp_weight_min}) must be less than "
                    f"stdp_weight_max ({self.stdp_weight_max})"
                )

        return self


class PopulationContract(BaseModel):
    """Contract for neural population (ensemble) parameters."""

    model_config = ConfigDict(extra="allow")

    population_n_neurons: int = Field(
        ..., gt=0, le=10000, description="Number of neurons in population"
    )
    population_dimensions: int = Field(..., gt=0, description="Dimensionality of representation")
    population_radius: float = Field(..., gt=0, description="Representation radius")
    lateral_inhibition_radius: float | None = Field(
        default=None, gt=0, description="Inhibition radius"
    )
    homeostatic_target_rate: float | None = Field(
        default=None, gt=0, description="Target firing rate"
    )
    neuromodulation_factor: float | None = Field(
        default=None, gt=0, description="Neuromodulation factor"
    )
    population_coding_range: float | None = Field(default=None, gt=0, description="Coding range")

    @model_validator(mode="after")
    def validate_population(self) -> "PopulationContract":
        """Validate population parameters."""
        # The following are implicitly covered by Field(gt=0) constraints:
        # 10. population_neuron_count_positive
        # 11. population_dimensions_positive
        # 12. population_radius_positive
        # 15. lateral_inhibition_radius_positive
        # 16. homeostatic_target_rate_positive
        # 17. neuromodulation_factor_positive
        # 18. population_coding_range_positive

        # 13. learning_rate_positive (implicit gt=0)
        # 14. learning_rule_valid (implicit Literal check)

        # Explicitly check for consistency if needed (currently all are independent gt=0)
        if self.population_n_neurons <= 0:
            raise ValueError("population_n_neurons must be positive")
        if self.population_dimensions <= 0:
            raise ValueError("population_dimensions must be positive")
        if self.population_radius <= 0:
            raise ValueError("population_radius must be positive")

        return self
