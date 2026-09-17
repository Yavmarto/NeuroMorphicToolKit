"""GET /api/simulators/capabilities and POST /api/simulators/run.

This module implements the backend-neutral simulator contract defined in
``docs/current tasks/2026-05-14-cnl-nir-simulator-contract-plan.md``.

Both the Lava and snnTorch simulator backends return the same response shape
so the Studio can render a unified simulation panel without branching on
backend name.

Notes
-----
- Missing optional dependencies (``lava``, ``snntorch``) never crash the
  base NeuroCNL startup.  They are detected via ``importlib.util.find_spec``
  and surfaced as ``available=False`` in the capability response or as a
  structured 503 diagnostic in the run endpoint.
- The old ``POST /api/simulate`` endpoint (410 Gone) is preserved unchanged.
- T1-6: full Lava simulator dispatch wired.
- T1-7: full snnTorch simulator dispatch wired.
"""

from __future__ import annotations

import base64
import binascii
import tempfile
from pathlib import Path
from typing import Annotated

import nir
import structlog
from fastapi import APIRouter, File, Form, HTTPException, Request, Response, UploadFile

from backend.app.middleware.rate_limit import limiter
from backend.app.schemas.simulators import (
    PreflightRequest,
    PreflightResult,
    SimulatorCapability,
    SimulatorNIRSummary,
    SimulatorRunRequest,
    SimulatorRunResult,
    SimulatorStatus,
    SimulatorStimulusRecord,
    SupportLevel,
)
from backend.app.services.pynq_trained_weights import (
    TrainedWeightError,
    apply_trained_weights_to_graph,
    graph_is_all_zero,
    load_trained_nir_graph,
)
from backend.app.utils.cnl_errors import (
    build_backend_failure_detail,
    build_validation_failure_detail,
)
from neurocnl import CompileError, compile_to_nir
from neurocnl.lif_semantics import unreachable_threshold_warnings
from neurocnl.runtime.nir_support import (
    classify_nir_graph,
    get_supported_node_types,
    list_simulator_backends,
)
from neurocnl.runtime.stimulus import (
    StimulusError,
    ValidatedStimulus,
    generate_default_stimulus,
    parse_stimulus,
)
from neurocnl.target_sdk import (
    brian2_available,
    brian2_worker_url,
    lava_available,
    lava_worker_url,
    module_importable,
)

router = APIRouter()
logger = structlog.get_logger(__name__)

# ---------------------------------------------------------------------------
# Capability profiles (static metadata for T1-5)
# ---------------------------------------------------------------------------

_LAVA_SIM_SUPPORT = get_supported_node_types("lava_sim")
_SNNTORCH_SIM_SUPPORT = get_supported_node_types("snntorch_sim")
_SC_NEUROCORE_SIM_SUPPORT = get_supported_node_types("sc_neurocore_sim")
_BRIAN2_SIM_SUPPORT = get_supported_node_types("brian2_sim")
_NENGO_SIM_SUPPORT = get_supported_node_types("nengo_sim")
_SINABS_SIM_SUPPORT = get_supported_node_types("sinabs_sim")


def _is_available(package_name: str) -> bool:
    """Return True if *package_name* can be imported."""
    return module_importable(package_name)


# A run is allowed 10,000 timesteps (SimulatorRunRequest.timesteps) at a firing
# rate of up to 1.0, so a 784-neuron MNIST input can legitimately produce ~7.8M
# spike entries — roughly 40 MB of JSON, which would stall the Studio for a
# panel that only ever shows a raster. 50,000 entries is about 250 KB, and the
# typical 784-neuron × 100-timestep run at rate 0.3 lands near 23,500, so real
# runs echo in full and only pathological ones are cut back.
_MAX_STIMULUS_SPIKES = 50_000


def _stimulus_record(
    stim: ValidatedStimulus, *, generated: bool
) -> SimulatorStimulusRecord:
    """Mirror the spike train that drove a run back to the caller.

    Stringifies the neuron indices so the record matches one population of
    ``SimulatorRunResult.spikes`` exactly, and caps the payload at
    :data:`_MAX_STIMULUS_SPIKES` entries.

    The cap keeps *whole* neurons, in ascending index order, and drops the rest
    outright. Cutting a neuron's spike list short would draw a real-looking gap
    in the raster — a silent stretch that never happened — so a missing row is
    the only honest way to shed size.
    """
    emitted: dict[str, list[int]] = {}
    remaining = _MAX_STIMULUS_SPIKES
    truncated = False
    for index in sorted(stim.spikes):
        timesteps = stim.spikes[index]
        if len(timesteps) > remaining:
            truncated = True
            break
        emitted[str(index)] = list(timesteps)
        remaining -= len(timesteps)
    return SimulatorStimulusRecord(
        population=stim.population,
        neuron_count=stim.neuron_count,
        generated=generated,
        truncated=truncated,
        spikes=emitted,
    )


