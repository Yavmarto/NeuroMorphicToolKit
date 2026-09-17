"""Service for running parameter sweep simulations with Nengo."""

import copy
import uuid

from ...contracts.design_contracts import (
    BackendSupport,
    GeneratorFidelitySummary,
    SimulationStatus,
)
from ..schemas.canvas import CanvasGraph
from ..schemas.preview import PreviewRequest
from ..schemas.sweep import SweepRequest, SweepResponse, SweepStepResult
from .job_store import job_store
from .nir_support import (
    PREVIEW_BACKEND,
    assess_preview_support,
    can_use_neurocnl_generator,
    merge_backend_support,
    merge_generator_fidelity,
    requires_local_faithful_preview,
)
from .preview_runner import run_preview

EXPECTED_PARAMETER_PATH_PARTS = 3
POPULATION_SPECIFIC_PREVIEW_PARAMS = {"threshold", "tau_ref", "tau_rc"}
NUMERIC_NODE_PARAMS = {"tau_rc", "tau_ref", "n_neurons", "threshold"}
NUMERIC_EDGE_PARAMS = {"weight", "delay"}


def update_graph_parameter(graph: CanvasGraph, parameter_path: str, value: float) -> CanvasGraph:
    """Update a parameter in a CanvasGraph given its path.

    Paths are expected in the format: "nodes.<node_id>.<param_name>"
    or "edges.<edge_id>.<param_name>".

    Args:
        graph (CanvasGraph): The graph to update.
        parameter_path (str): The dot-separated path to the parameter.
        value (float): The new value for the parameter.

    Returns:
        CanvasGraph: A new graph instance with the parameter updated.
    """
    new_graph = copy.deepcopy(graph)
    path_parts = _parameter_path_parts(parameter_path)
    if path_parts is None:
        raise ValueError(
            f"Invalid parameter path {parameter_path!r}: expected format "
            "'nodes.<id>.<param>' or 'edges.<id>.<param>'."
        )

    category, element_id, param_name = path_parts
    if category not in {"nodes", "edges"}:
        raise ValueError(f"Parameter path category must be 'nodes' or 'edges', got {category!r}.")

    elements = new_graph.nodes if category == "nodes" else new_graph.edges
    target = next((element for element in elements if element.id == element_id), None)
    if target is None:
        available_ids = [element.id for element in elements]
        raise ValueError(
            f"No {category[:-1]} with id {element_id!r} found in graph. "
            f"Available ids: {available_ids}"
        )

    allowed = NUMERIC_NODE_PARAMS if category == "nodes" else NUMERIC_EDGE_PARAMS
    if param_name not in allowed:
        raise ValueError(
            f"Parameter {param_name!r} is not a supported sweep target for {category}. "
            f"Supported: {sorted(allowed)}"
        )

    target.parameters[param_name] = value

    return new_graph


def _build_step_values(request: SweepRequest) -> list[float]:
    if request.steps > 1:
        step_size = (request.end - request.start) / (request.steps - 1)
    else:
        step_size = 0.0
    return [request.start + index * step_size for index in range(request.steps)]


def _parameter_path_parts(parameter_path: str) -> tuple[str, str, str] | None:
    parts = parameter_path.split(".")
    if len(parts) != EXPECTED_PARAMETER_PATH_PARTS:
        return None
    return parts[0], parts[1], parts[2]


def validate_parameter_path(graph: CanvasGraph, parameter_path: str) -> None:
    """Validate a sweep parameter path against the graph."""
    update_graph_parameter(graph, parameter_path, 0.0)


def _is_faithful_local_preview_sweep_step(
    graph: CanvasGraph,
    parameter_path: str,
    support: BackendSupport,
) -> bool:
    if support.verdict != "approximate":
        return False
    path_parts = _parameter_path_parts(parameter_path)
    if path_parts is None:
        return False
    category, _element_id, parameter_name = path_parts
    if category != "nodes" or parameter_name not in POPULATION_SPECIFIC_PREVIEW_PARAMS:
        return False
    return can_use_neurocnl_generator(graph) and requires_local_faithful_preview(graph)


def _promote_faithful_local_preview_support(
    support: BackendSupport,
) -> BackendSupport:
    return BackendSupport(
        backend=support.backend,
        verdict="faithful",
        warnings=list(support.warnings),
        supported_concepts=list(support.supported_concepts),
        approximated_concepts=[
            concept
            for concept in support.approximated_concepts
            if concept != "population_specific_preview_parameters"
        ],
        unsupported_concepts=list(support.unsupported_concepts),
    )


def _assess_sweep_step_supports(
    request: SweepRequest,
) -> tuple[list[CanvasGraph], list[BackendSupport], list[GeneratorFidelitySummary | None]]:
    graphs: list[CanvasGraph] = []
    supports: list[BackendSupport] = []
    fidelities: list[GeneratorFidelitySummary | None] = []

    for param_value in _build_step_values(request):
        swept_graph = update_graph_parameter(
            request.graph,
            request.parameter_path,
            param_value,
        )
        support, fidelity = assess_preview_support(swept_graph)
        if _is_faithful_local_preview_sweep_step(
            swept_graph,
            request.parameter_path,
            support,
        ):
            support = _promote_faithful_local_preview_support(support)
        graphs.append(swept_graph)
        supports.append(support)
        fidelities.append(fidelity)

    return graphs, supports, fidelities


