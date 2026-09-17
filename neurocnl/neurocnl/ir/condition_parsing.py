"""Condition-string and subject-phrase parsing for the semantic-IR lowering pass.

Extracted from :mod:`neurocnl.ir.lowering` (Stage 6 refactor). This
module owns the "parameter resolution" side of lowering: normalizing
parsed-sentence subjects into population/connection names, and parsing
each concept's free-text ``condition`` string into typed values (numeric
bounds, shapes, connectivity masks, receptor/STP parameter dicts, matrix
declarations). Behaviour and error messages are unchanged by this move;
:mod:`~neurocnl.ir.lowering` calls through here.
"""

from __future__ import annotations

import ast
import re
from typing import Any

import numpy as np

from neurocnl.cnl.types import ParsedSentence
from neurocnl.ir.ir_merge import LoweringError, merge_inferred_population_size
from neurocnl.ir.types import NetworkIR, PopulationIR, SourceProvenance

__all__ = [
    "condition_value",
    "connection_endpoints",
    "lower_matrix_native_weight",
    "normalized_population_subject",
    "parse_connectivity_mask",
    "parse_matrix_shape",
    "parse_population_shape",
    "parse_receptor_dynamics",
    "parse_short_term_plasticity",
    "parse_weight_bounds",
    "population_flattened_size",
    "population_name",
    "population_role",
    "provenance_for",
    "split_projection_targets",
    "stdp_direction",
    "stdp_kind",
]


def provenance_for(spec: ParsedSentence) -> SourceProvenance:
    return SourceProvenance(
        line=spec.get("line"),
        raw=spec.get("raw"),
        concept=spec.get("concept"),
    )


def population_name(subject: str) -> str:
    name = " ".join(subject.strip().lower().split())
    if name.endswith(" membrane potential"):
        name = name[: -len(" membrane potential")]
    for suffix in (" neurons", " neuron", " populations", " population"):
        if name.endswith(suffix):
            name = name[: -len(suffix)]
            break
    return name


def normalized_population_subject(subject: str) -> str:
    name = population_name(subject)
    if name in {"input population", "output population"}:
        return name.removesuffix(" population")
    return name


def population_role(subject: str) -> str | None:
    name = population_name(subject)
    if name in {"input", "input population"}:
        return "input"
    if name in {"output", "output population"}:
        return "output"
    return None


def connection_endpoints(subject: str) -> tuple[str, str]:
    normalized_subject = subject.strip().lower()
    if normalized_subject.startswith("connection from "):
        subject = subject[len("connection from ") :]
    parts = subject.split(" to ", 1)
    if len(parts) != 2:
        raise LoweringError(
            f"Could not normalize connection endpoints from subject {subject!r}."
        )
    return population_name(parts[0]), population_name(parts[1])


def parse_receptor_dynamics(condition: str) -> dict[str, float | str]:
    match = re.search(
        r"(?P<receptor>AMPA|NMDA|GABA_A|GABA_B)\s+receptor\s+dynamics"
        r"(?:\s+WITH\s+time\s+constant\s+of\s+(?P<tau>\d+(?:\.\d+)?)\s+seconds)?",
        condition,
        flags=re.IGNORECASE,
    )
    if match is None:
        raise LoweringError(f"Unsupported receptor dynamics condition {condition!r}.")

    receptor = match.group("receptor").upper()
    tau = match.group("tau")
    data: dict[str, float | str] = {"receptor_type": receptor}
    if tau is not None:
        data["time_constant"] = float(tau)
    return data


def split_projection_targets(condition: str) -> list[str]:
    if not condition.startswith("projects to "):
        raise LoweringError(f"Unsupported network projection condition {condition!r}.")
    targets_text = condition.removeprefix("projects to ")
    return [population_name(target) for target in targets_text.split(", ") if target]


def stdp_kind(condition: str) -> str:
    normalized = condition.lower()
    if normalized.startswith("bcm"):
        return "bcm"
    if normalized.startswith("oja"):
        return "oja"
    return "stdp"


