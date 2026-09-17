"""Layer 1 Validator.

Validates parsed CNL specifications against the physical invariants
defined in layer1_invariants.py.

`validate()` is live via the canvas/notebook `lif_population`/`adaptive_lif`
node validation path (`neurosim/app/services/nir_support.py:validate_semantics`)
which always uses the default "nengo" backend. Hardware-backend support
(loihi/akida/spinnaker/teensy) was removed 2026-07-04 as dead code — no live
caller ever passes those backend values (see
current tasks/2026-07-04/validation-deploy-readiness/audit.md).
"""

import inspect
from collections.abc import Callable
from typing import Any

from pydantic import ValidationError

from neurocnl.cnl.types import ParsedSentence
from neurocnl.contracts import LIFNeuronContract
from neurocnl.ir.types import NetworkIR

try:
    from neurocnl.layers.layer1_invariants import (
        ALL_INVARIANTS,
        NIR_CUBALIF_INVARIANTS,
        NIR_LIF_INVARIANTS,
    )
except ImportError:
    from layer1_invariants import (  # type: ignore[no-redef]
        ALL_INVARIANTS,
        NIR_CUBALIF_INVARIANTS,
        NIR_LIF_INVARIANTS,
    )

from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    ArrayValues,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
)

INVARIANT_FIELDS: dict[str, list[str]] = {
    "threshold_above_resting": ["threshold", "resting_potential"],
    "refractory_period_positive": ["refractory_period"],
    "time_constant_positive": ["tau"],
    "reset_at_or_below_threshold": ["reset_potential", "threshold"],
    "membrane_potential_decays_toward_rest": [
        "tau",
        "resting_potential",
        "current_voltage",
    ],
    "axonal_delay_in_range": ["axonal_delay", "max_axonal_delay"],
    "population_neuron_count_within_bounds": ["population_n_neurons"],
    "population_dimensions_positive": ["population_dimensions"],
    "population_radius_positive": ["population_radius"],
    "learning_rate_positive": ["learning_rate"],
    "network_timestep_positive": ["network_timestep"],
    "delay_quantization_step_positive": ["delay_quantization_step"],
    "biological_speed_multiplier_positive": ["biological_speed_multiplier"],
    "delay_quantization_not_finer_than_timestep": [
        "delay_quantization_step",
        "network_timestep",
    ],
    "adaptive_spiking_tau_positive": ["adaptation_tau"],
}

INVARIANT_FAILURE_MESSAGES: dict[str, str] = {}


def _normalize_loc(loc: Any) -> str | None:
    """Convert a Pydantic location tuple into a field name."""
    if isinstance(loc, tuple) and loc:
        return str(loc[-1])
    if isinstance(loc, str):
        return loc
    return None


def _lines_for_fields(
    fields: list[str], param_provenance: dict[str, dict[str, Any]]
) -> list[int]:
    """Collect unique line numbers for a list of parameter fields."""
    lines: set[int] = set()
    for field in fields:
        provenance = param_provenance.get(field, {})
        for line in provenance.get("lines", []):
            if line is not None:
                lines.add(int(line))
        single_line = provenance.get("line")
        if single_line is not None:
            lines.add(int(single_line))
    return sorted(lines)


def _build_failure(
    *,
    code: str,
    message: str,
    fields: list[str],
    neuron_params: dict[str, Any],
    param_provenance: dict[str, dict[str, Any]],
    name: str | None = None,
) -> dict[str, Any]:
    """Create a normalized Layer 1 failure payload."""
    primary_field = fields[0] if fields else None
    primary_value = neuron_params.get(primary_field) if primary_field else None
    lines = _lines_for_fields(fields, param_provenance)
    detail = {
        "name": name or code,
        "reason": message,
        "description": message,
        "code": code,
        "message": message,
        "source": "layer1",
        "field": primary_field,
        "value": primary_value,
        "lines": lines,
    }
    if primary_field is not None and primary_field in param_provenance:
        raw = param_provenance[primary_field].get("raw")
        if raw:
            detail["raw"] = raw
    return detail


def _build_warning(
    *,
    code: str,
    message: str,
    fields: list[str],
    neuron_params: dict[str, Any],
    param_provenance: dict[str, dict[str, Any]],
    name: str | None = None,
) -> dict[str, Any]:
    """Create a normalized Layer 1 warning payload."""
    detail = _build_failure(
        code=code,
        message=message,
        fields=fields,
        neuron_params=neuron_params,
        param_provenance=param_provenance,
        name=name,
    )
    detail["severity"] = "warning"
    return detail


