"""Pydantic schemas for multi-app workflows in NeuroHub."""

from typing import Any, Literal

from pydantic import BaseModel

from neurohub.contracts.workflow_contracts import WorkflowStep, WorkflowTemplate

# Re-exporting contracts for consistency
__all__ = ["WorkflowStep", "WorkflowTemplate", "WorkflowStepResult", "WorkflowRun"]


class WorkflowStepResult(BaseModel):
    """Schema for the result of a single workflow step execution."""

    step_id: str
    step_name: str
    status: Literal["pending", "running", "passed", "failed", "skipped"]
    started_at: str | None = None
    completed_at: str | None = None
    duration_seconds: float | None = None
    output_summary: str | None = None  # Human-readable result
    error: str | None = None
    result_data: dict[str, Any] | None = None  # Full API response for downstream steps


class WorkflowRun(BaseModel):
    """Schema for a specific execution of a workflow template."""

    id: str
    workflow_id: str
    project_id: str
    started_at: str
    completed_at: str | None = None
    heartbeat: str | None = None
    status: Literal["pending", "running", "completed", "failed", "cancelled"]
    steps: list[WorkflowStepResult]
