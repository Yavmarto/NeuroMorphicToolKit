"""Pydantic models for prosthetic endpoints."""

from typing import Any, Literal

from pydantic import BaseModel, Field

# --- TASK-16: Drop Test Simulation ---


class ProstheticSimRequest(BaseModel):
    spec: str
    gripper_type: Literal["pinch", "tripod"] = "pinch"
    drop_height: float = 0.15
    duration: float = 2.0
    n_neurons: int = 50
    use_sleep_weights: bool = False
    seed: int = 0


class ProstheticSimResult(BaseModel):
    success: bool
    grip_history: list[float]
    slip_vz_history: list[float]
    object_z_history: list[float]
    stopping_distance_m: float
    frames: list[str] | None = None
    wall_time_seconds: float


# --- TASK-17: Sleep Training ---


class SleepTrainRequest(BaseModel):
    spec: str
    memory_buffer: list[dict[str, Any]] = Field(
        ..., description="List of {slip_vz, grip, error} dicts"
    )
    n_epochs: int = 10
    homeostasis_factor: float = 0.01


class SleepTrainResult(BaseModel):
    loss_curve: list[float]
    n_epochs: int
    final_loss: float
    learned_weights: list[list[float]]


# --- TASK-18: Crossbar Export ---


class CrossbarExportRequest(BaseModel):
    learned_weights: list[list[float]]
    bit_width: int = 8
    format: Literal["hdf5", "json"] = "json"


class CrossbarExportResult(BaseModel):
    quantized_weights: list[list[float]]
    bit_width: int
    scale_factor: float
    zero_point: float
    sparsity: float


# --- TASK-19: Energy / Quantization / Hardware ---


class EnergyRequest(BaseModel):
    spec: str
    n_neurons: int = 50
    duration: float = 1.0


class EnergyResult(BaseModel):
    per_ensemble_pj: dict[str, float]
    total_pj: float
    avg_power_uw: float


class QuantizeRequest(BaseModel):
    spec: str
    bit_widths: list[int] = Field(default=[4, 6, 8])


class QuantizeResult(BaseModel):
    bit_widths: list[int]
    accuracy_drops: list[float]
    sparsity: list[float]


class FaultInjectionRequest(BaseModel):
    spec: str
    error_rate: float = Field(default=0.1, ge=0.0, le=1.0)


class FaultInjectionResult(BaseModel):
    error_rate: float
    baseline_accuracy: float
    degraded_accuracy: float
    failed_nodes: list[str] = Field(default_factory=list)
    resilience_score: float


class HardwareConnectRequest(BaseModel):
    port: str
    baud_rate: int = 115200


class SensorFrame(BaseModel):
    timestamp: float
    emg_channels: list[float] = Field(default_factory=list)
    proximity: float = 0.0
    tactile: float = 0.0


class NeuroSenseReplayRequest(BaseModel):
    artifact_path: str
    start_time_seconds: float | None = None
    end_time_seconds: float | None = None
    preview_frames: int = Field(default=5, ge=1, le=50)


class NeuroSenseReplayResult(BaseModel):
    session_id: str
    artifact_path: str
    artifact_schema_version: str
    device_type: str
    signal_type: str
    capture_mode: str
    support_level: str
    channels: int
    sampling_rate_hz: float
    frame_count: int
    preview_frames: list[dict[str, Any]]
    spike_batch_count: int
    spike_event_count: int