def _build_lava_capability() -> SimulatorCapability:
    worker_url = lava_worker_url()
    available = lava_available()
    if available:
        unavailable_reason = None
    elif worker_url is None:
        unavailable_reason = (
            "Lava is not available in this backend deployment. "
            "Use Backend Setup to update or repair the backend, then try again."
        )
    else:
        unavailable_reason = (
            "The configured Lava runtime is not ready. "
            "Use Backend Setup to repair the backend, then try again."
        )
    return SimulatorCapability(
        backend_name="lava_sim",
        display_name="Lava simulator",
        available=available,
        unavailable_reason=unavailable_reason,
        supported_nir_nodes=[n for n, v in _LAVA_SIM_SUPPORT.items() if v == "exact"],
        unsupported_nir_nodes=[
            n for n, v in _LAVA_SIM_SUPPORT.items() if v == "unsupported"
        ],
        approximate_semantics=[
            n for n, v in _LAVA_SIM_SUPPORT.items() if v == "approximate"
        ],
        max_timesteps=1000,
        supports_spike_output=True,
        supports_voltage_trace=False,
        requires_optional_dependency="lava-nc" if not available else None,
    )


def _build_snntorch_capability() -> SimulatorCapability:
    available = _is_available("snntorch") and _is_available("torch")
    unavailable_reason: str | None = None
    if not available:
        if not _is_available("torch"):
            unavailable_reason = (
                "The backend is missing its sNN simulation runtime. "
                "Use Backend Setup to repair the backend, then try again."
            )
        else:
            unavailable_reason = (
                "The backend is missing its sNN simulation runtime. "
                "Use Backend Setup to repair the backend, then try again."
            )
    return SimulatorCapability(
        backend_name="snntorch_sim",
        display_name="snnTorch simulator",
        available=available,
        unavailable_reason=unavailable_reason,
        supported_nir_nodes=[
            n for n, v in _SNNTORCH_SIM_SUPPORT.items() if v == "exact"
        ],
        unsupported_nir_nodes=[
            n for n, v in _SNNTORCH_SIM_SUPPORT.items() if v == "unsupported"
        ],
        approximate_semantics=[
            n for n, v in _SNNTORCH_SIM_SUPPORT.items() if v == "approximate"
        ],
        max_timesteps=1000,
        supports_spike_output=True,
        supports_voltage_trace=False,
        requires_optional_dependency="torch snntorch" if not available else None,
    )


def _build_brian2_capability() -> SimulatorCapability:
    available = brian2_available()
    unavailable_reason: str | None = None
    if not available:
        if brian2_worker_url() is None and not _is_available("brian2"):
            unavailable_reason = (
                "The backend is missing its Brian2 simulation runtime. "
                "Use Backend Setup to repair the backend, then try again."
            )
        else:
            unavailable_reason = (
                "The configured Brian2 runtime is not ready. "
                "Use Backend Setup to repair the backend, then try again."
            )
    return SimulatorCapability(
        backend_name="brian2_sim",
        display_name="Brian2 simulator",
        available=available,
        unavailable_reason=unavailable_reason,
        supported_nir_nodes=[n for n, v in _BRIAN2_SIM_SUPPORT.items() if v == "exact"],
        unsupported_nir_nodes=[
            n for n, v in _BRIAN2_SIM_SUPPORT.items() if v == "unsupported"
        ],
        approximate_semantics=[
            n for n, v in _BRIAN2_SIM_SUPPORT.items() if v == "approximate"
        ],
        max_timesteps=10_000,
        supports_spike_output=True,
        supports_voltage_trace=False,
        requires_optional_dependency="brian2" if not available else None,
    )


def _build_nengo_capability() -> SimulatorCapability:
    available = _is_available("nengo")
    unavailable_reason: str | None = None
    if not available:
        unavailable_reason = (
            "The backend is missing its Nengo simulation runtime. "
            "Use Backend Setup to repair the backend, then try again."
        )
    return SimulatorCapability(
        backend_name="nengo_sim",
        display_name="Nengo simulator",
        available=available,
        unavailable_reason=unavailable_reason,
        supported_nir_nodes=[n for n, v in _NENGO_SIM_SUPPORT.items() if v == "exact"],
        unsupported_nir_nodes=[
            n for n, v in _NENGO_SIM_SUPPORT.items() if v == "unsupported"
        ],
        approximate_semantics=[
            n for n, v in _NENGO_SIM_SUPPORT.items() if v == "approximate"
        ],
        max_timesteps=10_000,
        supports_spike_output=True,
        supports_voltage_trace=True,
        requires_optional_dependency="nengo" if not available else None,
    )


