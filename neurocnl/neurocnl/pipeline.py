"""Unified pipeline orchestration.

Single entry point for the parse -> validate -> generate -> simulate flow.
Used by both the CLI (run_simulation.py) and the API (simulate router).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from typing import Any, cast

import nir
import structlog

from neurocnl.cnl.document import extract_embedded_ir
from neurocnl.cnl.types import ParsedSentence, ParseResult
from neurocnl.contracts import PipelineResultContract
from neurocnl.export.nir_exporter import ensure_nir_exportable, export_to_nir
from neurocnl.generation.assertion_generator import generate_assertions
from neurocnl.ir import LoweringError, MaterializerError, NetworkIR, lower_to_ir
from neurocnl.layers.layer1_validator import validate as l1_validate
from neurocnl.layers.layer1_validator import validate_nir_records as l1_nir_validate
from neurocnl.layers.layer2_validator import validate_cross_sentence
from neurocnl.layers.layer2_validator import validate_nir_records as l2_nir_validate
from neurocnl.nir_cnl.ir_types import NetworkContainer, NIREdgeRecord, NIRNodeRecord
from neurocnl.planner import PlannerResult, plan_backend_support
from neurocnl.utils import extract_numeric

logger = structlog.get_logger(__name__)

DEFAULT_NEURON_PARAMS: dict[str, Any] = {
    "threshold": 1.0,
    "resting_potential": 0.0,
    "refractory_period": 0.002,
    "tau": 0.02,
    "reset_potential": 0.0,
    "current_voltage": 0.5,
    "synaptic_weight": 1.0,
}
ParamProvenance = dict[str, dict[str, Any]]


@dataclass
class PipelineResult:
    """Result of a full pipeline run."""

    parsed: list[ParsedSentence] = field(default_factory=list)
    ir: NetworkIR | None = None
    planner: PlannerResult | None = None
    generator_fidelity: dict[str, Any] | None = None
    validation: dict[str, Any] = field(default_factory=dict)
    network: object | None = None
    simulation: dict[str, Any] = field(default_factory=dict)
    assertions: dict[str, Any] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    neuron_params: dict[str, Any] = field(default_factory=dict)
    overall_pass: bool = False

    # Extra data for backend / analysis
    probes: dict[str, Any] = field(default_factory=dict)
    summary: dict[str, Any] = field(default_factory=dict)
    benchmarks: dict[str, float] = field(default_factory=dict)

    def to_contract(self) -> PipelineResultContract:
        """Convert result to validated Pydantic contract."""
        return PipelineResultContract(
            parsed=self.parsed,
            validation=self.validation if self.validation else None,
            simulation=self.simulation if self.simulation else None,
            assertions=self.assertions if self.assertions else None,
            errors=self.errors,
            neuron_params=self.neuron_params,
            overall_pass=self.overall_pass,
            probes=self.probes,
            summary=self.summary,
            benchmarks=self.benchmarks,
        )


@dataclass(slots=True)
class NirImportDiagnostic:
    """Structured diagnostic produced while translating NIR back to CNL."""

    code: str
    message: str
    node_id: str | None = None
    primitive: str | None = None
    hint: str | None = None


class NirImportError(Exception):
    """Raised when a NIR graph cannot be translated to canonical CNL."""

    def __init__(self, message: str, diagnostics: list[NirImportDiagnostic]) -> None:
        super().__init__(message)
        self.diagnostics = diagnostics

    def __str__(self) -> str:
        lines = [super().__str__()]
        for diagnostic in self.diagnostics:
            where = f" node={diagnostic.node_id}" if diagnostic.node_id else ""
            primitive = (
                f" primitive={diagnostic.primitive}" if diagnostic.primitive else ""
            )
            hint = f" hint={diagnostic.hint}" if diagnostic.hint else ""
            lines.append(
                f"  [{diagnostic.code}]{where}{primitive}: {diagnostic.message}{hint}"
            )
        return "\n".join(lines)


def default_params_from_specs(parsed_specs: list[ParsedSentence]) -> dict[str, Any]:
    """Build a reasonable neuron_params dict from parsed spec values."""
    params, _ = default_params_with_provenance(parsed_specs)
    return params


def default_params_with_provenance(
    parsed_specs: list[ParsedSentence],
) -> tuple[dict[str, Any], ParamProvenance]:
    """Build neuron params plus source provenance from parsed spec values."""
    params: dict[str, Any] = dict(DEFAULT_NEURON_PARAMS)
    provenance: ParamProvenance = {}
    for spec in parsed_specs:
        cond = spec.get("condition") or ""
        concept = spec["concept"]
        val = extract_numeric(cond)
        if val is None:
            continue
        line = spec.get("line")
        base_provenance = {
            "line": line,
            "lines": [line] if line is not None else [],
            "raw": spec.get("raw"),
            "source": "spec",
        }
        if concept == "threshold_firing":
            params["threshold"] = val
            provenance["threshold"] = {
                **base_provenance,
                "field": "threshold",
                "value": val,
            }
        elif concept == "refractory_period":
            params["refractory_period"] = val
            provenance["refractory_period"] = {
                **base_provenance,
                "field": "refractory_period",
                "value": val,
            }
        elif concept == "membrane_potential_decay":
            params["tau"] = val
            provenance["tau"] = {**base_provenance, "field": "tau", "value": val}
        elif concept == "synaptic_weight":
            params["synaptic_weight"] = val
            provenance["synaptic_weight"] = {
                **base_provenance,
                "field": "synaptic_weight",
                "value": val,
            }
        elif concept == "axonal_delay":
            params["axonal_delay"] = val
            provenance["axonal_delay"] = {
                **base_provenance,
                "field": "axonal_delay",
                "value": val,
            }
        elif concept == "population_coding":
            params["population_n_neurons"] = int(val)
            provenance["population_n_neurons"] = {
                **base_provenance,
                "field": "population_n_neurons",
                "value": int(val),
            }
    return params, provenance


def apply_user_params(
    params: dict[str, Any],
    provenance: ParamProvenance,
    user_params: dict[str, Any] | None,
) -> None:
    """Overlay user params and mark their provenance."""
    if not user_params:
        return
    for key, value in user_params.items():
        if value is None:
            continue
        params[key] = value
        provenance[key] = {
            "field": key,
            "value": value,
            "line": None,
            "lines": [],
            "raw": None,
            "source": "request",
        }


def parse_spec_text(spec_text: str) -> list[ParseResult]:
    """Parse NIR-native CNL text into a list of :class:`ParseResult` dicts.

    Thin adapter over :class:`~neurocnl.nir_cnl.parser.NIR_CNL_Parser`:
    each :class:`~neurocnl.nir_cnl.ir_types.NIRNodeRecord` and
    :class:`~neurocnl.nir_cnl.ir_types.NIREdgeRecord` is converted into
    a ``ParseResult`` so downstream callers that expect the legacy
    sentence-list shape continue to receive a uniform structure.
    Network containers are not surfaced — they are a grammar construct
    rather than a parsed sentence in the legacy sense.

    On parse failure, every collected
    :class:`~neurocnl.nir_cnl.errors.Diagnostic` is converted into one
    invalid ``ParseResult`` so callers can iterate failures the same
    way they iterate successes.
    """
    from neurocnl.nir_cnl.errors import ParseError as _NIRParseError
    from neurocnl.nir_cnl.ir_types import NetworkContainer as _NetworkContainer
    from neurocnl.nir_cnl.ir_types import NIREdgeRecord as _NIREdgeRecord
    from neurocnl.nir_cnl.ir_types import NIRNodeRecord as _NIRNodeRecord
    from neurocnl.nir_cnl.parser import NIR_CNL_Parser as _NIR_CNL_Parser

    try:
        records = _NIR_CNL_Parser().parse(spec_text)
    except _NIRParseError as exc:
        results: list[ParseResult] = []
        for d in exc.errors:
            results.append(
                ParseResult(
                    line=d.line if d.line is not None else 0,
                    raw=d.raw or "",
                    parsed=None,
                    valid=False,
                    error=d.message,
                    error_detail={
                        "line": d.line if d.line is not None else 0,
                        "code": d.code,
                        "message": d.message,
                        "hint": d.hint or "",
                    },
                )
            )
        return results

    results = []
    for rec in records:
        if isinstance(rec, _NetworkContainer):
            # Network containers are a grammar construct, not a parsed
            # sentence; skip them per task 9.2 contract.
            continue
        if isinstance(rec, _NIRNodeRecord):
            raw = f"Define a {rec.primitive} named {rec.name}."
            parsed: ParsedSentence = {
                "concept": rec.primitive,
                "subject": rec.name,
                "action": "",
                "verb": "Define",
                "negated": False,
                "condition": "",
                "raw": raw,
                "line": rec.line,
            }
            results.append(
                ParseResult(
                    line=rec.line,
                    raw=raw,
                    parsed=parsed,
                    valid=True,
                    error=None,
                    error_detail=None,
                )
            )
        elif isinstance(rec, _NIREdgeRecord):
            raw = f"Connect {rec.src} to {rec.target}."
            parsed_edge: ParsedSentence = {
                "concept": "Connect",
                "subject": rec.src,
                "action": "",
                "verb": "Connect",
                "negated": False,
                "condition": rec.target,
                "raw": raw,
                "line": rec.line,
            }
            results.append(
                ParseResult(
                    line=rec.line,
                    raw=raw,
                    parsed=parsed_edge,
                    valid=True,
                    error=None,
                    error_detail=None,
                )
            )
    return results


def _validation_summary(validation: dict[str, Any]) -> str:
    """Build a concise validation summary for pipeline errors."""
    layer1_failed = validation.get("layer1", {}).get("failed", [])
    layer2_failed = validation.get("layer2", {}).get("checks_failed", [])
    if layer1_failed:
        first = layer1_failed[0]
        code = first.get("code") or first.get("name") or "layer1_failure"
        message = (
            first.get("message") or first.get("reason") or "Layer 1 validation failed."
        )
        return f"Layer 1 validation failed ({code}): {message}"
    if layer2_failed:
        first = layer2_failed[0]
        code = first.get("code") or first.get("check") or "layer2_failure"
        message = (
            first.get("message") or first.get("detail") or "Layer 2 validation failed."
        )
        return f"Layer 2 validation failed ({code}): {message}"
    return "Validation failed."


def _probe_label(probe: object) -> str:
    """Extract a human-readable label for a Nengo probe."""
    if hasattr(probe, "label") and probe.label:
        return str(probe.label)
    target = getattr(probe, "target", None)
    target_label = getattr(target, "label", None)
    if target_label:
        return str(target_label)
    if hasattr(target, "ensemble"):
        ens = getattr(target, "ensemble", None)
        return str(getattr(ens, "label", None) or id(ens))
    return str(id(target))


def _compute_summary(probes: dict[str, Any], duration: float) -> dict[str, Any]:
    """Compute summary statistics (spike counts, rates, latency) from probe data."""
    summary: dict[str, Any] = {
        "sensory_spike_count": 0,
        "motor_spike_count": 0,
        "sensory_mean_rate": 0.0,
        "motor_mean_rate": 0.0,
        "first_output_spike": None,
        "input_to_output_latency": None,
    }
    first_sensory: float | None = None
    first_motor: float | None = None

    for key, data in probes.items():
        if data.get("type") != "spike_raster":
            continue
        count = len(data["times"])
        times_list = data["times"]
        first_t = min(times_list) if times_list else None

        if "sensory" in key.lower():
            summary["sensory_spike_count"] = count
            summary["sensory_mean_rate"] = (
                round(count / duration, 1) if duration > 0 else 0.0
            )
            if first_t is not None:
                first_sensory = first_t
        elif "motor" in key.lower():
            summary["motor_spike_count"] = count
            summary["motor_mean_rate"] = (
                round(count / duration, 1) if duration > 0 else 0.0
            )
            if first_t is not None:
                first_motor = first_t
                summary["first_output_spike"] = round(first_t, 6)

    if first_sensory is not None and first_motor is not None:
        summary["input_to_output_latency"] = round(first_motor - first_sensory, 6)

    return summary


def build_ir_from_spec_text(
    spec_text: str,
    parsed_specs: list[ParsedSentence] | None = None,
) -> NetworkIR:
    """Build IR from a CNL document, honoring embedded round-trip metadata when present."""
    embedded_ir = extract_embedded_ir(spec_text)
    if embedded_ir is not None:
        return embedded_ir
    if parsed_specs is None:
        parse_results = parse_spec_text(spec_text)
        parsed_specs = [
            item["parsed"]
            for item in parse_results
            if item["valid"] and item["parsed"] is not None
        ]
    return lower_to_ir(parsed_specs)


def generate_cnl_from_nir(graph: nir.NIRGraph) -> str:
    """Generate NIR-native CNL text from a NIR graph (all 19 primitives).

    Uses :class:`~neurocnl.nir_cnl.renderer.NIR_Renderer` to render the graph
    directly to NIR-native CNL. Unsupported node types produce a comment line
    (``# unsupported: ...``) rather than raising an exception.
    """
    from neurocnl.nir_cnl.renderer import NIR_Renderer

    renderer = NIR_Renderer()
    return renderer.render(graph)


def validate_spec(
    parsed_specs: (
        list[ParsedSentence] | list[NIRNodeRecord | NIREdgeRecord | NetworkContainer]
    ),
    neuron_params: dict[str, Any],
    backend: str = "nir",
    param_provenance: ParamProvenance | None = None,
    ir: NetworkIR | None = None,
) -> dict[str, Any]:
    """Run Layer 1 + Layer 2 validation and return a combined result.

    Parameters
    ----------
    parsed_specs : list[ParsedSentence]
        List of parsed CNL sentences.
    neuron_params : dict
        Parameters for neuron validation.
    backend : str
        The simulation backend.

    Returns
    -------
    dict
        Combined validation result.
    """
    # Detect whether parsed_specs contains NIR records (new pipeline) or
    # legacy ParsedSentence dicts (old pipeline, kept for backward compat)
    _is_nir = bool(parsed_specs) and isinstance(
        parsed_specs[0], NIRNodeRecord | NIREdgeRecord
    )

    if _is_nir:
        nir_specs = cast(
            "list[NIRNodeRecord | NIREdgeRecord | NetworkContainer]", parsed_specs
        )
        l1 = l1_nir_validate(nir_specs, backend=backend)
        l2 = l2_nir_validate(nir_specs)
    else:
        cnl_specs = cast("list[ParsedSentence]", parsed_specs)
        l1 = l1_validate(
            cnl_specs,
            neuron_params,
            backend=backend,
            param_provenance=param_provenance,
            ir=ir,
        )
        l2 = validate_cross_sentence(cnl_specs)

    l1_passed = [
        {
            "name": n,
            "reason": f"Invariant '{n}' satisfied",
            "description": f"Invariant '{n}' satisfied",
            "result": True,
            "code": n,
            "message": f"Invariant '{n}' satisfied",
            "source": "layer1",
            "lines": [],
        }
        for n in l1["passed"]
    ]
    l1_failed = []
    l1_warnings = []
    for failure in l1["failed"]:
        normalized = dict(failure)
        normalized.setdefault("code", failure["name"])
        normalized.setdefault("message", failure["reason"])
        normalized.setdefault("description", failure["reason"])
        normalized.setdefault("source", "layer1")
        normalized.setdefault("lines", [])
        normalized["result"] = False
        l1_failed.append(normalized)
    for warning in l1.get("warnings", []):
        normalized = dict(warning)
        normalized.setdefault("code", warning["name"])
        normalized.setdefault("message", warning["reason"])
        normalized.setdefault("description", warning["reason"])
        normalized.setdefault("source", "layer1")
        normalized.setdefault("lines", [])
        normalized.setdefault("severity", "warning")
        l1_warnings.append(normalized)

    return {
        "layer1": {
            "overall": l1["overall"],
            "passed": l1_passed,
            "failed": l1_failed,
            "warnings": l1_warnings,
            "raw": l1,
        },
        "layer2": {
            "overall": l2["overall"],
            "checks_passed": l2["checks_passed"],
            "checks_failed": [dict(failure) for failure in l2["checks_failed"]],
            "neurons_found": l2.get("neurons_found", []),
            "raw": l2,
        },
        "overall": l1["overall"] and l2["overall"],
    }


def run_pipeline(
    spec_text: str,
    backend: str = "nir",
    verbose: bool = False,
    user_params: dict[str, Any] | None = None,
    skip_simulation: bool = False,
    skip_assertions: bool = False,
    duration: float = 1.0,
    dt: float = 0.001,
    probe_all: bool = False,
) -> PipelineResult:
    """Execute the full pipeline: parse -> validate -> generate -> simulate -> assert.

    Parameters
    ----------
    spec_text : str
        Raw CNL spec text (multi-line).
    backend : str
        "nengo" (default) or "loihi".
    verbose : bool
        Enable verbose logging.
    user_params : dict | None
        User-supplied parameter overrides.
    skip_simulation : bool
        If True, stop after network generation.
    skip_assertions : bool
        If True, skip Layer 3 assertion generation/execution.
    duration : float
        Simulation duration in seconds.
    dt : float
        Simulation time step in seconds.
    probe_all : bool
        If True, add probes to all ensembles for output data extraction.

    Returns
    -------
    PipelineResult
        Aggregated result with parsed specs, validation, network, simulation, assertions.
    """
    logger.info("pipeline_started", backend=backend)
    result = PipelineResult()

    # Step 1: Parse
    start_parse = time.perf_counter()
    parse_results = parse_spec_text(spec_text)
    result.benchmarks["parse_latency"] = time.perf_counter() - start_parse

    result.parsed = [
        r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
    ]

    parse_error_details = [r["error_detail"] for r in parse_results if not r["valid"]]
    parse_errors = [
        f"line {detail['line']}: {detail['message']}"
        for detail in parse_error_details
        if detail is not None
    ]
    if parse_errors:
        if not result.parsed:
            result.errors.append(
                f"No valid CNL sentences found. Parse errors: {parse_errors}"
            )
        else:
            result.errors.append(
                f"Some CNL sentences failed to parse. Parse errors: {parse_errors}"
            )
        logger.error("parse_failed", errors=parse_errors)
        return result

    logger.info(
        "parsed_specs",
        count=len(result.parsed),
        latency=result.benchmarks["parse_latency"],
    )

    # Step 2: Lower to IR
    start_lower = time.perf_counter()
    try:
        result.ir = build_ir_from_spec_text(spec_text, result.parsed)
        result.benchmarks["lowering_latency"] = time.perf_counter() - start_lower
        logger.info("lowering_completed", latency=result.benchmarks["lowering_latency"])
    except LoweringError as e:
        result.benchmarks["lowering_latency"] = time.perf_counter() - start_lower
        result.errors.append(f"IR lowering error: {e}")
        logger.error("lowering_failed", error=str(e))
        return result

    # Step 3: Build params
    params, param_provenance = default_params_with_provenance(result.parsed)
    apply_user_params(params, param_provenance, user_params)
    result.neuron_params = params

    # Step 4: Validate
    start_val = time.perf_counter()
    result.validation = validate_spec(
        result.parsed,
        params,
        backend=backend,
        param_provenance=param_provenance,
        ir=result.ir,
    )
    result.benchmarks["validation_latency"] = time.perf_counter() - start_val

    # Step 4.5: Plan Backend Support (now that we have validator report)
    if result.ir is not None:
        result.planner = plan_backend_support(
            result.ir, backend, validator_report=result.validation.get("layer1")
        )

    if not result.validation["overall"]:
        result.errors.append(_validation_summary(result.validation))
        logger.error(
            "validation_failed", latency=result.benchmarks["validation_latency"]
        )
        return result

    logger.info("validation_passed", latency=result.benchmarks["validation_latency"])

    # Steps 5 & 6 (Nengo network generation and simulation) have been removed.
    # The active product surface uses compile_to_nir() for NIR-native workflows.
    # result.network remains None; skip_simulation is now a no-op parameter kept
    # for backwards-compatible call sites.

    # Step 7: Assertions
    if not skip_assertions:
        start_assert = time.perf_counter()
        with tempfile.TemporaryDirectory() as tmpdir:
            assertion_path = os.path.join(tmpdir, "test_layer3_assertions.py")
            generate_assertions(result.parsed, output_path=assertion_path)

            pytest_result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "pytest",
                    assertion_path,
                    "-v",
                    "--tb=short",
                ],
                capture_output=True,
                text=True,
            )
        result.benchmarks["assertion_latency"] = time.perf_counter() - start_assert

        passed = 0
        failed = 0
        for line in pytest_result.stdout.splitlines():
            if "passed" in line:
                m = re.search(r"(\d+)\s+passed", line)
                if m:
                    passed = int(m.group(1))
            if "failed" in line:
                m = re.search(r"(\d+)\s+failed", line)
                if m:
                    failed = int(m.group(1))

        result.assertions = {
            "passed": passed,
            "failed": failed,
            "returncode": pytest_result.returncode,
        }
        logger.info(
            "assertions_completed",
            passed=passed,
            failed=failed,
            latency=result.benchmarks["assertion_latency"],
        )

    # Determine overall pass
    result.overall_pass = (
        result.validation["overall"]
        and not result.errors
        and (
            skip_assertions
            or (
                result.assertions.get("failed", 0) == 0
                and result.assertions.get("passed", 0) > 0
            )
        )
    )
    logger.info("pipeline_finished", overall_pass=result.overall_pass)

    return result


def compile_to_nir(spec_text: str, filename: str | os.PathLike[str]) -> NetworkIR:
    """Compile a CNL spec directly to a NIR artifact without using Nengo.

    .. deprecated::
        Use :func:`neurocnl.compile.compile_to_nir` instead.  That function
        returns a ``nir.NIRGraph`` directly, accepts an optional ``save_to``
        keyword argument, and raises structured :class:`~neurocnl.compile.CompileError`
        diagnostics instead of plain ``ValueError``.
    """
    import warnings

    warnings.warn(
        "neurocnl.pipeline.compile_to_nir() is deprecated; "
        "use neurocnl.compile.compile_to_nir() instead.",
        DeprecationWarning,
        stacklevel=2,
    )
    parse_results = parse_spec_text(spec_text)
    parse_errors = [
        r["error"] for r in parse_results if not r["valid"] and r["error"] is not None
    ]
    if parse_errors:
        raise ValueError(
            "Some CNL sentences failed to parse:\n" + "\n".join(parse_errors)
        )

    parsed_specs = [
        r["parsed"] for r in parse_results if r["valid"] and r["parsed"] is not None
    ]
    if not parsed_specs:
        raise ValueError("No valid CNL sentences found.")

    embedded_ir = extract_embedded_ir(spec_text)
    try:
        if embedded_ir is None:
            ensure_nir_exportable(parsed_specs)
            ir_model = lower_to_ir(parsed_specs)
        else:
            ir_model = embedded_ir
        export_to_nir(ir_model, os.fspath(filename))
    except LoweringError as exc:
        raise ValueError(str(exc)) from exc
    except MaterializerError as exc:
        raise ValueError(str(exc)) from exc
    return ir_model
