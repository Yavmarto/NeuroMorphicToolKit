"""NIR-native backend support assessments for NeuroSim.

Replaces the biological-grammar-specific neurocnl_bridge assessments with
NIR-native equivalents that cover all 19 NIR primitives.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, NoReturn

import neurocnl as neurocnl_package
from neurosim.app.services.components import load_components
from neurosim.contracts.design_contracts import (
    BackendSupport,
    CanvasGraph,
    GeneratorFidelityAnnotation,
    GeneratorFidelitySummary,
)

NEUROCNL_ROOT = Path(neurocnl_package.__file__).resolve().parent

PREVIEW_BACKEND = "nengo"
CANONICAL_EXPORT_FORMAT = "cnl"
VISUAL_EXPORT_FORMAT = "svg"
LOCAL_ONLY_EXPORT_FORMATS = {"python", "nir", "mlir", "neuroml", "c"}
UNSUPPORTED_EXPORT_FORMATS = {"c"}

LOCAL_EXPORT_WARNING = (
    "This export is produced by a NeuroSim-local serializer rather than NeuroCNL's "
    "shared backend exporter."
)
LOCAL_EXPORT_SCAFFOLD_WARNING = (
    "This export target is only available as a local scaffold in NeuroSim and is not "
    "backed by a supported NeuroCNL backend export path."
)
# fmt: off
SVG_EXPORT_WARNING = "SVG export is a visual layout export and does not represent backend execution fidelity."
# fmt: on

_FAITHFUL_VERDICTS = {"faithful", "exportable", "deployable"}
_APPROXIMATE_VERDICTS = {
    "approximate",
    "exportable_with_warnings",
    "deployable_with_warnings",
}
_UNSUPPORTED_VERDICTS = {"unsupported", "not_exportable", "not_deployable"}


@dataclass
class _SupportDetails:
    warnings: list[str] = field(default_factory=list)
    supported_concepts: list[str] = field(default_factory=list)
    approximated_concepts: list[str] = field(default_factory=list)
    unsupported_concepts: list[str] = field(default_factory=list)


def _normalize_verdict(verdict: str) -> str:
    lowered = verdict.lower()
    if lowered in _FAITHFUL_VERDICTS:
        return "faithful"
    if lowered in _APPROXIMATE_VERDICTS:
        return "approximate"
    if lowered in _UNSUPPORTED_VERDICTS:
        return "unsupported"
    return verdict


def _merge_unique(collections: Iterable[list[str]]) -> list[str]:
    merged: list[str] = []
    for col in collections:
        for item in col:
            if item not in merged:
                merged.append(item)
    return merged


def _build_support(
    *,
    backend: str,
    verdict: str,
    details: _SupportDetails | None = None,
) -> BackendSupport:
    d = details or _SupportDetails()
    return BackendSupport(
        backend=backend,
        verdict=_normalize_verdict(verdict),
        warnings=list(d.warnings),
        supported_concepts=list(d.supported_concepts),
        approximated_concepts=list(d.approximated_concepts),
        unsupported_concepts=list(d.unsupported_concepts),
    )


def merge_backend_support(
    supports: Iterable[BackendSupport],
    *,
    backend: str | None = None,
) -> BackendSupport:
    """Collapse multiple support assessments into the worst-case verdict."""
    support_list = list(supports)
    if not support_list:
        return _build_support(backend=backend or PREVIEW_BACKEND, verdict="faithful")

    priority = {"faithful": 0, "approximate": 1, "unsupported": 2}
    verdict = max(
        (_normalize_verdict(s.verdict) for s in support_list),
        key=lambda v: priority.get(v, 99),
    )
    supported_concepts = _merge_unique(s.supported_concepts for s in support_list)
    approximated_concepts = _merge_unique(s.approximated_concepts for s in support_list)
    unsupported_concepts = _merge_unique(s.unsupported_concepts for s in support_list)

    return _build_support(
        backend=backend or support_list[0].backend,
        verdict=verdict,
        details=_SupportDetails(
            warnings=_merge_unique(s.warnings for s in support_list),
            supported_concepts=supported_concepts,
            approximated_concepts=approximated_concepts,
            unsupported_concepts=unsupported_concepts,
        ),
    )


def merge_generator_fidelity(
    fidelities: Iterable[GeneratorFidelitySummary | None],
) -> GeneratorFidelitySummary | None:
    """Merge fidelity annotation lists, preserving first-seen order."""
    annotations: list[GeneratorFidelityAnnotation] = []
    seen: set[tuple[str, str, str, str]] = set()
    for fidelity in fidelities:
        if fidelity is None:
            continue
        for ann in fidelity.annotations:
            key = (ann.concept, ann.subject, ann.fidelity, ann.reason)
            if key in seen:
                continue
            seen.add(key)
            annotations.append(ann)
    return GeneratorFidelitySummary(annotations=annotations) if annotations else None


def assess_preview_support(
    graph: CanvasGraph,
    backend: str = PREVIEW_BACKEND,
) -> tuple[BackendSupport, GeneratorFidelitySummary | None]:
    """Return NIR-native preview support for a canvas graph.

    All graphs now go through the local Nengo preview model builder.
    NIR-type graphs report faithful; legacy biological-only graphs report approximate.
    """
    if not graph.nodes and not graph.edges:
        return (
            _build_support(
                backend=backend,
                verdict="approximate",
                details=_SupportDetails(
                    warnings=["Empty graphs do not map to a concrete design."],
                    approximated_concepts=["empty_graph"],
                ),
            ),
            None,
        )

    components = load_components()
    for node in graph.nodes:
        if node.nir_type is None and node.component_id not in components:
            return (
                _build_support(
                    backend=backend,
                    verdict="unsupported",
                    details=_SupportDetails(
                        warnings=[f"Unknown component type '{node.component_id}'."],
                        unsupported_concepts=["unknown_component"],
                    ),
                ),
                None,
            )

    has_nir_nodes = any(node.nir_type for node in graph.nodes)
    if has_nir_nodes:
        return _build_support(backend=backend, verdict="faithful"), None
    # Biological/legacy canvas nodes — local preview fallback
    annotations: list[GeneratorFidelityAnnotation] = []
    for node in graph.nodes:
        if node.parameters.get("threshold") is not None:
            annotations.append(
                GeneratorFidelityAnnotation(
                    concept="threshold",
                    subject=node.id,
                    fidelity="approximate",
                    reason="Local preview uses fixed firing threshold; NeuroCNL backend required for exact threshold dynamics.",
                )
            )
    for edge in graph.edges:
        if edge.parameters.get("delay") is not None:
            annotations.append(
                GeneratorFidelityAnnotation(
                    concept="axonal_delay",
                    subject=edge.id,
                    fidelity="approximate",
                    reason="Local preview approximates axonal delay; NeuroCNL backend required for exact delay propagation.",
                )
            )
    fidelity = None
    if annotations:
        fidelity = GeneratorFidelitySummary(annotations=annotations)
    return (
        _build_support(
            backend=backend,
            verdict="approximate",
            details=_SupportDetails(
                warnings=[
                    "Preview approximates execution through NeuroSim's local preview model builder."
                ],
                approximated_concepts=["local_preview_fallback"],
            ),
        ),
        fidelity,
    )


def assess_validation_support(
    graph: CanvasGraph,
    backend: str = PREVIEW_BACKEND,
) -> tuple[BackendSupport, GeneratorFidelitySummary | None]:
    """Return NIR-native validation support for a canvas graph."""
    if not graph.nodes and not graph.edges:
        return (
            _build_support(
                backend=backend,
                verdict="approximate",
                details=_SupportDetails(
                    warnings=["Empty graphs do not map to a concrete design."],
                    approximated_concepts=["empty_graph"],
                ),
            ),
            None,
        )

    components = load_components()
    for node in graph.nodes:
        if node.nir_type is None and node.component_id not in components:
            return (
                _build_support(
                    backend=backend,
                    verdict="unsupported",
                    details=_SupportDetails(
                        warnings=[f"Unknown component type '{node.component_id}'."],
                        unsupported_concepts=["unknown_component"],
                    ),
                ),
                None,
            )

    has_nir_nodes = any(node.nir_type for node in graph.nodes)
    if has_nir_nodes:
        return _build_support(backend=backend, verdict="faithful"), None
    return (
        _build_support(
            backend=backend,
            verdict="approximate",
            details=_SupportDetails(
                warnings=[
                    "This design is outside NeuroSim's shared NeuroCNL validation/runtime path "
                    "and will rely on NeuroSim-local validation behavior."
                ],
                approximated_concepts=["local_validation_fallback"],
            ),
        ),
        None,
    )


def assess_export_support(
    graph: CanvasGraph,
    format: str,
) -> tuple[BackendSupport, GeneratorFidelitySummary | None]:
    """Return NIR-native export support for a canvas graph and format."""
    if format == CANONICAL_EXPORT_FORMAT:
        return _build_support(backend=format, verdict="faithful"), None

    if format == VISUAL_EXPORT_FORMAT:
        return (
            _build_support(
                backend=format,
                verdict="approximate",
                details=_SupportDetails(
                    warnings=[SVG_EXPORT_WARNING],
                    approximated_concepts=["visual_export"],
                ),
            ),
            None,
        )

    if format in LOCAL_ONLY_EXPORT_FORMATS:
        if format in UNSUPPORTED_EXPORT_FORMATS:
            return (
                _build_support(
                    backend=format,
                    verdict="unsupported",
                    details=_SupportDetails(
                        warnings=[LOCAL_EXPORT_SCAFFOLD_WARNING],
                        unsupported_concepts=["local_export_scaffold"],
                    ),
                ),
                None,
            )
        return (
            _build_support(
                backend=format,
                verdict="approximate",
                details=_SupportDetails(
                    warnings=[LOCAL_EXPORT_WARNING],
                    approximated_concepts=["local_export_serializer"],
                ),
            ),
            None,
        )

    return (
        _build_support(
            backend=format,
            verdict="unsupported",
            details=_SupportDetails(
                warnings=[f"Export format {format!r} is not supported."],
                unsupported_concepts=["export_format"],
            ),
        ),
        None,
    )


def validate_semantics(neuron_params: dict[str, Any]) -> list[str]:
    """Validate biological neuron parameters for lif_population/adaptive_lif nodes.

    Returns a list of error message strings (empty if valid).
    """
    from neurocnl.layers.layer1_validator import validate

    mapped_params = {}
    if "tau_rc" in neuron_params:
        mapped_params["tau"] = neuron_params["tau_rc"]
    if "tau_ref" in neuron_params:
        mapped_params["refractory_period"] = neuron_params["tau_ref"]
    if "threshold" in neuron_params:
        mapped_params["threshold"] = neuron_params["threshold"]
    if "weight" in neuron_params:
        mapped_params["synaptic_weight"] = neuron_params["weight"]

    default_params = {
        "threshold": 1.0,
        "resting_potential": 0.0,
        "refractory_period": 0.002,
        "tau": 0.02,
        "reset_potential": 0.0,
        "current_voltage": 0.5,
    }
    default_params.update(mapped_params)

    result = validate([], default_params)
    if not result.get("overall"):
        return [f"{f['name']}: {f['reason']}" for f in result.get("failed", [])]
    return []


def can_use_neurocnl_generator(_graph: CanvasGraph) -> bool:
    """Always False — the biological Nengo generator has been removed."""
    return False


def requires_local_faithful_preview(_graph: CanvasGraph) -> bool:
    """Always False — local model builder handles all cases."""
    return False


def generate_neurocnl_model(_graph: CanvasGraph) -> NoReturn:
    """Not available — biological Nengo generator has been removed.

    Raises NotImplementedError unconditionally.
    """
    raise NotImplementedError(
        "generate_neurocnl_model is no longer available. "
        "The biological Nengo generator was removed as part of the NIR-native CNL migration. "
        "Use the local Nengo preview model builder instead."
    )
