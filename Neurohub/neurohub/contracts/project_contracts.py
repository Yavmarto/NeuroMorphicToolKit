"""Pydantic contracts for projects in NeuroHub (artifact-sharing focus)."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ProjectMember(BaseModel):
    """Contract for a project member (legacy ACL on project record)."""

    user_id: str
    name: str
    role: Literal["admin", "engineer", "viewer"]


class ProjectLinks(BaseModel):
    """Contract for links to related objects in suite apps."""

    neurosim_project_id: str | None = None
    neurochip_target_id: str | None = None
    neurochip_deployment_ids: list[str] = []
    neurobench_benchmark_ids: list[str] = []
    neurobench_baseline_ids: list[str] = []
    neurosense_session_ids: list[str] = []
    cnl_spec_hash: str | None = None


class Project(BaseModel):
    """Contract for a NeuroHub project (grouping metadata for shared artefacts)."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    description: str
    created_at: str  # ISO 8601
    updated_at: str
    owner: str  # User ID
    members: list[ProjectMember] = Field(default_factory=list)
    links: ProjectLinks = Field(default_factory=ProjectLinks)
    status: Literal["not_started", "in_progress", "complete", "archived"] = "not_started"
    tags: list[str] = Field(default_factory=list)

    @field_validator("name")
    @classmethod
    def name_must_not_be_empty(cls, v: str) -> str:
        """Validate that name is not empty."""
        if not v.strip():
            raise ValueError("Project name cannot be empty")
        return v


class ProjectConfig(BaseModel):
    """Contract for project configuration (used during creation)."""

    name: str
    owner: str
    module_list: list[str]

    @field_validator("name")
    @classmethod
    def name_must_not_be_empty(cls, v: str) -> str:
        """Validate that name is not empty."""
        if not v.strip():
            raise ValueError("Project name cannot be empty")
        return v

    @field_validator("owner")
    @classmethod
    def owner_must_not_be_empty(cls, v: str) -> str:
        """Validate that owner is not empty."""
        if not v.strip():
            raise ValueError("Project owner cannot be empty")
        return v

    @field_validator("module_list")
    @classmethod
    def modules_must_be_valid(cls, v: list[str]) -> list[str]:
        """Validate that all modules are valid suite apps."""
        valid_modules = {"neurosim", "neurochip", "neurobench", "neurosense", "neurocnl"}
        for module in v:
            if module not in valid_modules:
                raise ValueError(f"Invalid module reference: {module}")
        return v
