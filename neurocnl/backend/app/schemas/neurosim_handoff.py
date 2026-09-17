"""Schemas for the NeuroSim handoff endpoint."""

from pydantic import BaseModel, Field


class NeurosimHandoffRequest(BaseModel):
    spec: str = Field(..., description="Raw NeuroCNL spec text")


class NeurosimCanvasNode(BaseModel):
    id: str
    component_id: str
    nir_type: str | None = None
    label: str | None = None
    parameters: dict[str, object]
    position: tuple[float, float]
    width: float = 150.0
    height: float = 132.0
    is_visible: bool = True
    metadata: dict[str, object] = Field(default_factory=dict)


class NeurosimCanvasEdge(BaseModel):
    id: str
    source_node_id: str
    source_port: str
    target_node_id: str
    target_port: str
    parameters: dict[str, object]


class NeurosimCanvasGraph(BaseModel):
    nodes: list[NeurosimCanvasNode]
    edges: list[NeurosimCanvasEdge]
    metadata: dict[str, object] = Field(default_factory=dict)


class NeurosimImportContract(BaseModel):
    payload_type: str = Field(
        default="neurocnl_import_contract",
        description="Discriminator for canonical NeuroCNL -> NeuroSim imports",
    )
    payload_version: str = Field(default="2026-04-29")
    source_module: str = Field(default="neurocnl")
    semantics_mode: str = Field(default="canonical_import")
    cnl_spec: str = Field(
        ...,
        description="NeuroSim-compatible topology CNL with appended semantic hints",
    )
    graph: NeurosimCanvasGraph
    warnings: list[str] = Field(default_factory=list)


class NeurosimHandoffResponse(BaseModel):
    import_contract: NeurosimImportContract
