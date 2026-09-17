from typing import Literal

from pydantic import BaseModel, Field


class ConstraintRejection(BaseModel):
    field: str
    limit: int
    actual: int
    code: str
    hint: str


class ConstraintReport(BaseModel):
    target_id: str
    network_neurons: int
    target_capacity: int
    neuron_fit: Literal["pass", "warn", "fail"]
    weight_bit_width_required: int
    quantization_needed: bool
    memory_usage_kb: float
    memory_available_kb: float
    memory_fit: Literal["pass", "warn", "fail"]
    unsupported_features: list[str]
    warnings: list[str]
    recommendations: list[str]
    rejections: list[ConstraintRejection] = Field(default_factory=list)
