"""Service layer for lightweight fault injection analysis."""

from __future__ import annotations

from backend.app.schemas.prosthetic import FaultInjectionRequest, FaultInjectionResult
from backend.app.services.neurocnl_bridge import build_deploy_ir_from_spec_text
from neurocnl.ir import LoweringError
from neurocnl.pipeline import (
    apply_user_params,
    default_params_with_provenance,
    parse_spec_text,
)


def run_fault_injection_analysis(req: FaultInjectionRequest) -> dict:
    """Estimate resilience under injected faults for the current CNL spec.

    The current implementation provides a deterministic structural analysis
    backed by the lowered IR so the frontend can exercise a real backend
    contract even when hardware extras are unavailable.
    """
    parse_results = parse_spec_text(req.spec)
    parse_errors = [r["error_detail"] for r in parse_results if not r["valid"]]
    if parse_errors:
        messages = [e["message"] for e in parse_errors if e is not None]
        raise ValueError("Parse failed: " + "; ".join(messages))

    parsed_specs = [r["parsed"] for r in parse_results if r["valid"]]
    params, param_provenance = default_params_with_provenance(parsed_specs)
    apply_user_params(params, param_provenance, {})

    try:
        ir = build_deploy_ir_from_spec_text(req.spec, parsed_specs)
    except LoweringError as exc:
        raise ValueError(f"Lowering failed: {exc}") from exc

    population_names = list(ir.populations.keys())
    if not population_names:
        population_names = ["network"]

    n_populations = len(population_names)
    n_connections = len(ir.connections)
    density = min(1.0, n_connections / max(1, n_populations))

    baseline_accuracy = max(0.8, 0.99 - 0.01 * min(n_populations, 10))
    degradation = min(0.95, req.error_rate * (0.55 + 0.25 * density))
    degraded_accuracy = max(0.0, baseline_accuracy - degradation)

    failed_count = 0
    if req.error_rate > 0:
        failed_count = max(1, round(req.error_rate * n_populations))
    failed_nodes = population_names[: min(n_populations, failed_count)]

    resilience_score = 0.0
    if baseline_accuracy > 0:
        resilience_score = max(0.0, min(1.0, degraded_accuracy / baseline_accuracy))

    return FaultInjectionResult(
        error_rate=req.error_rate,
        baseline_accuracy=round(baseline_accuracy, 4),
        degraded_accuracy=round(degraded_accuracy, 4),
        failed_nodes=failed_nodes,
        resilience_score=round(resilience_score, 4),
    ).model_dump()
