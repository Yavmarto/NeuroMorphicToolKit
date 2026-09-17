from pydantic import BaseModel, Field


class DisplayLatencyContract(BaseModel):
    """Contract for display latency from acquisition to screen."""

    latency_ms: float = Field(..., lt=50, description="Display latency must be less than 50ms")


class PipelineLatencyContract(BaseModel):
    """Contract for end-to-end pipeline latency from acquisition to SNN output."""

    latency_ms: float = Field(..., lt=100, description="Pipeline latency must be less than 100ms")
