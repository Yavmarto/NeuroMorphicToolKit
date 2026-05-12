from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field


class ToolStatus(StrEnum):
    ok = "ok"
    error = "error"
    needs_attention = "needs_attention"
    preflight_failed = "preflight_failed"
    degraded_optional_capability = "degraded_optional_capability"


class ArtifactRef(BaseModel):
    kind: str
    uri: str | None = None
    path: str | None = None
    title: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class NextAction(BaseModel):
    action: str
    label: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)


class ToolResult(BaseModel):
    status: str
    summary: str
    details: dict[str, Any] = Field(default_factory=dict)
    artifacts: list[ArtifactRef] = Field(default_factory=list)
    next_actions: list[NextAction] = Field(default_factory=list)
