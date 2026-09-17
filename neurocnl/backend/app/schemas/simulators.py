"""Pydantic schemas for the shared CNL → NIR → Simulator contract.

These schemas define the backend-neutral request/response shapes for
GET /api/simulators/capabilities, POST /api/simulators/run,
POST /api/simulators/preflight, and POST /api/simulators/preflight-nir.
Both the Lava and snnTorch simulator backends use these same shapes so
the Studio does not grow two incompatible runtime paths.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, Field


class SimulatorStatus(StrEnum):
    """Final status of a simulator run."""

    completed = "completed"
    failed = "failed"
    unsupported = "unsupported"
    missing_dependency = "missing_dependency"
    preflight_failed = "preflight_failed"


class SupportLevel(StrEnum):
    """How faithfully the simulator executed the NIR graph."""

    exact = "exact"
    approximate = "approximate"
    unsupported = "unsupported"


class StimulusSpec(BaseModel):
    """Explicit spike-train input provided by the caller."""

    type: Literal["spike_train"] = "spike_train"
    population: str = Field(..., description="Name of the NIR Input node to drive.")
    spikes: dict[str, list[int]] = Field(
        ...,
        description="Map of neuron index (string) → list of timesteps at which it fires.",
    )


class SimulatorCapability(BaseModel):
    """Availability and NIR support profile for one simulator backend."""

    backend_name: str
    display_name: str
    available: bool
    unavailable_reason: str | None = None
    supported_nir_nodes: list[str] = Field(default_factory=list)
    unsupported_nir_nodes: list[str] = Field(default_factory=list)
    approximate_semantics: list[str] = Field(default_factory=list)
    max_timesteps: int = 1000
    supports_spike_output: bool = True
    supports_voltage_trace: bool = False
    requires_optional_dependency: str | None = None


class SimulatorRunRequest(BaseModel):
    """Request body for POST /api/simulators/run."""

    spec: str = Field(..., description="CNL specification text to compile and run.")
    backend_name: str = Field(
        ...,
        description="Simulator backend identifier, e.g. 'lava_sim' or 'snntorch_sim'.",
    )
    timesteps: int = Field(
        100, ge=1, le=10_000, description="Number of simulation timesteps."
    )
    seed: int = Field(
        1,
        description=(
            "Random seed. Controls default stimulus generation (when no explicit stimulus "
            "is provided). Both simulator backends apply this seed internally, but simulation "
            "dynamics are deterministic for fixed graph weights — only the generated input "
            "spike train changes between seeds."
        ),
    )
    dt_ms: float = Field(
        1.0,
        ge=0.1,
        le=100.0,
        description=(
            "Display-only: milliseconds per step used to label the raster's time "
            "axis. This is NOT the timestep the neuron dynamics are integrated "
            "at — that comes from the graph (CNL 'with timestep', or the canvas "
            "Network Settings field) and is resolved by "
            "neurocnl.lif_semantics.resolve_dt. Do not wire this value into any "
            "adapter: a second, disagreeing timestep is exactly the bug that "
            "made one network behave differently on every backend."
        ),
    )
    firing_rate: float = Field(
        0.3,
        ge=0.01,
        le=1.0,
        description="Poisson firing probability per neuron per timestep for the default stimulus.",
    )
    trained_nir_base64: str | None = Field(
        default=None,
        description=(
            "Optional base64 `.nir` graph carrying trained weights, from "
            "GET /notebook/artifacts/latest-trained-nir. Without it the weights "
            "come from the CNL spec, which stores tensor shape only — so they are "
            "all zeros and no neuron can reach threshold."
        ),
    )
    stimulus: StimulusSpec | None = Field(
        None,
        description=(
            "Explicit spike-train stimulus.  When None a deterministic default stimulus "
            "is generated from seed and timesteps."
        ),
    )


class SimulatorNIRSummary(BaseModel):
    """Compact summary of the compiled NIR graph included in every run result."""

    node_count: int
    edge_count: int
    unsupported_nodes: list[str] = Field(default_factory=list)


class SimulatorStimulusRecord(BaseModel):
    """The spike train that actually drove this run, explicit or generated.

    The Studio can only tell a silent network apart from a silent *input* if it
    can see what went in, and until now the run result carried the output raster
    but not the input that produced it.  ``spikes`` deliberately mirrors one
    population of :attr:`SimulatorRunResult.spikes` — neuron index (as a string)
    → firing timesteps — so the existing raster parser and painter render it
    without a second code path.
    """

    population: str
    neuron_count: int
    generated: bool = Field(
        ...,
        description="False when the caller supplied the stimulus explicitly.",
    )
    truncated: bool = Field(
        False,
        description=(
            "True when whole neurons were dropped from `spikes` to keep the "
            "response transportable. The neurons that remain are complete."
        ),
    )
    spikes: dict[str, list[int]] = Field(
        default_factory=dict,
        description="neuron_index_str → [timestep, ...]",
    )


class SimulatorRunResult(BaseModel):
    """Response body for POST /api/simulators/run.

    Both Lava and snnTorch backends return this shape.  Backend-specific
    details are placed in ``metadata`` so the Studio can render a unified view
    without branching on backend name.
    """

    backend_name: str
    status: SimulatorStatus
    support_level: SupportLevel
    timesteps: int
    duration_seconds: float
    spikes: dict[str, dict[str, list[int]]] = Field(
        default_factory=dict,
        description="population_name → {neuron_index_str → [timestep, ...]}}",
    )
    voltages: dict[str, dict[str, list[float]]] = Field(
        default_factory=dict,
        description="population_name → {neuron_index_str → [voltage, ...]}",
    )
    warnings: list[str] = Field(default_factory=list)
    nir_summary: SimulatorNIRSummary
    stimulus: SimulatorStimulusRecord | None = Field(
        default=None,
        description=(
            "The spike train the run was actually driven with, so an empty "
            "output raster can be told apart from an empty input. Null when "
            "the result was built without one."
        ),
    )
    trained_weights: dict[str, Any] | None = Field(
        default=None,
        description=(
            "Where the simulated network's weights came from. `applied` false "
            "means they are the spec's zeros, so an empty raster is expected "
            "rather than a result. Null when no trained NIR was supplied."
        ),
    )
    metadata: dict[str, object] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Preflight schemas
# ---------------------------------------------------------------------------


class PreflightRequest(BaseModel):
    """Request body for POST /api/simulators/preflight."""

    spec: str = Field(
        ..., description="CNL specification text to compile and classify."
    )
    backend_name: str = Field(
        ..., description="Simulator backend identifier: 'lava_sim' or 'snntorch_sim'."
    )


class PreflightResult(BaseModel):
    """Response body for both preflight endpoints.

    Shared by POST /api/simulators/preflight and POST /api/simulators/preflight-nir.
    """

    level: Literal["exact", "approximate", "unsupported"] = Field(
        ..., description="Overall NIR support classification for the backend."
    )
    supported_nodes: list[str] = Field(
        default_factory=list,
        description="NIR node type names that are exactly supported.",
    )
    approximate_nodes: list[str] = Field(
        default_factory=list,
        description="NIR node type names executed with approximate semantics.",
    )
    unsupported_nodes: list[str] = Field(
        default_factory=list,
        description="NIR node type names that cannot be executed.",
    )
    diagnostics: list[str] = Field(
        default_factory=list,
        description="Human-readable messages for approximate and unsupported nodes.",
    )
