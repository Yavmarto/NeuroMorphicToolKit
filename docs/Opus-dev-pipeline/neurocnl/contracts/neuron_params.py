"""Domain contracts for neurocnl neuron parameters.

Converts the 18 Layer 1 invariants from layer1_invariants.py into
self-validating Pydantic models. These contracts replace dict-based
parameter passing with typed, physics-enforced models.

Source: NeuroML iafTauCell / iafTauRefCell specification.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class LIFNeuronContract(BaseModel):
    """Contract for Leaky Integrate-and-Fire neuron parameters.

    Every field maps to a NeuroML parameter. Any violation means
    the parameter set is physically impossible.
    """

    model_config = ConfigDict(frozen=True)

    threshold: float
    resting_potential: float
    reset_potential: float
    refractory_period: float
    tau: float
    current_voltage: float | None = None

    @field_validator("refractory_period")
    @classmethod
    def refractory_must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(
                f"Refractory period {v}s is non-physical (must be > 0). "
                "NeuroML: refract > 0. A zero refractory period means "
                "infinite spike frequency."
            )
        return v

    @field_validator("tau")
    @classmethod
    def tau_must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(
                f"Time constant tau={v}s is non-physical (must be > 0). "
                "NeuroML: tau > 0. Non-positive tau produces undefined "
                "or divergent membrane dynamics."
            )
        return v

    @model_validator(mode="after")
    def threshold_above_resting(self) -> LIFNeuronContract:
        if self.threshold <= self.resting_potential:
            raise ValueError(
                f"Threshold ({self.threshold}) must exceed resting potential "
                f"({self.resting_potential}). NeuroML: thresh > leakReversal. "
                "A neuron at or above threshold at rest fires continuously."
            )
        return self

    @model_validator(mode="after")
    def reset_at_or_below_threshold(self) -> LIFNeuronContract:
        if self.reset_potential > self.threshold:
            raise ValueError(
                f"Reset potential ({self.reset_potential}) must be <= threshold "
                f"({self.threshold}). Resetting above threshold creates an "
                "infinite-frequency firing loop."
            )
        return self

    @model_validator(mode="after")
    def membrane_decays_toward_rest(self) -> LIFNeuronContract:
        if self.current_voltage is not None and self.tau > 0:
            v = self.current_voltage
            rest = self.resting_potential
            dv_dt = (rest - v) / self.tau
            if v > rest and dv_dt >= 0:
                raise ValueError(
                    f"Voltage {v} above rest {rest} must decay (dv/dt < 0), "
                    f"got dv/dt={dv_dt}"
                )
            if v < rest and dv_dt <= 0:
                raise ValueError(
                    f"Voltage {v} below rest {rest} must increase (dv/dt > 0), "
                    f"got dv/dt={dv_dt}"
                )
        return self


class SynapticContract(BaseModel):
    """Contract for synaptic connection parameters."""

    model_config = ConfigDict(frozen=True)

    weight: float
    is_inhibitory: bool = False
    axonal_delay: float | None = None
    max_axonal_delay: float = 0.150  # 150ms biological max

    @model_validator(mode="after")
    def inhibitory_weight_must_be_negative(self) -> SynapticContract:
        if self.is_inhibitory and self.weight > 0:
            raise ValueError(
                f"Inhibitory weight must be <= 0, got {self.weight}. "
                "Positive inhibitory weights are biologically impossible."
            )
        return self

    @model_validator(mode="after")
    def delay_in_biological_range(self) -> SynapticContract:
        if self.axonal_delay is not None:
            if self.axonal_delay < 0:
                raise ValueError(
                    f"Axonal delay {self.axonal_delay}s is negative (non-physical)."
                )
            if self.axonal_delay > self.max_axonal_delay:
                raise ValueError(
                    f"Axonal delay {self.axonal_delay}s exceeds biological "
                    f"maximum {self.max_axonal_delay}s (longest peripheral nerve)."
                )
        return self


class STDPContract(BaseModel):
    """Contract for Spike-Timing-Dependent Plasticity parameters.

    Source: Bi & Poo (1998), NeuroML STDP specification.
    """

    model_config = ConfigDict(frozen=True)

    learning_rate: float
    stdp_window: float | None = None  # seconds
    weight_min: float = 0.0
    weight_max: float = 10.0
    rule_type: str = "PES"

    @field_validator("learning_rate")
    @classmethod
    def positive_lr(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"Learning rate must be positive, got {v}")
        return v

    @field_validator("stdp_window")
    @classmethod
    def biologically_plausible_window(cls, v: float | None) -> float | None:
        if v is not None and (v <= 0 or v > 0.100):
            raise ValueError(
                f"STDP window {v}s outside biological range (0, 100ms]. "
                "Typical STDP windows are 10-100ms."
            )
        return v

    @field_validator("rule_type")
    @classmethod
    def valid_rule_type(cls, v: str) -> str:
        valid = {"PES", "BCM", "OJA", "STDP"}
        if v.upper() not in valid:
            raise ValueError(f"Learning rule '{v}' not in {valid}")
        return v.upper()

    @model_validator(mode="after")
    def valid_weight_range(self) -> STDPContract:
        if self.weight_min >= self.weight_max:
            raise ValueError(
                f"weight_min ({self.weight_min}) must be < "
                f"weight_max ({self.weight_max})"
            )
        return self


class PopulationContract(BaseModel):
    """Contract for neuron population / ensemble parameters."""

    model_config = ConfigDict(frozen=True)

    n_neurons: int
    dimensions: int = 1
    radius: float = 1.0

    @field_validator("n_neurons")
    @classmethod
    def positive_count(cls, v: int) -> int:
        if v < 1:
            raise ValueError(f"Population must have >= 1 neuron, got {v}")
        return v

    @field_validator("dimensions")
    @classmethod
    def positive_dims(cls, v: int) -> int:
        if v < 1:
            raise ValueError(f"Dimensions must be >= 1, got {v}")
        return v

    @field_validator("radius")
    @classmethod
    def positive_radius(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"Radius must be > 0, got {v}")
        return v
