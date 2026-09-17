"""Typed contracts for the canonical editor document.

The canonical editor document owns semantic truth inside the Studio.
CNL text and canvas graph state are derived projections of this document.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class NodeLayout(BaseModel):
    """Canvas position for a single population node."""

    node_id: str
    x: float = 0.0
    y: float = 0.0


class FidelityAnnotation(BaseModel):
    """Structured annotation for non-executable or unsupported semantics.

    ``kind`` values:
    - ``"executable"``  — semantic lowers faithfully to NIR
    - ``"advisory"``    — semantic is metadata-only, not executable
    - ``"unsupported"`` — semantic cannot be represented; canvas editing blocked
    """

    kind: Literal["executable", "advisory", "unsupported"]
    concept: str
    message: str
    affects: list[str] = Field(default_factory=list)


class CanvasProjection(BaseModel):
    """Minimal canvas view derived from the canonical document."""

    nodes: list[dict[str, Any]] = Field(default_factory=list)
    edges: list[dict[str, Any]] = Field(default_factory=list)
    read_only_annotations: list[FidelityAnnotation] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)


class CanonicalEditorDocument(BaseModel):
    """The single source of truth for Studio editor state.

    ``ir_json`` is the output of ``neurocnl.cnl.document.serialize_ir(ir)``
    and round-trips via ``deserialize_ir(ir_json)`` without loss.
    """

    ir_json: dict[str, Any]
    layout: list[NodeLayout] = Field(default_factory=list)
    fidelity_annotations: list[FidelityAnnotation] = Field(default_factory=list)
    cnl_text: str = ""
    canvas: CanvasProjection | None = None


class CanvasNodeMutation(BaseModel):
    """A typed canvas edit that updates one population node's parameters."""

    node_id: str
    threshold: float | None = None
    membrane_time_constant: float | None = None
    weight_to: dict[str, float] = Field(
        default_factory=dict,
        description="target_node_id -> new_scalar_weight",
    )


class ParseCnlRequest(BaseModel):
    spec_text: str


class ParseCnlResponse(BaseModel):
    document: CanonicalEditorDocument
    diagnostics: list[str] = Field(default_factory=list)