def stdp_direction(action: str | None) -> str | None:
    if action is None:
        return None
    normalized = action.strip().lower()
    if normalized == "strengthen":
        return "strengthen"
    if normalized == "weaken":
        return "weaken"
    return None


def parse_weight_bounds(spec: ParsedSentence) -> tuple[float | None, float | None]:
    condition = (spec.get("condition") or "").lower()
    matches = re.findall(r"-?\d+(?:\.\d+)?", condition)

    if condition.startswith("weight bounds ") and len(matches) >= 2:
        return float(matches[0]), float(matches[1])

    if condition.startswith("weight bound of ") and matches:
        bound = float(matches[0])
        raw_text = f"{spec.get('raw', '')} {spec.get('action', '')}".lower()
        if "below" in raw_text or "minimum" in raw_text:
            return bound, None
        if "exceed" in raw_text or "above" in raw_text or "maximum" in raw_text:
            return None, bound
        if spec.get("negated"):
            return None, bound
        return -abs(bound), abs(bound)

    return None, None


def condition_value(condition: str, prefix: str) -> float | None:
    match = re.search(
        rf"{re.escape(prefix)}(-?\d+(?:\.\d+)?)", condition, flags=re.IGNORECASE
    )
    if match is None:
        return None
    return float(match.group(1))


def parse_population_shape(condition: str) -> tuple[int, ...] | None:
    match = re.search(r"shape\s*\((?P<axes>[\d,\s]+)\)", condition, flags=re.IGNORECASE)
    if match is None:
        return None
    axes = tuple(
        int(part.strip()) for part in match.group("axes").split(",") if part.strip()
    )
    if not axes:
        raise LoweringError(f"Unsupported population shape condition {condition!r}.")
    return axes


def parse_connectivity_mask(mask_literal: str) -> tuple[tuple[int, ...], ...]:
    try:
        parsed = ast.literal_eval(mask_literal)
    except (SyntaxError, ValueError) as exc:
        raise LoweringError(
            f"Unsupported binary connectivity mask {mask_literal!r}."
        ) from exc

    if (
        not isinstance(parsed, list)
        or not parsed
        or not all(isinstance(row, list) for row in parsed)
    ):
        raise LoweringError(f"Unsupported binary connectivity mask {mask_literal!r}.")

    normalized: list[tuple[int, ...]] = []
    expected_width: int | None = None
    for row in parsed:
        if not row:
            raise LoweringError(
                f"Unsupported binary connectivity mask {mask_literal!r}."
            )
        normalized_row = tuple(int(value) for value in row)
        if any(value not in (0, 1) for value in normalized_row):
            raise LoweringError(
                f"Unsupported binary connectivity mask {mask_literal!r}."
            )
        if expected_width is None:
            expected_width = len(normalized_row)
        elif len(normalized_row) != expected_width:
            raise LoweringError(
                f"Unsupported binary connectivity mask {mask_literal!r}."
            )
        normalized.append(normalized_row)
    return tuple(normalized)


def parse_matrix_shape(spec: ParsedSentence) -> tuple[int, int] | None:
    shape = spec.get("weight_shape")
    if shape is None:
        return None
    if len(shape) != 2 or any(int(axis) <= 0 for axis in shape):
        raise LoweringError(f"Unsupported matrix shape declaration {shape!r}.")
    return int(shape[0]), int(shape[1])


def population_flattened_size(population: PopulationIR) -> int | None:
    if population.shape is not None:
        flattened_size = 1
        for axis in population.shape:
            flattened_size *= axis
        return flattened_size
    if population.size is not None and population.size > 0:
        return population.size
    return None


