from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

MAX_PREVIEW_DURATION_MS = 500.0
MAX_SWEEP_STEPS = 20


# --- Component Models ---
class PortDef(BaseModel):
    """Definition of a component port."""

    id: str  # noqa: A003
    direction: Literal["input", "output"]
    label: str


class ParameterDef(BaseModel):
    """Definition of a component parameter."""

    name: str
    label: str
    description: str
    type: Literal["float", "int", "bool", "enum", "text"]  # noqa: A003
    default: float | int | bool | str | None
    min: float | None = None  # noqa: A003
    max: float | None = None  # noqa: A003
    unit: str | None = None
    enum_values: list[str] | None = None


class ComponentBlock(BaseModel):
    """A reusable network component block."""

    id: str  # noqa: A003
    name: str
    category: str
    description: str
    icon: str
    parameters: list[ParameterDef]
    ports: list[PortDef]
    cnl_template: str
    is_custom: bool = False
    canvas_contexts: list[str] = Field(default_factory=list)
    supported_frameworks: list[str] = Field(default_factory=list)
    author: str = ""
    version: str = "1.0.0"
    source_path: str | None = Field(default=None, exclude=True)
    source_filename: str | None = None
    # Every registered built-in can generate source; loaded custom nodes
    # override this based on whether their managed source file is present.
    source_available: bool = True
    base_component_id: str | None = None
    base_nir_type: str | None = None
    base_pipeline_type: str | None = None


# --- Canvas Models ---
class CanvasNode(BaseModel):
    """A node on the NeuroSim canvas."""

    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str  # noqa: A003
    component_id: str
    nir_type: str | None = None
    label: str | None = None
    parameters: dict[str, Any]
    position: tuple[float, float]
    width: float = 150.0
    height: float = 132.0
    is_visible: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class CanvasEdge(BaseModel):
    """An edge (connection) on the NeuroSim canvas."""

    model_config = ConfigDict(arbitrary_types_allowed=True)

    id: str  # noqa: A003
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
                    f"Edge {edge.id} references non-existent source node '{edge.source_node_id}'",
                )
            if edge.target_node_id not in node_ids:
                raise ValueError(
                    f"Edge {edge.id} references non-existent target node '{edge.target_node_id}'",
                )
        return self


class SimulationStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ValidationError(BaseModel):
    """Details of a single validation error."""

    element_id: str
    field: str
    message: str
    severity: Literal["error", "warning"] = "error"


class ValidationResult(BaseModel):
    """Result of a graph validation."""

    valid: bool
    errors: list[ValidationError] = Field(default_factory=list)
    backend_support: "BackendSupport | None" = None
    generator_fidelity: "GeneratorFidelitySummary | None" = None


class CnlRequest(BaseModel):
    graph: CanvasGraph


class CnlResponse(BaseModel):
    cnl_spec: str


# --- Project Models ---
class ProjectSummary(BaseModel):
    """Summary information for a NeuroSim project."""

    id: str  # noqa: A003
    name: str
    description: str = ""
    updated_at: str


class Project(ProjectSummary):
    """A complete NeuroSim project."""

    graph: CanvasGraph
    cnl_spec: str = ""

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:  # noqa: ANN102
        if not v or not v.strip():
            raise ValueError("Project name cannot be empty")
        return v


class CreateProjectRequest(BaseModel):
    """Request to create a new project."""

    name: str
    description: str = ""
    graph: CanvasGraph

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:  # noqa: ANN102
        if not v or not v.strip():
            raise ValueError("Project name cannot be empty")
        return v


# --- Simulation & Preview Models ---
MAX_PREVIEW_DURATION_MS = 500.0
MAX_SWEEP_STEPS = 20


