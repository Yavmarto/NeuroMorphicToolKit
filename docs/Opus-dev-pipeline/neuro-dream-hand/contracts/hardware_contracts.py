"""Domain contracts for Neuro-Dream-Hand hardware integration.

Converts SPEC.md Phase 4 (HITL) and Phase 5 (Chip Deployment)
into enforceable contracts.

Sources:
- Neuro-Dream-Hand/SPEC.md Sections 4.1-4.6, 5.1-5.4
- OpenBCI Ganglion Technical Reference
- Teensy 4.0 USB Serial Specification
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


# === Phase 4: HITL Contracts ===


class SerialBridgeContract(BaseModel):
    """Contract for Teensy serial bridge protocol (SPEC 4.1).

    Command frame: [0x55][grip_u16_hi][grip_u16_lo][checksum][0xAA] (5 bytes)
    Sensor frame: [0x55][timestamp_ms u32][force_raw u16][checksum][0xAA] (10 bytes)
    """

    model_config = ConfigDict(frozen=True)

    grip_value: float
    baud_rate: int = 1_000_000
    dt: float = 0.002  # Must match Nengo dt

    @field_validator("grip_value")
    @classmethod
    def grip_in_actuator_range(cls, v: float) -> float:
        if v < 0.0 or v > 1.0:
            raise ValueError(
                f"Grip {v} outside actuator range [0.0, 1.0]. "
                "Maps to uint16 [0, 65535] for Teensy servo."
            )
        return v

    @field_validator("baud_rate")
    @classmethod
    def supported_baud(cls, v: int) -> int:
        if v not in {115200, 500_000, 1_000_000}:
            raise ValueError(
                f"Baud rate {v} not tested. Use 115200, 500000, or 1000000."
            )
        return v

    @field_validator("dt")
    @classmethod
    def matches_nengo_dt(cls, v: float) -> float:
        if v != 0.002:
            raise ValueError(
                f"dt={v} does not match Nengo simulation dt=0.002. "
                "Mismatched dt causes timing drift in HITL loop."
            )
        return v


class SensorFrameContract(BaseModel):
    """Contract for sensor data from Teensy (SPEC 4.1)."""

    model_config = ConfigDict(frozen=True)

    timestamp_ms: int
    force_raw: int  # 12-bit ADC [0, 4095]
    force_N: float
    slip_vz: float

    @field_validator("force_raw")
    @classmethod
    def adc_12bit_range(cls, v: int) -> int:
        if v < 0 or v > 4095:
            raise ValueError(
                f"force_raw={v} outside 12-bit ADC range [0, 4095]."
            )
        return v


class EMGStreamContract(BaseModel):
    """Contract for EMG data from OpenBCI Ganglion (SPEC 4.3-4.4).

    Ganglion: 4 channels, 200 Hz, Bluetooth/USB dongle.
    """

    model_config = ConfigDict(frozen=True)

    n_channels: int = 4
    sample_rate_hz: int = 200
    bandpass_low_hz: float = 20.0
    bandpass_high_hz: float = 90.0  # Ganglion limit ~100 Hz
    envelope_cutoff_hz: float = 5.0
    window_samples: int = 200  # 1 second at 200 Hz
    n_encoding_neurons: int = 100

    @field_validator("n_channels")
    @classmethod
    def ganglion_channels(cls, v: int) -> int:
        if v < 1 or v > 4:
            raise ValueError(
                f"Ganglion supports 1-4 channels, got {v}."
            )
        return v

    @field_validator("bandpass_high_hz")
    @classmethod
    def within_nyquist(cls, v: float) -> float:
        # Ganglion at 200 Hz → Nyquist = 100 Hz
        if v > 100.0:
            raise ValueError(
                f"High cutoff {v} Hz exceeds Ganglion Nyquist (100 Hz)."
            )
        return v


class EMGSpikeOutputContract(BaseModel):
    """Contract for EMG spike encoder output (SPEC 4.4)."""

    model_config = ConfigDict(frozen=True)

    value: float

    @field_validator("value")
    @classmethod
    def normalized_range(cls, v: float) -> float:
        if v < 0.0 or v > 1.0:
            raise ValueError(
                f"EMG spike output {v} outside [0, 1]. "
                "Must track voluntary grip-relax cycles."
            )
        return v


class HITLLatencyContract(BaseModel):
    """Contract for HITL latency requirements (SPEC 4.5)."""

    model_config = ConfigDict(frozen=True)

    median_roundtrip_ms: float
    p95_ms: float

    @field_validator("median_roundtrip_ms")
    @classmethod
    def under_4ms_median(cls, v: float) -> float:
        if v > 4.0:
            raise ValueError(
                f"Median round-trip {v}ms exceeds SPEC requirement of <4ms "
                "at 500 Hz on Teensy 4.0 USB Serial 1 Mbaud."
            )
        return v

    @field_validator("p95_ms")
    @classmethod
    def under_2ms_p95(cls, v: float) -> float:
        if v > 2.0:
            raise ValueError(
                f"p95 latency {v}ms exceeds SPEC requirement of <2ms."
            )
        return v


# === Phase 5: Chip Deployment Contracts ===


class FaultInjectionContract(BaseModel):
    """Contract for fault injection (SPEC 5.1).

    Fault injector must return copies, never mutate in place.
    """

    model_config = ConfigDict(frozen=True)

    dead_neuron_fraction: float = 0.0
    stuck_at_fraction: float = 0.0
    weight_noise_sigma: float = 0.0

    @field_validator("dead_neuron_fraction", "stuck_at_fraction")
    @classmethod
    def fraction_range(cls, v: float) -> float:
        if v < 0.0 or v > 0.30:
            raise ValueError(
                f"Fault fraction {v} outside range [0.0, 0.30]. "
                "SPEC limits fault injection to 30% maximum."
            )
        return v

    @field_validator("weight_noise_sigma")
    @classmethod
    def reasonable_noise(cls, v: float) -> float:
        if v < 0.0 or v > 0.30:
            raise ValueError(
                f"Weight noise sigma {v} outside range [0.0, 0.30]."
            )
        return v


class CrossbarExportContract(BaseModel):
    """Contract for crossbar weight-to-conductance mapping (SPEC 5.3).

    Conductance range [g_min, g_max] with linear normalization.
    Output as HDF5 with conductances, original weights, and metadata.
    """

    model_config = ConfigDict(frozen=True)

    g_min: float = 1e-9   # 1 nS minimum conductance
    g_max: float = 1e-6   # 1 uS maximum conductance

    @model_validator(mode="after")
    def valid_conductance_range(self) -> CrossbarExportContract:
        if self.g_min >= self.g_max:
            raise ValueError(
                f"g_min ({self.g_min}) must be < g_max ({self.g_max})."
            )
        if self.g_min <= 0:
            raise ValueError(
                f"g_min ({self.g_min}) must be > 0 (physical conductance)."
            )
        return self


class DropTestContract(BaseModel):
    """Contract for drop-test validation (SPEC 4.6).

    Defines acceptance criteria for sim-to-real gap analysis.
    """

    model_config = ConfigDict(frozen=True)

    n_trials: int = 20
    perturbation_force_duration_s: float = 0.2
    perturbation_time_s: float = 2.0
    base_grip: float = 0.6
    sim_survival_rate: float  # from simulation
    real_survival_rate: float  # from hardware
    max_gap_pct_points: float = 15.0

    @model_validator(mode="after")
    def sim_to_real_gap_acceptable(self) -> DropTestContract:
        gap = abs(self.sim_survival_rate - self.real_survival_rate)
        if gap > self.max_gap_pct_points:
            raise ValueError(
                f"Sim-to-real gap {gap:.1f} percentage points exceeds "
                f"maximum allowed {self.max_gap_pct_points}. "
                f"Sim: {self.sim_survival_rate}%, Real: {self.real_survival_rate}%."
            )
        return self
