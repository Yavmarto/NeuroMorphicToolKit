from typing import Any

from pydantic import BaseModel, ConfigDict, Field, model_validator


class CanvasNode(BaseModel):
    """A node on the NeuroSim canvas."""

    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str
    component_id: str
    parameters: dict[str, Any]
    position: tuple[float, float]


class CanvasEdge(BaseModel):
    """An edge (connection) on the NeuroSim canvas."""

    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str
    source_node_id: str
    source_port: str
    target_node_id: str
    target_port: str
    parameters: dict[str, Any]


class CanvasGraph(BaseModel):
    """A complete network graph represented on the canvas."""

    model_config = ConfigDict(arbitrary_types_allowed=True)

    nodes: list[CanvasNode]
    edges: list[CanvasEdge]
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_connections(self) -> "CanvasGraph":
        """Ensure all edges reference existing nodes."""
        node_ids = {node.id for node in self.nodes}
        for edge in self.edges:
            if edge.source_node_id not in node_ids:
                raise ValueError(
                    f"Edge {edge.id} references non-existent source node {edge.source_node_id}",
                )
            if edge.target_node_id not in node_ids:
                raise ValueError(
                    f"Edge {edge.id} references non-existent target node {edge.target_node_id}",
                )
        return self