def assess_sweep_support(
    request: SweepRequest,
    backend: str = PREVIEW_BACKEND,
) -> tuple[BackendSupport, GeneratorFidelitySummary | None]:
    """Assess the worst-case preview support across all sweep steps."""
    _, supports, fidelities = _assess_sweep_step_supports(request)
    return (
        merge_backend_support(supports, backend=backend),
        merge_generator_fidelity(fidelities),
    )


def run_sweep_sync(
    request: SweepRequest,
    job_id: str,
    backend_support: BackendSupport | None = None,
    generator_fidelity: GeneratorFidelitySummary | None = None,
) -> None:
    """Execute a sweep job for a previously queued job id.

    Args:
        request (SweepRequest): The original sweep request.
        job_id (str): The job ID to update.
        backend_support (BackendSupport | None): Pre-computed backend support from the router.
            When provided the sweep runner skips the redundant re-assessment inside run_sweep.
        generator_fidelity (GeneratorFidelitySummary | None): Pre-computed fidelity summary.
    """
    job = job_store.get_job(job_id)
    if job is not None:
        job.parameter_path = request.parameter_path
        # Prefer pre-computed support from the router over the job store copy.
        if backend_support is None:
            backend_support = job.backend_support
        if generator_fidelity is None:
            generator_fidelity = job.generator_fidelity

    job_store.update_job_status(job_id, SimulationStatus.RUNNING)
    try:
        response = run_sweep(
            request,
            job_id=job_id,
            backend_support=backend_support,
            generator_fidelity=generator_fidelity,
        )
        match response.status:
            case SimulationStatus.FAILED:
                job_store.update_job_error(job_id, response.error or "Unknown error")
                return
            case SimulationStatus.CANCELLED:
                return
            case _:
                job_store.update_job_results(
                    job_id,
                    response.steps,
                    backend_support=response.backend_support,
                    generator_fidelity=response.generator_fidelity,
                )
    except Exception as exc:
        job_store.update_job_error(job_id, str(exc))


def run_sweep(
    request: SweepRequest,
    job_id: str | None = None,
    backend_support: BackendSupport | None = None,
    generator_fidelity: GeneratorFidelitySummary | None = None,
) -> SweepResponse:
    """Start a parameter sweep simulation job.

    Args:
        request (SweepRequest): The sweep request.
        job_id (str | None): Optional job ID for cancellation polling.
        backend_support (BackendSupport | None): Pre-computed worst-case support. When
            provided the per-step re-assessment is skipped to avoid duplicate work.
        generator_fidelity (GeneratorFidelitySummary | None): Pre-computed fidelity summary.

    Returns:
        SweepResponse: The completed sweep response.
    """
    step_results: list[SweepStepResult] = []
    step_values = _build_step_values(request)

    if backend_support is not None and generator_fidelity is not None:
        # Use pre-computed worst-case values; still need individual swept graphs for execution.
        swept_graphs = [
            update_graph_parameter(request.graph, request.parameter_path, v) for v in step_values
        ]
        step_supports = [backend_support] * len(swept_graphs)
        step_fidelities: list[GeneratorFidelitySummary | None] = [generator_fidelity] * len(
            swept_graphs
        )
        support = backend_support
        fidelity: GeneratorFidelitySummary | None = generator_fidelity
    else:
        swept_graphs, step_supports, step_fidelities = _assess_sweep_step_supports(request)
        support = merge_backend_support(step_supports, backend=PREVIEW_BACKEND)
        fidelity = merge_generator_fidelity(step_fidelities)

    if support.verdict == "unsupported":
        return SweepResponse(
            job_id=job_id,
            status=SimulationStatus.FAILED,
            error="Sweep is unsupported for the selected backend.",
            parameter_path=request.parameter_path,
            steps=None,
            backend_support=support,
            generator_fidelity=fidelity,
        )

    try:
        for param_value, swept_graph, step_support, step_fidelity in zip(
            step_values,
            swept_graphs,
            step_supports,
            step_fidelities,
            strict=True,
        ):
            if job_id:
                job = job_store.get_job(job_id)
                if job and job.cancelled:
                    return SweepResponse(
                        job_id=job_id,
                        status=SimulationStatus.CANCELLED,
                        parameter_path=request.parameter_path,
                        steps=step_results,
                        backend_support=support,
                        generator_fidelity=fidelity,
                    )
            preview_request = PreviewRequest(
                graph=swept_graph,
                duration_ms=request.simulation_duration_ms,
            )
            preview_response = run_preview(
                preview_request,
                backend_support=step_support,
                generator_fidelity=step_fidelity,
            )
            match preview_response.status:
                case SimulationStatus.FAILED:
                    return SweepResponse(
                        job_id=job_id or str(uuid.uuid4()),
                        status=SimulationStatus.FAILED,
                        error=preview_response.error or "Sweep preview step failed.",
                        parameter_path=request.parameter_path,
                        steps=step_results,
                        backend_support=support,
                        generator_fidelity=fidelity,
                    )
                case _:
                    step_results.append(
                        SweepStepResult(
                            parameter_value=param_value,
                            result=preview_response,
                        ),
                    )
    except Exception as exc:
        return SweepResponse(
            job_id=job_id or str(uuid.uuid4()),
            status=SimulationStatus.FAILED,
            error=str(exc),
            parameter_path=request.parameter_path,
            steps=None,
            backend_support=support,
            generator_fidelity=fidelity,
        )
    return SweepResponse(
        job_id=job_id or str(uuid.uuid4()),
        status=SimulationStatus.COMPLETED,
        parameter_path=request.parameter_path,
        steps=step_results,
        backend_support=support,
        generator_fidelity=fidelity,
    )