def lower_matrix_native_weight(
    network: NetworkIR,
    *,
    spec: ParsedSentence,
    source: str,
    target: str,
    provenance: SourceProvenance,
) -> tuple[np.ndarray[Any, Any], dict[str, object]]:
    matrix_kind = spec.get("matrix_kind")
    declared_shape = parse_matrix_shape(spec)
    source_size = population_flattened_size(network.populations[source])
    target_size = population_flattened_size(network.populations[target])

    def validate_and_infer_shape(rows: int, cols: int) -> None:
        if declared_shape is not None and declared_shape != (rows, cols):
            raise LoweringError(
                f"Declared matrix shape {declared_shape} does not match literal shape {(rows, cols)} "
                f"for connection {source!r} -> {target!r}."
            )
        if source_size is not None and source_size != cols:
            raise LoweringError(
                f"Source population {source!r} has size {source_size}, but the matrix requires "
                f"{cols} source columns."
            )
        if target_size is not None and target_size != rows:
            raise LoweringError(
                f"Target population {target!r} has size {target_size}, but the matrix requires "
                f"{rows} target rows."
            )
        if source_size is None:
            merge_inferred_population_size(
                network, name=source, provenance=provenance, size=cols
            )
        if target_size is None:
            merge_inferred_population_size(
                network, name=target, provenance=provenance, size=rows
            )

    if matrix_kind == "dense":
        matrix = np.asarray(spec.get("weight_matrix"), dtype=float)
        rows, cols = matrix.shape
        validate_and_infer_shape(rows, cols)
        return matrix, {
            "matrix_kind": "dense",
            "declared_weight_shape": declared_shape,
            "inferred_weight_shape": (rows, cols),
        }

    if matrix_kind == "identity":
        if declared_shape is not None and declared_shape[0] != declared_shape[1]:
            raise LoweringError("Identity matrix declarations must be square.")
        resolved_size = None
        if declared_shape is not None:
            resolved_size = declared_shape[0]
        elif source_size is not None and target_size is not None:
            if source_size != target_size:
                raise LoweringError(
                    f"Identity matrix requires equal source and target sizes, got "
                    f"{source_size} and {target_size}."
                )
            resolved_size = source_size
        elif source_size is not None:
            resolved_size = source_size
        elif target_size is not None:
            resolved_size = target_size
        if resolved_size is None:
            raise LoweringError(
                f"Identity matrix for {source!r} -> {target!r} is ambiguous. Add an explicit "
                "N by N clause or declare deterministic source and target population sizes."
            )
        validate_and_infer_shape(resolved_size, resolved_size)
        return np.eye(resolved_size, dtype=float), {
            "matrix_kind": "identity",
            "declared_weight_shape": declared_shape,
            "inferred_weight_shape": (resolved_size, resolved_size),
        }

    if matrix_kind == "diagonal":
        diagonal_values = np.asarray(spec.get("weight_vector"), dtype=float)
        resolved_size = int(diagonal_values.shape[0])
        if declared_shape is not None and (
            declared_shape[0] != declared_shape[1] or declared_shape[0] != resolved_size
        ):
            raise LoweringError(
                f"Diagonal matrix declaration shape {declared_shape} does not match "
                f"{resolved_size} diagonal values."
            )
        validate_and_infer_shape(resolved_size, resolved_size)
        return np.diag(diagonal_values), {
            "matrix_kind": "diagonal",
            "declared_weight_shape": declared_shape,
            "inferred_weight_shape": (resolved_size, resolved_size),
            "diagonal_values": tuple(float(value) for value in diagonal_values),
        }

    raise LoweringError(
        f"Unsupported matrix-native weight declaration {matrix_kind!r}."
    )


def parse_short_term_plasticity(condition: str) -> dict[str, float | str]:
    match = re.search(
        r"short-term\s+(?P<kind>depression|facilitation)"
        r"(?:\s+WITH\s+recovery\s+time\s+of\s+(?P<recovery>\d+(?:\.\d+)?)\s+seconds)?",
        condition,
        flags=re.IGNORECASE,
    )
    if match is None:
        raise LoweringError(
            f"Unsupported short-term plasticity condition {condition!r}."
        )

    recovery = match.group("recovery")
    data: dict[str, float | str] = {
        "stp_type": match.group("kind").lower(),
        "recovery_time": float(recovery) if recovery is not None else 0.1,
    }
    utilization_match = re.search(
        r"WITH\s+utilization\s+rate\s+of\s+(?P<utilization>\d+(?:\.\d+)?)",
        condition,
        flags=re.IGNORECASE,
    )
    if utilization_match is not None:
        data["utilization_rate"] = float(utilization_match.group("utilization"))
    return data
