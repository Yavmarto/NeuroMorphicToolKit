"""Bridge between the FastAPI layer and the neurocnl library.

Wraps every public neurocnl function with error handling and output
normalisation so the routers stay thin.

Delegates to neurocnl.pipeline for shared logic.
"""

from __future__ import annotations

import os
import tempfile
from collections import defaultdict
from collections.abc import MutableMapping
from pathlib import Path
from typing import Any

import nengo
import numpy as np

from backend.app.utils.cnl_errors import StructuredJobError, normalize_cnl_error_item
from neurocnl.cnl.types import ParsedSentence
from neurocnl.export.nir_exporter import materialize_to_nir as _materialize_to_nir
from neurocnl.ir import (
    ConnectionIR,
    LoweringError,
    MaterializerError,
    NetworkIR,
    PopulationIR,
)
from neurocnl.ir.types import SourceProvenance
from neurocnl.nir_cnl.ir_types import NetworkContainer, NIREdgeRecord, NIRNodeRecord
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.size_propagation import (
    linear_weight_matrix as _linear_weight_matrix,
)
from neurocnl.nir_cnl.size_propagation import (
    propagate_nir_sizes as _propagate_nir_sizes,
)
from neurocnl.nir_cnl.size_propagation import (
    require_int_tuple_param as _require_int_tuple_param,
)
from neurocnl.nir_cnl.size_propagation import vector_values as _vector_values
from neurocnl.pipeline import (
    apply_user_params,
    build_ir_from_spec_text,
    default_params_from_specs,
    default_params_with_provenance,
    parse_spec_text,
)
from neurocnl.pipeline import validate_spec as _validate_spec
from neurocnl.planner import plan_backend_support

# Re-export for existing callers
parse_spec = parse_spec_text
_default_params_from_specs = default_params_from_specs


def ensure_nengo_runtime_cache(
    env: MutableMapping[str, str] | None = None,
) -> Path:
    """Ensure Nengo has a writable runtime home and decoder-cache directory.

    Docker images often run as a system user whose default home resolves to a
    non-existent path such as ``/nonexistent``. Nengo's decoder cache uses the
    process home/cache directories, so simulation can fail even though the
    package is installed correctly. This helper normalises the runtime
    environment to a writable location before the simulator is constructed.
    """

    runtime_env = os.environ if env is None else env

    configured_home = runtime_env.get("HOME", "").strip()
    home_path = Path(configured_home).expanduser() if configured_home else None
    if home_path is None or not home_path.exists() or not home_path.is_dir():
        home_path = Path(tempfile.gettempdir()) / "nmtk-runtime-home"
        home_path.mkdir(parents=True, exist_ok=True)
        runtime_env["HOME"] = str(home_path)

    configured_cache = runtime_env.get("XDG_CACHE_HOME", "").strip()
    cache_root = (
        Path(configured_cache).expanduser()
        if configured_cache
        else home_path / ".cache"
    )
    cache_root.mkdir(parents=True, exist_ok=True)
    runtime_env["XDG_CACHE_HOME"] = str(cache_root)

    decoder_cache_dir = cache_root / "nengo" / "decoders"
    decoder_cache_dir.mkdir(parents=True, exist_ok=True)

    # Nengo is imported at module-load time in this bridge, so updating
    # HOME/XDG_CACHE_HOME alone is too late for Docker/system-user cases.
    # Point the live decoder-cache config at the writable directory as well.
    nengo.rc.set("decoder_cache", "path", str(decoder_cache_dir))
    nengo.rc.set("decoder_cache", "enabled", "True")
    return decoder_cache_dir


# NIR-native concept names — all concepts produced by the NIR-native parser.
_NIR_ALL_CONCEPTS: frozenset[str] = frozenset(
    {
        "Input",
        "Output",
        "LIF",
        "CubaLIF",
        "LI",
        "CubaLI",
        "IF",
        "I",
        "Linear",
        "Affine",
        "Scale",
        "Conv1d",
        "Conv2d",
        "AvgPool2d",
        "SumPool2d",
        "Flatten",
        "Delay",
        "Threshold",
        "Connect",
    }
)