def _build_sinabs_capability() -> SimulatorCapability:
    available = _is_available("sinabs") and _is_available("torch")
    unavailable_reason: str | None = None
    if not available:
        unavailable_reason = (
            "The backend is missing its Sinabs simulation runtime. "
            "Use Backend Setup to repair the backend, then try again."
        )
    return SimulatorCapability(
        backend_name="sinabs_sim",
        display_name="Sinabs simulator",
        available=available,
        unavailable_reason=unavailable_reason,
        supported_nir_nodes=[n for n, v in _SINABS_SIM_SUPPORT.items() if v == "exact"],
        unsupported_nir_nodes=[
            n for n, v in _SINABS_SIM_SUPPORT.items() if v == "unsupported"
        ],
        approximate_semantics=[
            n for n, v in _SINABS_SIM_SUPPORT.items() if v == "approximate"
        ],
        max_timesteps=10_000,
        supports_spike_output=True,
        supports_voltage_trace=False,
        requires_optional_dependency="sinabs torch" if not available else None,
    )


def _build_sc_neurocore_capability() -> SimulatorCapability:
    available = _is_available("sc_neurocore")
    unavailable_reason: str | None = None
    if not available:
        unavailable_reason = (
            "The backend is missing its SC-NeuroCore simulation runtime. "
            "Use Backend Setup to repair the backend, then try again."
        )
    return SimulatorCapability(
        backend_name="sc_neurocore_sim",
        display_name="SC-NeuroCore (Simulation)",
        available=available,
        unavailable_reason=unavailable_reason,
        supported_nir_nodes=[
            n for n, v in _SC_NEUROCORE_SIM_SUPPORT.items() if v == "exact"
        ],
        unsupported_nir_nodes=[
            n for n, v in _SC_NEUROCORE_SIM_SUPPORT.items() if v == "unsupported"
        ],
        approximate_semantics=[
            n for n, v in _SC_NEUROCORE_SIM_SUPPORT.items() if v == "approximate"
        ],
        max_timesteps=10_000,
        supports_spike_output=True,
        supports_voltage_trace=True,
        requires_optional_dependency="sc-neurocore" if not available else None,
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get(
    "/simulators/capabilities",
    response_model=list[SimulatorCapability],
    summary="List simulator backend capabilities",
    tags=["simulators"],
)
@limiter.limit("60/minute")
async def get_simulator_capabilities(
    request: Request, response: Response
) -> list[SimulatorCapability]:
    """Return availability and NIR support profile for each simulator backend.

    The Studio uses this to show preflight status and install hints before
    the user clicks Run.  Missing optional dependencies never cause a 5xx
    error here — they are reflected in the ``available`` flag.
    """
    return [
        _build_lava_capability(),
        _build_snntorch_capability(),
        _build_sc_neurocore_capability(),
        _build_brian2_capability(),
        _build_nengo_capability(),
        _build_sinabs_capability(),
    ]


@router.post(
    "/simulators/preflight",
    response_model=PreflightResult,
    summary="Classify a CNL spec against a simulator backend (no dispatch)",
    tags=["simulators"],
    responses={
        400: {"description": "CNL compilation failed."},
        422: {"description": "Unknown backend name."},
    },
)
@limiter.limit("10/minute")
async def preflight(
    request: Request, response: Response, body: PreflightRequest
) -> PreflightResult:
    """Compile a CNL spec to NIR and classify it against a simulator backend.

    Unlike ``/run``, this endpoint never dispatches to a simulator and never
    checks whether optional simulator dependencies are installed.  It is a
    pure classification step intended to surface compatibility information
    before the user clicks Run.

    Pipeline
    --------
    1. Validate ``backend_name`` ∈ ``{"lava_sim", "snntorch_sim"}`` → 422.
    2. Compile ``spec`` via :func:`neurocnl.compile_to_nir` → 400 on failure.
    3. Classify the graph with :func:`classify_nir_graph` → return result.
    """
    # ── 1. Validate backend name ──────────────────────────────────────────
    _KNOWN_BACKENDS = set(list_simulator_backends())
    if body.backend_name not in _KNOWN_BACKENDS:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Unknown simulator backend {body.backend_name!r}.",
                code="unknown_backend",
            ),
        )

    # ── 2. Compile CNL → NIR ──────────────────────────────────────────────
    try:
        graph = compile_to_nir(body.spec)
    except CompileError as exc:
        items = [
            {
                "code": d.code,
                "message": d.message,
                "line": d.line,
                "raw": d.raw,
                "hint": d.hint,
                "source": d.stage,
            }
            for d in exc.diagnostics
        ]
        raise HTTPException(
            status_code=400,
            detail=build_backend_failure_detail(
                "compile_failed",
                items=items,
                source="compile",
            ),
        ) from exc

    # ── 3. Classify NIR support ───────────────────────────────────────────
    classification = classify_nir_graph(graph, body.backend_name)

    # ── 4. Return result — no simulator dispatch, no dependency check ─────
    return PreflightResult(
        level=classification.level,
        supported_nodes=classification.supported_nodes,
        approximate_nodes=classification.approximate_nodes,
        unsupported_nodes=classification.unsupported_nodes,
        diagnostics=classification.diagnostics,
    )


