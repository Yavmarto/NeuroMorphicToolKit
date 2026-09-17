"""Pydantic schemas for project notes in NeuroHub."""

from pydantic import BaseModel, ConfigDict


class NoteCreate(BaseModel):
    """Schema for creating a new project note."""

    author: str
    content: str
    asset_id: str | None = None


class Note(BaseModel):
    """Schema for a project note."""

    model_config = ConfigDict(from_attributes=True)

    id: str
    project_id: str
    asset_id: str | None = None
    author: str
    content: str
    created_at: str