_NIR_DEPLOY_POPULATION_PRIMITIVES: frozenset[str] = frozenset(
    {"Input", "Output", "LIF"}
)
_NIR_DEPLOY_SUPPORTED_PRIMITIVES: frozenset[str] = frozenset(
    {"Input", "Output", "LIF", "Linear"}
)


def _is_nir_native(parsed_specs: list[ParsedSentence]) -> bool:
    """Return True when *all* valid parsed records use NIR-native concept names."""
    return bool(parsed_specs) and any(
        p["concept"] in _NIR_ALL_CONCEPTS for p in parsed_specs
    )


def _provenance(line: int, *, concept: str, raw: str) -> SourceProvenance:
    return SourceProvenance(line=line, concept=concept, raw=raw)


def _scalar_param(record: NIRNodeRecord, param_name: str) -> float | None:
    raw = record.params.get(param_name)
    if raw is None:
        return None
    values = _vector_values(raw)
    if values.ndim != 1:
        raise LoweringError(
            f"NIR-native deployability bridge expected {record.primitive}.{param_name} "
            f"for node {record.name!r} to be scalar- or vector-shaped."
        )
    if values.size == 0:
        return None
    if values.size > 1 and not np.allclose(values, values[0]):
        raise LoweringError(
            f"NIR-native deployability bridge requires uniform {param_name!r} values on "
            f"node {record.name!r}."
        )
    return float(values[0])


def _build_nir_population_ir(record: NIRNodeRecord, size: int) -> PopulationIR:
    if record.primitive == "Input":
        shape = _require_int_tuple_param(record, "input_type")
        return PopulationIR(
            name=record.name,
            size=size,
            shape=shape,
            role="input",
            population_type="input",
            provenance=[
                _provenance(
                    record.line,
                    concept="network_topology",
                    raw=f"Define an input port named {record.name}.",
                )
            ],
        )
    if record.primitive == "Output":
        shape = _require_int_tuple_param(record, "output_type")
        return PopulationIR(
            name=record.name,
            size=size,
            shape=shape,
            role="output",
            population_type="output",
            provenance=[
                _provenance(
                    record.line,
                    concept="network_topology",
                    raw=f"Define an output port named {record.name}.",
                )
            ],
        )
    if record.primitive == "LIF":
        return PopulationIR(
            name=record.name,
            size=size,
            role=None,
            population_type="lif",
            threshold=_scalar_param(record, "v_threshold"),
            membrane_time_constant=_scalar_param(record, "tau"),
            provenance=[
                _provenance(
                    record.line,
                    concept="threshold_firing",
                    raw=f"Define a LIF neuron named {record.name}.",
                ),
                _provenance(
                    record.line,
                    concept="membrane_potential_decay",
                    raw=f"Define a LIF neuron named {record.name}.",
                ),
            ],
            attributes={
                "nir_native": True,
                "resistance": _scalar_param(record, "r"),
                "leak_voltage": _scalar_param(record, "v_leak"),
            },
        )
    raise LoweringError(
        f"NIR-native deployability bridge does not support population primitive {record.primitive!r}."
    )


def _build_nir_connection_ir(
    source: NIRNodeRecord,
    target: NIRNodeRecord,
    *,
    line: int,
    weight: float | np.ndarray[Any, Any],
) -> ConnectionIR:
    raw = f"Connect {source.name} to {target.name}."
    return ConnectionIR(
        source=source.name,
        target=target.name,
        weight=weight,
        provenance=[
            _provenance(line, concept="network_topology", raw=raw),
            _provenance(line, concept="synaptic_weight", raw=raw),
        ],
        attributes={"nir_native": True},
    )