@router.post(
    "/simulators/run",
    response_model=SimulatorRunResult,
    summary="Compile CNL to NIR and run in a simulator backend",
    tags=["simulators"],
    responses={
        422: {
            "description": "Compilation failed or NIR graph is unsupported by the backend."
        },
        503: {"description": "Required simulator dependency is not installed."},
    },
)
@limiter.limit("10/minute")
async def run_simulation(
    request: Request, response: Response, body: SimulatorRunRequest
) -> SimulatorRunResult:
    """Compile a CNL spec to NIR and dispatch to the requested simulator backend.

    Pipeline
    --------
    1. Compile ``spec`` via :func:`neurocnl.compile_to_nir` (fail → 422).
    2. Classify the NIR graph support level for the backend (fail → 422).
    3. Check optional dependency availability (fail → 503).
    4. Parse or generate a deterministic stimulus.
    5. Dispatch to the simulator backend.
       For T1-5 the dispatch is a preflight stub; full execution is added in
       T1-6 (Lava) and T1-7 (snnTorch).
    6. Return a :class:`SimulatorRunResult`.
    """
    # ── 1: Validate backend name ──────────────────────────────────────────────
    known_backends = set(list_simulator_backends())
    if body.backend_name not in known_backends:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Unknown simulator backend {body.backend_name!r}. "
                f"Known backends: {', '.join(sorted(known_backends))}.",
                code="unknown_backend",
            ),
        )

    # ── 2: Compile CNL → NIR ──────────────────────────────────────────────────
    try:
        graph = compile_to_nir(body.spec)
    except CompileError as exc:
        items = [
            {
                "code": d.code,
                "message": d.message,
                "line": d.line,
                "raw": d.raw,
                "hint": d.hint,
                "source": d.stage,
            }
            for d in exc.diagnostics
        ]
        raise HTTPException(
            status_code=400,
            detail=build_backend_failure_detail(
                "compile_failed",
                items=items,
                source="compile",
            ),
        ) from exc

    # ── 2b: Overlay trained weights, if the caller supplied them ─────────────
    # The spec compiles to shape-only tensors, so without this every weight is
    # 0.0 and the run finishes in milliseconds with an empty raster. Same
    # artifact and the same matching rule the PYNQ deploy path uses.
    trained_weights: dict | None = None
    zero_weight_warning: str | None = None
    if body.trained_nir_base64:
        # Reading the file and matching it to the network are separate failures
        # with separate fixes — a corrupt upload is re-exported, a mismatched one
        # is re-trained — so they must not share an error code.
        try:
            trained_graph = load_trained_nir_graph(
                base64.b64decode(body.trained_nir_base64, validate=True)
            )
        except (binascii.Error, ValueError, TrainedWeightError) as exc:
            raise HTTPException(
                status_code=422,
                detail=build_backend_failure_detail(
                    "invalid_trained_nir",
                    f"The trained network file could not be read: {exc}",
                    source="trained_weights",
                    hint=(
                        "Re-run the training pipeline so the NIR Exporter node "
                        "writes a fresh graph, then try again."
                    ),
                ),
            ) from exc
        try:
            trained_weights = apply_trained_weights_to_graph(
                graph, trained_graph
            ).to_dict()
        except TrainedWeightError as exc:
            raise HTTPException(
                status_code=422,
                detail=build_backend_failure_detail(
                    "trained_nir_mismatch",
                    str(exc),
                    source="trained_weights",
                ),
            ) from exc

    if trained_weights is None and graph_is_all_zero(graph):
        zero_weight_warning = (
            "Every weight in this network is 0.0, so no neuron can reach "
            "threshold and nothing will fire. Add a NIR Exporter node to your "
            "Training canvas and run the pipeline to get trained weights."
        )

    if (
        body.backend_name == "sinabs_sim"
        and trained_weights is None
        and graph_is_all_zero(graph)
    ):
        raise HTTPException(
            status_code=422,
            detail=build_backend_failure_detail(
                "trained_nir_required",
                "Sinabs simulation requires trained weights from a completed training run.",
                source="trained_weights",
                hint=(
                    "Add a NIR Exporter node to your Training canvas, run the "
                    "pipeline, then retry with the exported trained NIR graph."
                ),
            ),
        )

    # ── 3: Classify NIR support ───────────────────────────────────────────────
    classification = classify_nir_graph(graph, body.backend_name)
    if classification.level == "unsupported":
        raise HTTPException(
            status_code=422,
            detail=build_backend_failure_detail(
                "nir_unsupported",
                *classification.diagnostics,
                items=[
                    {"code": "nir_unsupported", "message": msg, "source": "nir_support"}
                    for msg in classification.diagnostics
                ],
                source="nir_support",
                hint=(
                    "Remove or replace the unsupported NIR node types before running. "
                    "Use GET /api/simulators/capabilities to check the supported subset."
                ),
            ),
        )

    # ── 4: Check optional dependency ─────────────────────────────────────────
    if body.backend_name == "lava_sim" and not (
        lava_available() or _is_available("lava")
    ):
        logger.warning(
            "lava_sim_dependency_missing",
            backend="lava_sim",
            reason="missing_dependency",
        )
        raise HTTPException(
            status_code=503,
            detail=build_backend_failure_detail(
                "missing_dependency",
                "Lava is not available in this backend deployment.",
                source="dependency_check",
                hint=(
                    "Use Backend Setup to install or repair the optional Lava runtime, "
                    "then try again."
                ),
            ),
        )
    if body.backend_name == "snntorch_sim" and (
        not _is_available("snntorch") or not _is_available("torch")
    ):
        raise HTTPException(
            status_code=503,
            detail=build_backend_failure_detail(
                "missing_dependency",
                "The backend is missing its sNN simulation runtime.",
                source="dependency_check",
                hint="Use Backend Setup to repair the backend, then try again.",
            ),
        )
    if body.backend_name == "sc_neurocore_sim" and not _is_available("sc_neurocore"):
        raise HTTPException(
            status_code=503,
            detail=build_backend_failure_detail(
                "missing_dependency",
                "The backend is missing its SC-NeuroCore simulation runtime.",
                source="dependency_check",
                hint="Use Backend Setup to repair the backend, then try again.",
            ),
        )
    if body.backend_name == "brian2_sim" and not brian2_available():
        raise HTTPException(
            status_code=503,
            detail=build_backend_failure_detail(
                "missing_dependency",
                "The backend is missing its Brian2 simulation runtime.",
                source="dependency_check",
                hint="Use Backend Setup to repair the backend, then try again.",
            ),
        )
    if body.backend_name == "nengo_sim" and not _is_available("nengo"):
        raise HTTPException(
            status_code=503,
            detail=build_backend_failure_detail(
                "missing_dependency",
                "The backend is missing its Nengo simulation runtime.",
                source="dependency_check",
                hint="Use Backend Setup to repair the backend, then try again.",
            ),
        )
    if body.backend_name == "sinabs_sim" and (
        not _is_available("sinabs") or not _is_available("torch")
    ):
        raise HTTPException(
            status_code=503,
            detail=build_backend_failure_detail(
                "missing_dependency",
                "The backend is missing its Sinabs simulation runtime.",
                source="dependency_check",
                hint="Use Backend Setup to repair the backend, then try again.",
            ),
        )

    # ── 5: Parse or generate stimulus ────────────────────────────────────────
    stimulus_was_generated = body.stimulus is None
    try:
        if body.stimulus is not None:
            validated_stimulus = parse_stimulus(body.stimulus.model_dump(), graph)
        else:
            validated_stimulus = generate_default_stimulus(
                graph, body.timesteps, body.seed, body.firing_rate
            )
    except StimulusError as exc:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                *exc.diagnostics,
                code="invalid_stimulus",
            ),
        ) from exc

    # Built once here rather than at each dispatch site, so all three backends
    # echo the same input and none of them can drift.
    stimulus_record = _stimulus_record(
        validated_stimulus, generated=stimulus_was_generated
    )

    # ── 6: Build NIR summary ──────────────────────────────────────────────────
    nir_summary = SimulatorNIRSummary(
        node_count=len(graph.nodes),
        edge_count=len(graph.edges),
        unsupported_nodes=classification.unsupported_nodes,
    )

    support_level = SupportLevel(classification.level)

    # The zero-weight warning leads: the backends' own "recorded no spikes" lines
    # describe the symptom, this one names the cause.
    prefix_warnings = [zero_weight_warning] if zero_weight_warning else []
    # Same for an unreachable firing threshold, which is the other way a run
    # comes back empty for a reason the raster cannot show. This diagnostic
    # already existed but only ever reached the generated notebook, so a user
    # running from Execute -> Review never saw it.
    prefix_warnings.extend(unreachable_threshold_warnings(graph))

    # ── 7: Dispatch to simulator backend ─────────────────────────────────────
    if body.backend_name == "lava_sim":
        from neurocnl.runtime.lava_simulator import (
            LavaDispatchError,
            LavaSimulatorAdapter,
        )

        try:
            logger.info(
                "lava_sim_dispatch_started",
                backend="lava_sim",
                timesteps=body.timesteps,
                runtime_mode="in_process" if _is_available("lava") else "remote",
            )
            lava_result = LavaSimulatorAdapter().run(
                graph,
                validated_stimulus,
                timesteps=body.timesteps,
                seed=body.seed,
                worker_url=lava_worker_url(),
            )
        except LavaDispatchError as exc:
            logger.error(
                "lava_sim_dispatch_error",
                backend="lava_sim",
                exc_type=type(exc).__name__,
                exc_message=str(exc),
                exc_info=True,
            )
            raise HTTPException(
                status_code=422,
                detail=build_backend_failure_detail(
                    "lava_dispatch_failed",
                    *exc.diagnostics,
                    items=[
                        {
                            "code": "lava_dispatch_failed",
                            "message": msg,
                            "source": "lava_sim",
                        }
                        for msg in exc.diagnostics
                    ],
                    source="lava_sim",
                    hint=(
                        "Check that the compiled NIR graph is supported by the Lava simulator "
                        "and that the Lava runtime is available."
                    ),
                ),
            ) from exc
        except Exception as exc:  # noqa: BLE001
            logger.exception(
                "lava_sim_unexpected_error",
                backend="lava_sim",
                exc_type=type(exc).__name__,
                exc_message=str(exc),
            )
            raise

        return SimulatorRunResult(
            backend_name=body.backend_name,
            status=SimulatorStatus.completed,
            support_level=support_level,
            timesteps=body.timesteps,
            duration_seconds=round(lava_result.execution_time_ms / 1000.0, 4),
            spikes=lava_result.spikes,
            voltages=lava_result.voltages,
            warnings=prefix_warnings
            + classification.diagnostics
            + lava_result.warnings,
            nir_summary=nir_summary,
            stimulus=stimulus_record,
            trained_weights=trained_weights,
            metadata={
                "seed": body.seed,
                "dt_ms": body.dt_ms,
                "firing_rate": body.firing_rate,
                "runtime_mode": lava_result.runtime_mode,
                "stimulus_population": validated_stimulus.population,
                "stimulus_neuron_count": validated_stimulus.neuron_count,
                "nir_support_level": classification.level,
            },
        )

    if body.backend_name == "brian2_sim":
        from neurocnl.runtime.brian2_simulator import (
            Brian2DispatchError,
            Brian2SimulatorAdapter,
        )

        try:
            logger.info(
                "brian2_sim_dispatch_started",
                backend="brian2_sim",
                timesteps=body.timesteps,
                runtime_mode="in_process" if _is_available("brian2") else "remote",
            )
            brian2_result = Brian2SimulatorAdapter().run(
                graph,
                validated_stimulus,
                timesteps=body.timesteps,
                seed=body.seed,
                worker_url=brian2_worker_url(),
            )
        except Brian2DispatchError as exc:
            raise HTTPException(
                status_code=422,
                detail=build_backend_failure_detail(
                    "brian2_dispatch_failed",
                    *exc.diagnostics,
                    items=[
                        {
                            "code": "brian2_dispatch_failed",
                            "message": msg,
                            "source": "brian2_sim",
                        }
                        for msg in exc.diagnostics
                    ],
                    source="brian2_sim",
                    hint=(
                        "Check that the compiled NIR graph is supported by the Brian2 simulator "
                        "and that the Brian2 runtime is available."
                    ),
                ),
            ) from exc

        return SimulatorRunResult(
            backend_name=body.backend_name,
            status=SimulatorStatus.completed,
            support_level=support_level,
            timesteps=body.timesteps,
            duration_seconds=round(brian2_result.execution_time_ms / 1000.0, 4),
            spikes=brian2_result.spikes,
            voltages=brian2_result.voltages,
            warnings=prefix_warnings
            + classification.diagnostics
            + brian2_result.warnings,
            nir_summary=nir_summary,
            stimulus=stimulus_record,
            trained_weights=trained_weights,
            metadata={
                "seed": body.seed,
                "dt_ms": body.dt_ms,
                "firing_rate": body.firing_rate,
                "runtime_mode": brian2_result.runtime_mode,
                "stimulus_population": validated_stimulus.population,
                "stimulus_neuron_count": validated_stimulus.neuron_count,
                "nir_support_level": classification.level,
            },
        )

    if body.backend_name == "nengo_sim":
        from neurocnl.runtime.nengo_simulator import (
            NengoDispatchError,
            NengoSimulatorAdapter,
        )

        try:
            nengo_result = NengoSimulatorAdapter().run(
                graph,
                validated_stimulus,
                timesteps=body.timesteps,
                seed=body.seed,
                dt_ms=body.dt_ms,
            )
        except NengoDispatchError as exc:
            raise HTTPException(
                status_code=422,
                detail=build_backend_failure_detail(
                    "nengo_dispatch_failed",
                    *exc.diagnostics,
                    items=[
                        {
                            "code": "nengo_dispatch_failed",
                            "message": msg,
                            "source": "nengo_sim",
                        }
                        for msg in exc.diagnostics
                    ],
                    source="nengo_sim",
                    hint=(
                        "Check that the compiled NIR graph is supported by the Nengo simulator "
                        "and that the Nengo runtime is installed."
                    ),
                ),
            ) from exc

        return SimulatorRunResult(
            backend_name=body.backend_name,
            status=SimulatorStatus.completed,
            support_level=support_level,
            timesteps=body.timesteps,
            duration_seconds=round(nengo_result.execution_time_ms / 1000.0, 4),
            spikes=nengo_result.spikes,
            voltages=nengo_result.voltages,
            warnings=prefix_warnings
            + classification.diagnostics
            + nengo_result.warnings,
            nir_summary=nir_summary,
            stimulus=stimulus_record,
            trained_weights=trained_weights,
            metadata={
                "seed": body.seed,
                "dt_ms": body.dt_ms,
                "firing_rate": body.firing_rate,
                "runtime_mode": nengo_result.runtime_mode,
                "stimulus_population": validated_stimulus.population,
                "stimulus_neuron_count": validated_stimulus.neuron_count,
                "nir_support_level": classification.level,
            },
        )

    if body.backend_name == "sinabs_sim":
        from neurocnl.runtime.sinabs_simulator import (
            SinabsDispatchError,
            SinabsSimulatorAdapter,
        )

        try:
            sinabs_result = SinabsSimulatorAdapter().run(
                graph,
                validated_stimulus,
                timesteps=body.timesteps,
                seed=body.seed,
            )
        except SinabsDispatchError as exc:
            raise HTTPException(
                status_code=422,
                detail=build_backend_failure_detail(
                    "sinabs_dispatch_failed",
                    *exc.diagnostics,
                    items=[
                        {
                            "code": "sinabs_dispatch_failed",
                            "message": msg,
                            "source": "sinabs_sim",
                        }
                        for msg in exc.diagnostics
                    ],
                    source="sinabs_sim",
                    hint=(
                        "Check that the compiled NIR graph is sequential, trained weights "
                        "are attached, and that sinabs + torch are installed."
                    ),
                ),
            ) from exc

        return SimulatorRunResult(
            backend_name=body.backend_name,
            status=SimulatorStatus.completed,
            support_level=support_level,
            timesteps=body.timesteps,
            duration_seconds=round(sinabs_result.execution_time_ms / 1000.0, 4),
            spikes=sinabs_result.spikes,
            voltages=sinabs_result.voltages,
            warnings=prefix_warnings
            + classification.diagnostics
            + sinabs_result.warnings,
            nir_summary=nir_summary,
            stimulus=stimulus_record,
            trained_weights=trained_weights,
            metadata={
                "seed": body.seed,
                "dt_ms": body.dt_ms,
                "firing_rate": body.firing_rate,
                "runtime_mode": sinabs_result.runtime_mode,
                "stimulus_population": validated_stimulus.population,
                "stimulus_neuron_count": validated_stimulus.neuron_count,
                "nir_support_level": classification.level,
            },
        )

    # ── sc_neurocore_sim: Rust-based SNN simulation dispatch ──────────────────
    if body.backend_name == "sc_neurocore_sim":
        from neurocnl.runtime.sc_neurocore_simulator import (
            ScNeuroCoreDispatchError,
            ScNeuroCoreSimulatorAdapter,
        )

        try:
            logger.info(
                "sc_neurocore_sim_dispatch_started",
                backend="sc_neurocore_sim",
                timesteps=body.timesteps,
            )
            sc_result = ScNeuroCoreSimulatorAdapter().run(
                graph,
                validated_stimulus,
                timesteps=body.timesteps,
                seed=body.seed,
            )
        except ScNeuroCoreDispatchError as exc:
            logger.error(
                "sc_neurocore_sim_dispatch_error",
                backend="sc_neurocore_sim",
                exc_type=type(exc).__name__,
                exc_message=str(exc),
                exc_info=True,
            )
            raise HTTPException(
                status_code=422,
                detail=build_backend_failure_detail(
                    "sc_neurocore_dispatch_failed",
                    *exc.diagnostics,
                    items=[
                        {
                            "code": "sc_neurocore_dispatch_failed",
                            "message": msg,
                            "source": "sc_neurocore_sim",
                        }
                        for msg in exc.diagnostics
                    ],
                    source="sc_neurocore_sim",
                    hint=(
                        "Check that the compiled NIR graph is supported by sc-neurocore "
                        "and that the sc-neurocore package is installed."
                    ),
                ),
            ) from exc

        return SimulatorRunResult(
            backend_name=body.backend_name,
            status=SimulatorStatus.completed,
            support_level=support_level,
            timesteps=body.timesteps,
            duration_seconds=round(sc_result.execution_time_ms / 1000.0, 4),
            spikes=sc_result.spikes,
            voltages=sc_result.voltages,
            warnings=prefix_warnings + classification.diagnostics + sc_result.warnings,
            nir_summary=nir_summary,
            stimulus=stimulus_record,
            trained_weights=trained_weights,
            metadata={
                "seed": body.seed,
                "dt_ms": body.dt_ms,
                "firing_rate": body.firing_rate,
                "runtime_mode": sc_result.runtime_mode,
                "stimulus_population": validated_stimulus.population,
                "stimulus_neuron_count": validated_stimulus.neuron_count,
                "nir_support_level": classification.level,
            },
        )

    # ── snntorch_sim: T1-7 real dispatch ─────────────────────────────────────
    from neurocnl.runtime.snntorch_simulator import (
        SnnTorchDispatchError,
        SnnTorchSimulatorAdapter,
    )

    try:
        snn_result = SnnTorchSimulatorAdapter().run(
            graph,
            validated_stimulus,
            timesteps=body.timesteps,
            seed=body.seed,
        )
    except SnnTorchDispatchError as exc:
        raise HTTPException(
            status_code=422,
            detail=build_backend_failure_detail(
                "snntorch_dispatch_failed",
                *exc.diagnostics,
                items=[
                    {
                        "code": "snntorch_dispatch_failed",
                        "message": msg,
                        "source": "snntorch_sim",
                    }
                    for msg in exc.diagnostics
                ],
                source="snntorch_sim",
                hint=(
                    "Check that the compiled NIR graph is supported and that "
                    "torch + snntorch are installed."
                ),
            ),
        ) from exc

    return SimulatorRunResult(
        backend_name=body.backend_name,
        status=SimulatorStatus.completed,
        support_level=support_level,
        timesteps=body.timesteps,
        duration_seconds=round(snn_result.execution_time_ms / 1000.0, 4),
        spikes=snn_result.spikes,
        voltages=snn_result.voltages,
        warnings=prefix_warnings + classification.diagnostics + snn_result.warnings,
        nir_summary=nir_summary,
        stimulus=stimulus_record,
        trained_weights=trained_weights,
        metadata={
            "seed": body.seed,
            "dt_ms": body.dt_ms,
            "firing_rate": body.firing_rate,
            "runtime_mode": snn_result.runtime_mode,
            "stimulus_population": validated_stimulus.population,
            "stimulus_neuron_count": validated_stimulus.neuron_count,
            "nir_support_level": classification.level,
        },
    )