def _apply_timing_declarations(
    parsed_specs: list[ParsedSentence],
    neuron_params: dict[str, Any],
    param_provenance: dict[str, dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    """Overlay timing declarations parsed from CNL onto validation params."""
    params = dict(neuron_params)
    provenance = dict(param_provenance)

    for spec in parsed_specs:
        if spec["concept"] != "timing_declaration":
            continue

        condition = spec.get("condition") or ""
        line = spec.get("line")
        base_provenance = {
            "line": line,
            "lines": [line] if line is not None else [],
            "raw": spec.get("raw"),
            "source": "spec",
        }

        if condition.startswith("timestep of "):
            value = float(
                condition.removeprefix("timestep of ").removesuffix(" seconds")
            )
            params["network_timestep"] = value
            provenance["network_timestep"] = {
                **base_provenance,
                "field": "network_timestep",
                "value": value,
            }
        elif condition.startswith("delay quantization of "):
            value = float(
                condition.removeprefix("delay quantization of ").removesuffix(
                    " seconds"
                )
            )
            params["delay_quantization_step"] = value
            provenance["delay_quantization_step"] = {
                **base_provenance,
                "field": "delay_quantization_step",
                "value": value,
            }
        elif condition.startswith("biological speed multiplier of "):
            value = float(condition.removeprefix("biological speed multiplier of "))
            params["biological_speed_multiplier"] = value
            provenance["biological_speed_multiplier"] = {
                **base_provenance,
                "field": "biological_speed_multiplier",
                "value": value,
            }

    return params, provenance


def validate(
    _parsed_specs: list[ParsedSentence],
    neuron_params: dict[str, Any],
    backend: str = "nengo",
    param_provenance: dict[str, dict[str, Any]] | None = None,
    ir: NetworkIR | None = None,
) -> dict[str, Any]:
    """Validate parsed CNL sentences against Layer 1 physical invariants.

    Parameters
    ----------
    _parsed_specs : list[ParsedSentence]
        List of parsed CNL sentences.
        Reserved for future invariants that depend on parsed CNL sentences.
        Currently unused — invariants are purely parameter-based.
    neuron_params : dict
        Neuron parameters: tau, threshold, reset_potential, refractory_period,
        resting_potential.
    backend : str
        "nengo" (default). Hardware-specific backends (loihi/akida/spinnaker/
        teensy) were removed 2026-07-04 as dead code — no live caller ever
        passed those values.

    Returns
    -------
    dict
        Validation report with keys:
        - passed: list of invariant names that passed
        - failed: list of dicts with 'name' and 'reason' for each failure
        - warnings: list of advisory warnings
        - overall: True if all passed, False if any failed
    """
    param_provenance = param_provenance or {}
    neuron_params, param_provenance = _apply_timing_declarations(
        _parsed_specs,
        neuron_params,
        param_provenance,
    )
    invariants: dict[str, Callable[..., bool]] = dict(ALL_INVARIANTS)

    passed = []
    failed = []
    warnings: list[Any] = []

    # First, validate against Pydantic contracts
    try:
        LIFNeuronContract(**neuron_params)
    except ValidationError as e:
        for error in e.errors():
            field = _normalize_loc(error.get("loc"))
            fields = [field] if field is not None else []
            message = f"LIFNeuronContract: {error['msg']}"
            if field is not None:
                message += f" (field: {field}, value: {neuron_params.get(field)!r})"
            failed.append(
                _build_failure(
                    code="contract_violation",
                    name="ContractViolation",
                    message=message,
                    fields=fields,
                    neuron_params=neuron_params,
                    param_provenance=param_provenance,
                )
            )

    # Then run functional invariants (for backward compatibility and detailed reporting)
    for name, invariant_fn in invariants.items():
        try:
            if "ir" in inspect.signature(invariant_fn).parameters:
                result = invariant_fn(neuron_params, ir=ir)
            else:
                result = invariant_fn(neuron_params)
            if result:
                passed.append(name)
            else:
                fields = INVARIANT_FIELDS.get(name, [])
                field_summary = ", ".join(
                    f"{field}={neuron_params.get(field)!r}"
                    for field in fields
                    if field in neuron_params
                )
                message = INVARIANT_FAILURE_MESSAGES.get(
                    name, f"Invariant '{name}' violated."
                )
                if field_summary:
                    message += f" Relevant values: {field_summary}."
                failed.append(
                    _build_failure(
                        code=name,
                        message=message,
                        fields=fields,
                        neuron_params=neuron_params,
                        param_provenance=param_provenance,
                    )
                )
        except KeyError as e:
            missing_field = str(e).strip("'")
            failed.append(
                _build_failure(
                    code=name,
                    message=f"Missing parameter {missing_field!r} required by invariant '{name}'.",
                    fields=[missing_field],
                    neuron_params=neuron_params,
                    param_provenance=param_provenance,
                )
            )

    return {
        "passed": passed,
        "failed": failed,
        "warnings": warnings,
        "overall": len(failed) == 0,
    }


# Primitive names considered spiking neurons in NIR
_NIR_NEURON_PRIMITIVES = {"LIF", "CubaLIF", "LI", "CubaLI", "IF", "I"}

# Maps primitive name → invariant registry
_NIR_INVARIANT_REGISTRIES: dict[str, dict[str, Callable[[dict[str, Any]], bool]]] = {
    "LIF": NIR_LIF_INVARIANTS,
    "CubaLIF": NIR_CUBALIF_INVARIANTS,
    # LI, CubaLI, IF, I: no physical invariants defined yet — add when needed
}


def validate_nir_records(
    records: list[NIRNodeRecord | NIREdgeRecord | NetworkContainer],
    backend: str = "nengo",
) -> dict[str, Any]:
    """
    Validate NIR-native records (output of NIR_CNL_Parser) for physical
    plausibility. Uses NIR parameter names directly (tau, r, v_leak,
    v_threshold, tau_syn, tau_mem) — NOT the old CNL names.

    Returns the same shape as the legacy validate():
        {"passed": list[str], "failed": list[dict], "warnings": list, "overall": bool}
    """
    passed: list[str] = []
    failed: list[dict[str, Any]] = []
    warnings: list[Any] = []

    node_records: list[NIRNodeRecord] = [
        r for r in records if isinstance(r, NIRNodeRecord)
    ]

    for record in node_records:
        primitive = record.primitive

        # ── Physical invariants (LIF, CubaLIF) ──────────────────────────────
        registry = _NIR_INVARIANT_REGISTRIES.get(primitive, {})

        # Resolve params: ArrayValues → first float value; int/float → pass through.
        # An ArraySpec is a shape-only declaration ("with time constant shape
        # (32,)") and carries no value at all, so it is dropped rather than
        # forwarded: every invariant already skips a missing param, whereas
        # passing the object through made float() raise TypeError, which the
        # except-block below turned into a failure dict with no `name` — and that
        # made POST /api/validate answer a bare 500 for a perfectly legal spec.
        flat_params: dict[str, Any] = {}
        for k, v in record.params.items():
            if isinstance(v, ArraySpec):
                continue
            if isinstance(v, ArrayValues):
                flat_params[k] = v.values[0] if v.values else 0.0
            else:
                flat_params[k] = v

        for invariant_name, fn in registry.items():
            tag = f"{record.name}/{invariant_name}"
            try:
                ok = fn(flat_params)
            except Exception as exc:
                failed.append(
                    {
                        "invariant": invariant_name,
                        "node": record.name,
                        "primitive": primitive,
                        "reason": str(exc),
                    }
                )
                continue
            if ok:
                passed.append(tag)
            else:
                failed.append(
                    {
                        "invariant": invariant_name,
                        "node": record.name,
                        "primitive": primitive,
                        "reason": f"{invariant_name} violated for node '{record.name}'",
                    }
                )

        # ── Affine: warn on all-zero weight ──────────────────────────────────
        if primitive == "Affine":
            weight = record.params.get("weight")
            if (
                isinstance(weight, ArrayValues)
                and weight.values
                and all(v == 0.0 for v in weight.values)
            ):
                warnings.append(
                    {
                        "check": "affine_weight_all_zero",
                        "node": record.name,
                        "hint": "Weight matrix is all-zero — this Affine node has no effect.",
                    }
                )

    overall = len(failed) == 0
    return {
        "passed": passed,
        "failed": failed,
        "warnings": warnings,
        "overall": overall,
    }