def _nir_native_records_to_deploy_ir(spec_text: str) -> NetworkIR:
    records = NIR_CNL_Parser().parse(spec_text)
    node_records = {
        record.name: record for record in records if isinstance(record, NIRNodeRecord)
    }
    edge_records = [record for record in records if isinstance(record, NIREdgeRecord)]

    unsupported_primitives = sorted(
        {
            record.primitive
            for record in node_records.values()
            if record.primitive not in _NIR_DEPLOY_SUPPORTED_PRIMITIVES
        }
    )
    if unsupported_primitives:
        supported = ", ".join(sorted(_NIR_DEPLOY_SUPPORTED_PRIMITIVES))
        unsupported = ", ".join(unsupported_primitives)
        raise LoweringError(
            "NIR-native deployability currently supports only "
            f"{supported}; found unsupported primitive(s): {unsupported}."
        )

    outgoing: dict[str, list[str]] = defaultdict(list)
    incoming: dict[str, list[str]] = defaultdict(list)
    for edge in edge_records:
        if edge.src not in node_records or edge.target not in node_records:
            raise LoweringError(
                f"NIR-native deployability bridge found an edge referencing an undeclared node: "
                f"{edge.src!r} -> {edge.target!r}."
            )
        outgoing[edge.src].append(edge.target)
        incoming[edge.target].append(edge.src)

    sizes = _propagate_nir_sizes(node_records, outgoing, incoming)
    network = NetworkIR()

    for name, record in sorted(node_records.items()):
        if record.primitive in _NIR_DEPLOY_POPULATION_PRIMITIVES:
            # Key by the population's own normalised name, not the record's.
            # `PopulationIR` and `ConnectionIR` both lower-case their identifiers,
            # so keying by the raw CNL name ("nir.LIF_1") left every
            # `populations.get(connection.source)` — which arrives as
            # "nir.lif_1" — returning None. Consumers then saw no port
            # populations to exclude and no sizes: a 784→256→10 network was
            # reported as "4 layers … 0×0 → 0×0 → 0×0 → 0×0".
            population = _build_nir_population_ir(record, sizes[name])
            network.populations[population.name] = population

    for edge in edge_records:
        src_record = node_records[edge.src]
        target_record = node_records[edge.target]

        if src_record.primitive == "Linear" or target_record.primitive == "Linear":
            if src_record.primitive != "Linear":
                continue
            parents = incoming.get(src_record.name, [])
            children = outgoing.get(src_record.name, [])
            if len(parents) != 1 or len(children) != 1:
                raise LoweringError(
                    f"NIR-native deployability bridge requires linear node {src_record.name!r} "
                    "to have exactly one incoming and one outgoing edge."
                )
            parent_record = node_records[parents[0]]
            child_record = node_records[children[0]]
            if (
                parent_record.primitive not in _NIR_DEPLOY_POPULATION_PRIMITIVES
                or child_record.primitive not in _NIR_DEPLOY_POPULATION_PRIMITIVES
            ):
                raise LoweringError(
                    f"NIR-native deployability bridge requires linear node {src_record.name!r} "
                    "to connect population-like nodes."
                )
            if edge.target != child_record.name:
                continue
            network.connections.append(
                _build_nir_connection_ir(
                    parent_record,
                    child_record,
                    line=edge.line,
                    weight=_linear_weight_matrix(src_record),
                )
            )
            continue

        if (
            src_record.primitive in _NIR_DEPLOY_POPULATION_PRIMITIVES
            and target_record.primitive in _NIR_DEPLOY_POPULATION_PRIMITIVES
        ):
            network.connections.append(
                _build_nir_connection_ir(
                    src_record,
                    target_record,
                    line=edge.line,
                    weight=1.0,
                )
            )

    if not network.populations:
        raise LoweringError(
            "NIR-native deployability bridge could not derive any populations."
        )
    return network


def build_deploy_ir_from_spec_text(
    spec_text: str,
    parsed_specs: list[ParsedSentence] | None = None,
) -> NetworkIR:
    """Build deploy-planner IR from either legacy or current NIR-native Studio specs."""
    if parsed_specs is None:
        parse_results = parse_spec_text(spec_text)
        parsed_specs = [
            item["parsed"]
            for item in parse_results
            if item["valid"] and item["parsed"] is not None
        ]
    if _is_nir_native(parsed_specs):
        return _nir_native_records_to_deploy_ir(spec_text)
    return build_ir_from_spec_text(spec_text, parsed_specs)


