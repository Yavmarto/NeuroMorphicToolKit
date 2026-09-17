from typing import Any

from pydantic import BaseModel, Field


class MessageResponse(BaseModel):
    """Generic status/message payload."""

    status: str
    message: str | None = None


class PynqDeployResponse(MessageResponse):
    """Structured PYNQ deploy result payload."""

    runtime_mode: str
    preflight_status: str | None = None
    overlay_version: str | None = None


class SessionStatusResponse(BaseModel):
    """Session lifecycle response."""

    status: str
    session_id: str


class PortInfo(BaseModel):
    """Serial port metadata exposed by the API."""

    port: str
    description: str
    hwid: str
    is_teensy: bool


class FlashVerificationReport(BaseModel):
    """Opaque verification report stored after a flash completes."""

    model_config = {"extra": "allow"}


class FlashJobResponse(BaseModel):
    """Flash job status returned to the frontend."""

    job_id: str
    status: str
    progress_pct: int
    message: str
    error: str | None = None
    verification_report: FlashVerificationReport | dict[str, Any] | None = None


class PynqRunResponse(BaseModel):
    """PYNQ inference result payload."""

    status: str
    output_spikes: list[int] = Field(default_factory=list)
    execution_time_ms: float | None = None
    latency_ms: float | None = None
    power_mw: float | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)

    model_config = {"extra": "allow"}


class CompiledNetworkResponse(BaseModel):
    """Compiled network wrapper for hardware backends."""

    status: str
    compiled_network: dict[str, Any] | list[Any] | str | int | float | bool | None = None


class HardwareRunResults(BaseModel):
    """Structured execution results from a hardware backend."""

    status: str
    spikes: dict[str, list[int]] = Field(default_factory=dict)
    voltages: dict[str, Any] = Field(default_factory=dict)
    emulation: bool | None = None
    execution_time_ms: float | None = None


class HardwareRunResponse(BaseModel):
    """Wrapper around backend execution results."""

    status: str
    results: HardwareRunResults


class PartitionCompareResponse(BaseModel):
    """Placeholder analysis response surfaced to the frontend."""

    status: str = "placeholder"
    message: str
    hint: str | None = None


# ---------------------------------------------------------------------------
# Partition result schemas
# ---------------------------------------------------------------------------


class PartitionShard(BaseModel):
    """One chip's worth of a partitioned network."""

    id: int
    population_names: list[str]
    neuron_count: int
    synapse_count: int
    inter_partition_connections: int


class PartitionPlanResponse(BaseModel):
    """A single partitioning strategy and its predicted cost."""

    strategy: str
    num_partitions: int
    partitions: list[PartitionShard]
    total_inter_partition_synapses: int
    estimated_latency_overhead_pct: float
    support_level: str = "heuristic"
    is_estimate: bool = True


class PartitionResult(BaseModel):
    """Full response for ``POST /api/neurochip/partition``."""

    status: str
    target_id: str
    target_capacity: int
    network_fits_single_chip: bool
    suggestions: list[PartitionPlanResponse]
    message: str | None = None
