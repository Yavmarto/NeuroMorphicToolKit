"""Pydantic models for server-side workspace persistence."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class WorkspaceSyncRequest(BaseModel):
    name: str
    config: dict[str, Any]


class WorkspaceSummary(BaseModel):
    slug: str
    name: str
    updated_at: str


class WorkspaceDetail(BaseModel):
    slug: str
    name: str
    config: dict[str, Any]
    updated_at: str


class WorkspaceSummaryList(BaseModel):
    items: list[WorkspaceSummary]
