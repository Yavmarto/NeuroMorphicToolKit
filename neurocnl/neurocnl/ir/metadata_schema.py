"""Shared metadata helpers for advisory NIR semantics."""

from __future__ import annotations

from typing import Any

ADVISORY_SEMANTICS_VERSION = 1

VALID_EFFECT_TYPES: frozenset[str] = frozenset({"excitatory", "inhibitory", "modulatory"})

# Minimum field required in every CNL-lowered neuromodulation rule.
# The CNL lowering always sets "modulator" (the modulator name / subject).
# Other keys (factor, condition, action, negated, raw) are populated on a
# best-effort basis and are allowed to be absent.
_NEUROMODULATION_REQUIRED_FIELDS = frozenset({"modulator"})


def validate_neuromodulation_rule(rule: dict) -> None:  # type: ignore[type-arg]
    """Validate a single neuromodulation rule dict against the CNL-native schema.

    The CNL lowering pipeline always emits at minimum ``{"modulator": ...}``.
    If ``effect_type`` is present it must be one of the known values.

    Raises:
        TypeError: if rule is not a dict.
        ValueError: if the required ``modulator`` field is missing, or
            ``effect_type`` is present but invalid.
    """
    if not isinstance(rule, dict):
        raise TypeError("Neuromodulation rule must be a dict")

    missing_fields = sorted(_NEUROMODULATION_REQUIRED_FIELDS - rule.keys())
    if missing_fields:
        raise ValueError(f"Neuromodulation rule missing required field(s): {missing_fields}")

    if "effect_type" in rule:
        effect_type = rule["effect_type"]
        if effect_type not in VALID_EFFECT_TYPES:
            raise ValueError(
                f"Neuromodulation rule has invalid effect_type {effect_type!r}; "
                f"expected one of {sorted(VALID_EFFECT_TYPES)}"
            )


def advisory_population_semantics(*, shape_intent: list[int] | None) -> dict[str, Any]:
    """Build the reserved advisory metadata block for a population node."""
    return {
        "schema_version": ADVISORY_SEMANTICS_VERSION,
        "surface": "population",
        "shape_intent": shape_intent,
    }


def advisory_connection_semantics(
    *,
    delay: float | None,
    learning_rules: list[dict[str, Any]],
    connectivity_pattern: str | None,
    shape_intent: dict[str, list[int]] | None,
    locality_radius: float | None,
    connection_density: float | None,
) -> dict[str, Any]:
    """Build the reserved advisory metadata block for a connection node."""
    return {
        "schema_version": ADVISORY_SEMANTICS_VERSION,
        "surface": "connection",
        "delay": delay,
        "learning_rules": learning_rules,
        "connectivity_pattern": connectivity_pattern,
        "shape_intent": shape_intent,
        "locality_radius": locality_radius,
        "connection_density": connection_density,
    }


def advisory_delay_semantics(
    *,
    delay: float,
    shape_intent: dict[str, list[int]] | None,
) -> dict[str, Any]:
    """Build the reserved advisory metadata block for a delay node."""
    return {
        "schema_version": ADVISORY_SEMANTICS_VERSION,
        "surface": "delay",
        "delay": delay,
        "shape_intent": shape_intent,
    }


def advisory_graph_semantics(
    *,
    timing_declarations: list[dict[str, Any]],
    global_receptor_dynamics: dict[str, Any] | None,
    unscoped_learning_rules: list[dict[str, Any]],
    population_shapes: dict[str, list[int]],
    neuromodulation_rules: list[dict[str, Any]],
    short_term_plasticity_rules: list[dict[str, Any]],
) -> dict[str, Any]:
    """Build the reserved advisory metadata block for graph-level semantics."""
    return {
        "schema_version": ADVISORY_SEMANTICS_VERSION,
        "surface": "graph",
        "timing_declarations": timing_declarations,
        "global_receptor_dynamics": global_receptor_dynamics,
        "learning_rules": unscoped_learning_rules,
        "population_shapes": population_shapes,
        "neuromodulation_rules": neuromodulation_rules,
        "short_term_plasticity_rules": short_term_plasticity_rules,
    }