def _validate_nir_native(spec_text: str, backend: str) -> dict[str, Any]:
    """Validate a NIR-native CNL spec using the NIR-aware layer1/layer2 validators.

    Bypasses the biological-grammar lowering pipeline (``lower_to_ir``) and
    routes directly to ``validate_nir_records`` so that NIR-native LIF/Linear/
    CubaLIF networks receive proper invariant checking and topology analysis.
    """
    from neurocnl.layers.layer1_validator import validate_nir_records as l1_nir
    from neurocnl.layers.layer2_validator import validate_nir_records as l2_nir
    from neurocnl.nir_cnl.ir_types import NIREdgeRecord, NIRNodeRecord
    from neurocnl.nir_cnl.parser import NIR_CNL_Parser
    from neurocnl.planner import PlannerResult

    records = NIR_CNL_Parser().parse(spec_text)
    nir_records: list[NIRNodeRecord | NIREdgeRecord | NetworkContainer] = [
        r for r in records if isinstance(r, NIRNodeRecord | NIREdgeRecord)
    ]

    l1 = l1_nir(nir_records, backend=backend)
    l2 = l2_nir(nir_records)

    l1_passed = [
        {
            "name": n,
            "description": f"NIR invariant '{n}' satisfied",
            "reason": f"NIR invariant '{n}' satisfied",
            "result": True,
            "code": n,
            "message": f"NIR invariant '{n}' satisfied",
            "source": "layer1",
            "lines": [],
        }
        for n in l1["passed"]
    ]
    l1_failed = [
        {
            **normalize_cnl_error_item(failure, source="layer1"),
            "result": False,
        }
        for failure in l1["failed"]
    ]
    l1_warnings = [
        normalize_cnl_error_item(warning, source="layer1")
        for warning in l1.get("warnings", [])
    ]
    l2_failed = [
        normalize_cnl_error_item(failure, source="layer2")
        for failure in l2["checks_failed"]
    ]

    # For NIR-native, all defined primitives are directly representable in NIR.
    # Verdict is "faithful" when both layers pass, otherwise "approximate".
    overall = l1["overall"] and l2["overall"]
    verdict = "faithful" if overall else "approximate"
    planner = PlannerResult(
        backend=backend,
        verdict=verdict,
        supported_concepts=sorted(l2.get("neurons_found", [])),
        approximated_concepts=[],
        unsupported_concepts=[],
        warnings=[
            w.get("message", "") for w in l1.get("warnings", []) if w.get("message")
        ],
    )

    return {
        "layer1": {
            "overall": l1["overall"],
            "passed": l1_passed,
            "failed": l1_failed,
            "warnings": l1_warnings,
        },
        "layer2": {
            "overall": l2["overall"],
            "checks_passed": l2["checks_passed"],
            "checks_failed": l2_failed,
            "neurons_found": l2.get("neurons_found", []),
        },
        "overall": overall,
        "planner": planner,
    }


