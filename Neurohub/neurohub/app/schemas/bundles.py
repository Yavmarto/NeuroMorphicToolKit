"""Pydantic schemas for project export/import bundles."""

from pydantic import BaseModel, Field

from neurohub.app.schemas.projects import Project


class ProjectBundle(BaseModel):
    """Schema for a project export/import bundle (project metadata only)."""

    version: int = 2
    project: Project
    # Deprecated v1 fields — accepted on import but ignored.
    milestones: list[dict[str, object]] = Field(default_factory=list)
    notes: list[dict[str, object]] = Field(default_factory=list)
    workflow_runs: list[dict[str, object]] = Field(default_factory=list)