class PreviewRequest(BaseModel):
    """Request for a real-time simulation preview."""

    graph: CanvasGraph
    duration_ms: float = MAX_PREVIEW_DURATION_MS

    @field_validator("duration_ms")
    @classmethod
    def limit_duration(cls, v: float) -> float:  # noqa: ANN102
        """Enforce maximum preview duration."""
        if v <= 0:
            raise ValueError("Preview duration must be positive")
        if v > MAX_PREVIEW_DURATION_MS:
            raise ValueError("Preview duration cannot exceed 500ms")
        return v


class PreviewSpikeEvent(BaseModel):
    """A spike emitted by a single neuron at a specific simulation time."""

    node_id: str
    neuron_id: str
    neuron_index: int
    time_ms: float


class PreviewEdgeEvent(BaseModel):
    """A derived propagation event for one outgoing connection."""

    source_node_id: str
    target_node_id: str
    weight: float
    delay_ms: float
    time_ms: float


class PreviewNodePlayback(BaseModel):
    """Preview playback data for one canvas node."""

    node_id: str
    spike_trains: dict[str, list[float]] = Field(default_factory=dict)
    voltage_traces: dict[str, list[float]] = Field(default_factory=dict)
    spike_count: int = 0


class PreviewPlaybackSummary(BaseModel):
    """Small summary block for quick UI stats."""

    total_spikes: int = 0
    active_node_count: int = 0
    edge_event_count: int = 0


class NodeBulkData(BaseModel):
    """Per-node compact spike payload within a bulk (large-network) frame.

    `data` holds local-to-this-node alternating [local_neuron_idx, time_ms]
    pairs — local_neuron_idx is 0-based within this node's ensemble, NOT a
    global index across the network. Length is always even.
    `density_grid` is this node's own firing-rate heatmap, flattened
    row-major over (grid_h, grid_w), normalised to [0.0, 1.0].
    """

    data: list[float] = Field(default_factory=list)
    density_grid: list[float] = Field(default_factory=list)
    grid_w: int = 0
    grid_h: int = 0
    neuron_count: int = 0


class BulkSpikeFrame(BaseModel):
    """Compact, node-partitioned spike payload for large-scale simulations
    (n > 5 000 neurons across the whole network).

    Keyed by CanvasNode.id. Each value's data/density_grid cover only that
    node's neurons — node identity is preserved, unlike a flat whole-network
    encoding. scale_hint is derived once from the network-wide total and
    applies to every node's renderer selection.
    """

    nodes: dict[str, NodeBulkData] = Field(default_factory=dict)
    scale_hint: Literal["raster", "particle", "density"] = "raster"


class PreviewPlayback(BaseModel):
    """Structured playback payload shared by HTTP polling and WebSockets."""

    duration_ms: float
    sample_count: int = 0
    nodes: list[PreviewNodePlayback] = Field(default_factory=list)
    spike_events: list[PreviewSpikeEvent] = Field(default_factory=list)
    edge_events: list[PreviewEdgeEvent] = Field(default_factory=list)
    summary: PreviewPlaybackSummary = Field(default_factory=PreviewPlaybackSummary)
    bulk_spike_frame: BulkSpikeFrame | None = None  # populated for n > 5 000


class PreviewResponse(BaseModel):
    """Result of a simulation preview."""

    job_id: str | None = None
    status: SimulationStatus
    error: str | None = None
    results: dict[str, Any] | None = None
    playback: PreviewPlayback | None = None
    metrics: dict[str, Any] | None = None
    backend_support: "BackendSupport | None" = None
    generator_fidelity: "GeneratorFidelitySummary | None" = None


class SpinnakerResponse(PreviewResponse):
    """Result of a SpiNNaker2 simulation request."""

    backend_type: Literal["hardware", "mock", "unavailable"]
    error: str | None = None
    results: dict[str, Any] | None = None


