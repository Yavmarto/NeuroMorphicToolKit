"""Pydantic models for the /api/generate endpoint."""

from typing import Any

from pydantic import BaseModel, Field


class NodePosition(BaseModel):
    x: float
    y: float


class NetworkNode(BaseModel):
    id: str
    type: str
    label: str
    params: dict[str, Any] = Field(default_factory=dict)
    position: NodePosition | None = None


class NetworkEdge(BaseModel):
    id: str
    source: str
    target: str
    params: dict[str, Any] = Field(default_factory=dict)


class NetworkGraph(BaseModel):
    nodes: list[NetworkNode]
    edges: list[NetworkEdge]


class GenerateRequest(BaseModel):
    spec: str
    params: dict[str, Any] = Field(default_factory=dict)


class GenerateResponse(BaseModel):
    network: NetworkGraph
    cnl_document: str
    nir_code: str