def validate_spec(
    spec_text: str, user_params: dict[str, Any], backend: str = "nir"
) -> dict[str, Any]:
    """Run Layer 1 + Layer 2 validation and return a combined result."""
    parse_results = parse_spec_text(spec_text)

    parse_errors = [r["error_detail"] for r in parse_results if not r["valid"]]
    if parse_errors:
        failed_invariants = [
            {
                **normalize_cnl_error_item(error, source="parser"),
                "name": "ParseError",
                "result": False,
            }
            for error in parse_errors
            if error is not None
        ]
        return {
            "layer1": {
                "overall": False,
                "passed": [],
                "failed": failed_invariants,
                "warnings": [],
            },
            "layer2": {
                "overall": False,
                "checks_passed": [],
                "checks_failed": failed_invariants,
                "neurons_found": [],
            },
            "overall": False,
            "planner": None,
        }

    parsed_specs = [
        r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
    ]

    # NIR-native specs (concepts are NIR primitive names like LIF, Linear, Connect) must
    # bypass lower_to_ir and use the dedicated NIR-aware validators instead.
    if _is_nir_native(parsed_specs):
        return _validate_nir_native(spec_text, backend)

    params, param_provenance = default_params_with_provenance(parsed_specs)
    apply_user_params(params, param_provenance, user_params)

    planner = None
    lowering_diagnostic: dict[str, Any] | None = None
    materializer_diagnostic: dict[str, Any] | None = None
    ir_model = None
    try:
        ir_model = build_ir_from_spec_text(spec_text, parsed_specs)
        planner = plan_backend_support(ir_model, backend)
    except LoweringError as exc:
        lowering_diagnostic = {
            **normalize_cnl_error_item(
                {"code": "lowering_failed", "message": str(exc)},
                source="lowering",
            ),
            "name": "LoweringError",
            "result": False,
        }

    if ir_model is not None:
        try:
            _materialize_to_nir(ir_model)
        except MaterializerError as exc:
            materializer_diagnostic = {
                **normalize_cnl_error_item(
                    {"code": "materializer_failed", "message": str(exc)},
                    source="materializer",
                ),
                "name": "MaterializerError",
                "result": False,
            }

    result = _validate_spec(
        parsed_specs,
        params,
        backend=backend,
        param_provenance=param_provenance,
    )

    # Reshape to match existing API schema expectations
    layer1_failed = [
        {
            **normalize_cnl_error_item(failure, source="layer1"),
            "result": False,
        }
        for failure in result["layer1"]["failed"]
    ]
    layer1_warnings = [
        normalize_cnl_error_item(warning, source="layer1")
        for warning in result["layer1"].get("warnings", [])
    ]
    layer2_failed = [
        normalize_cnl_error_item(failure, source="layer2")
        for failure in result["layer2"]["checks_failed"]
    ]

    # Append pipeline-level failures (lowering, materializer) as Layer 1 diagnostics
    # so /api/validate and /api/generate agree on what constitutes a broken spec.
    pipeline_failures: list[dict[str, Any]] = []
    if lowering_diagnostic is not None:
        pipeline_failures.append(lowering_diagnostic)
    if materializer_diagnostic is not None:
        pipeline_failures.append(materializer_diagnostic)

    has_pipeline_failure = bool(pipeline_failures)
    combined_layer1_failed = layer1_failed + pipeline_failures
    layer1_overall = result["layer1"]["overall"] and not has_pipeline_failure
    overall = result["overall"] and not has_pipeline_failure

    return {
        "layer1": {
            "overall": layer1_overall,
            "passed": result["layer1"]["passed"],
            "failed": combined_layer1_failed,
            "warnings": layer1_warnings,
        },
        "layer2": {
            "overall": result["layer2"]["overall"],
            "checks_passed": result["layer2"]["checks_passed"],
            "checks_failed": layer2_failed,
            "neurons_found": result["layer2"].get("neurons_found", []),
        },
        "overall": overall,
        "planner": planner,
    }


def simulate_spec(
    spec_text: str,
    params_override: dict[str, Any],
    duration: float,
    dt: float,
    backend: str = "nir",
) -> dict[str, Any]:
    """Simulation is intentionally unsupported on the NIR-only product surface."""
    raise StructuredJobError(
        {
            "error": "unsupported_backend",
            "messages": [
                "Simulation is no longer supported on the NIR-only NeuroCNL surface."
            ],
            "items": [
                {
                    "code": "nir_simulation_unsupported",
                    "message": (
                        "Simulation is no longer supported on the NIR-only NeuroCNL surface."
                    ),
                    "hint": (
                        "Use Generate or Export -> NIR for compilation, or consume the NIR "
                        "artifact in a downstream runtime."
                    ),
                    "examples": [
                        "POST /api/generate to inspect the NIR topology",
                        "POST /api/export with format='nir' to download the artifact",
                    ],
                    "source": "simulate",
                }
            ],
        }
    )