# ---------------------------------------------------------------------------
# Preflight endpoint — raw NIR HDF5 input (Task 2.3)
# ---------------------------------------------------------------------------

_KNOWN_PREFLIGHT_BACKENDS = set(list_simulator_backends())


@router.post(
    "/simulators/preflight-nir",
    response_model=PreflightResult,
    summary="Classify a raw NIR graph against a simulator backend (no dispatch)",
    tags=["simulators"],
)
@limiter.limit("10/minute")
async def preflight_nir(
    request: Request,
    response: Response,
    file: Annotated[UploadFile, File()],
    backend_name: Annotated[str, Form()],
) -> PreflightResult:
    """Classify an uploaded NIR HDF5 file against a simulator backend.

    Accepts a raw ``.nir`` HDF5 binary and a backend name as multipart
    form fields.  The endpoint never dispatches to a simulator runtime
    and never checks whether optional dependencies are installed.

    Pipeline
    --------
    1. Validate ``backend_name`` ∈ ``{lava_sim, snntorch_sim}`` → 422
       ``unknown_backend``.
    2. Read file bytes → write to a ``NamedTemporaryFile`` (suffix
       ``.nir``, ``delete=False``).
    3. ``nir.read(str(tmp_path))`` → 422 ``nir_parse_error`` on any
       exception; ``finally`` block unlinks the temp file.
    4. ``classify_nir_graph(graph, backend_name)`` → return
       ``PreflightResult``.
    """
    # ── 1. Validate backend name ──────────────────────────────────────────
    if backend_name not in _KNOWN_PREFLIGHT_BACKENDS:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Unknown simulator backend {backend_name!r}.",
                code="unknown_backend",
            ),
        )

    # ── 2. Load NIR graph from HDF5 bytes ─────────────────────────────────
    # Uses the same NamedTemporaryFile pattern as neurosim/generation.py
    # because nir.read() may seek the file; BytesIO is insufficient.
    contents = await file.read()
    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
            tmp.write(contents)
            tmp_path = Path(tmp.name)
        graph = nir.read(str(tmp_path))
    except Exception as exc:
        raise HTTPException(
            status_code=422,
            detail=build_validation_failure_detail(
                f"Failed to parse NIR HDF5 file: {exc}",
                code="nir_parse_error",
            ),
        ) from exc
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)

    # ── 3. Classify NIR support ───────────────────────────────────────────
    classification = classify_nir_graph(graph, backend_name)

    # ── 4. Return result — no simulator dispatch ──────────────────────────
    return PreflightResult(
        level=classification.level,
        supported_nodes=classification.supported_nodes,
        approximate_nodes=classification.approximate_nodes,
        unsupported_nodes=classification.unsupported_nodes,
        diagnostics=classification.diagnostics,
    )