# --- Sweep Models ---
class SweepRequest(BaseModel):
    """Request for a parameter sweep."""

    graph: CanvasGraph
    parameter_path: str
    start: float
    end: float
    steps: int
    simulation_duration_ms: float = MAX_PREVIEW_DURATION_MS

    @field_validator("steps")
    @classmethod
    def limit_steps(cls, v: int) -> int:  # noqa: ANN102
        """Enforce maximum sweep steps."""
        if v <= 0:
            raise ValueError("Sweep steps must be positive")
        if v > MAX_SWEEP_STEPS:
            raise ValueError(f"Sweep steps cannot exceed {MAX_SWEEP_STEPS}")
        return v

    @model_validator(mode="after")
    def validate_range(self) -> "SweepRequest":
        if self.start >= self.end:
            raise ValueError("start must be strictly less than end")
        return self


class SweepStepResult(BaseModel):
    """Result of a single step in a parameter sweep."""

    parameter_value: float
    result: PreviewResponse


class SweepResponse(BaseModel):
    """Full results of a parameter sweep."""

    job_id: str | None = None
    status: SimulationStatus
    error: str | None = None
    parameter_path: str
    steps: list[SweepStepResult] | None = None
    backend_support: "BackendSupport | None" = None
    generator_fidelity: "GeneratorFidelitySummary | None" = None


# --- Export Models ---
class CanvasExportRequest(BaseModel):
    """Request to export the canvas graph to another format."""

    format: Literal["cnl", "python", "c", "neuroml", "svg", "nir"]  # noqa: A003
    graph: CanvasGraph


# --- CNL Sync Models ---
class NeuroCnlImportContract(BaseModel):
    """Typed NeuroCNL-owned import payload for canonical NeuroSim semantics."""

    payload_type: Literal["neurocnl_import_contract"] = "neurocnl_import_contract"
    payload_version: Literal["2026-04-29"] = "2026-04-29"
    source_module: Literal["neurocnl"] = "neurocnl"
    semantics_mode: Literal["canonical_import"] = "canonical_import"
    cnl_spec: str
    graph: CanvasGraph
    warnings: list[str] = Field(default_factory=list)


class CnlSyncRequest(BaseModel):
    """Payload for canvas sync from canonical import or explicit repair."""

    cnl_spec: str | None = None
    graph: CanvasGraph | None = None
    import_contract: NeuroCnlImportContract | None = None
    import_mode: Literal["repair", "canonical"] | None = None

    @model_validator(mode="after")
    def validate_request(self) -> "CnlSyncRequest":
        if self.import_contract is not None:
            if self.cnl_spec:
                raise ValueError(
                    "Canonical import payloads must use 'import_contract' instead of raw 'cnl_spec'.",
                )
            if self.import_mode is not None:
                raise ValueError(
                    "Canonical import payloads must not set 'import_mode'.",
                )
            return self

        if not self.cnl_spec and not self.graph:
            raise ValueError(
                "Provide either 'import_contract' or raw 'cnl_spec' with import_mode='repair'.",
            )

        if self.cnl_spec and self.import_mode not in (None, "repair", "canonical"):
            raise ValueError("Raw 'cnl_spec' sync uses an unsupported import_mode.")
        return self


class CnlSyncResponse(BaseModel):
    """Response after CNL synchronization operation."""

    cnl_spec: str
    graph: CanvasGraph
    errors: list[str] = Field(default_factory=list)


class BackendSupport(BaseModel):
    """Stable summary of backend support planning and Neurosim fallback behavior."""

    backend: str
    verdict: str
    supported_concepts: list[str] = Field(default_factory=list)
    approximated_concepts: list[str] = Field(default_factory=list)
    unsupported_concepts: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class GeneratorFidelityAnnotation(BaseModel):
    """Single generator fidelity annotation from NeuroCNL."""

    concept: str
    subject: str
    fidelity: str
    reason: str


class GeneratorFidelitySummary(BaseModel):
    """Generator fidelity metadata surfaced by Neurosim APIs."""

    annotations: list[GeneratorFidelityAnnotation] = Field(default_factory=list)


ValidationResult.model_rebuild()
PreviewResponse.model_rebuild()
SweepResponse.model_rebuild()
