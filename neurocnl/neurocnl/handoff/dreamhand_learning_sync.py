"""Hardware-aware learning sync artifacts for Neuro-Dream-Hand integration."""

from __future__ import annotations

from typing import Any

import numpy as np

from neurocnl.backends import get_backend_capability
from neurocnl.ir import ConnectionIR, LearningRuleIR, NetworkIR

_BACKEND_DEFAULTS: dict[str, dict[str, Any]] = {
    "loihi": {
        "hardware_family": "loihi",
        "hardware_generation": "loihi2",
        "quantization_bits": 8,
        "synchronization_mode": "native_on_chip",
        "native_learning_supported": True,
    },
    "akida": {
        "hardware_family": "akida",
        "hardware_generation": "akida",
        "quantization_bits": 8,
        "synchronization_mode": "host_quantized_sync",
        "native_learning_supported": False,
    },
    "akida1": {
        "hardware_family": "akida",
        "hardware_generation": "akida1",
        "quantization_bits": 8,
        "synchronization_mode": "host_quantized_sync",
        "native_learning_supported": False,
    },
    "akida2": {
        "hardware_family": "akida",
        "hardware_generation": "akida2",
        "quantization_bits": 8,
        "synchronization_mode": "host_quantized_sync",
        "native_learning_supported": False,
    },
}


def _normalize_backend(backend: str) -> str:
    normalized = backend.strip().lower()
    if normalized == "loihi2":
        return "loihi"
    if normalized in _BACKEND_DEFAULTS:
        return normalized
    raise KeyError(f"Unsupported Dream-Hand learning sync backend {backend!r}.")


def _resolve_rule_connection(
    ir: NetworkIR, rule: LearningRuleIR
) -> tuple[str | None, str | None, str, ConnectionIR | None]:
    if rule.source is not None and rule.target is not None:
        for connection in ir.connections:
            if connection.source == rule.source and connection.target == rule.target:
                return rule.source, rule.target, "connection", connection
        return rule.source, rule.target, "connection", None

    if len(ir.connections) == 1:
        connection = ir.connections[0]
        return (
            connection.source,
            connection.target,
            "inferred_single_connection",
            connection,
        )

    return None, None, "global", None


def _reference_weight_scale(
    rule: LearningRuleIR, connection: ConnectionIR | None
) -> float:
    candidates = [1.0]
    if connection is not None and connection.weight is not None:
        candidates.append(
            float(np.max(np.abs(np.asarray(connection.weight, dtype=float))))
        )
    if rule.weight_min is not None:
        candidates.append(abs(rule.weight_min))
    if rule.weight_max is not None:
        candidates.append(abs(rule.weight_max))
    return max(candidates)


def _quantize_delta(
    rule: LearningRuleIR,
    *,
    bits: int,
    scale_factor: float,
) -> tuple[int, float, str]:
    direction = rule.attributes.get("update_direction")
    if rule.rate is not None:
        requested_delta = rule.rate
        delta_source = "learning_rate"
        if requested_delta == 0:
            return 0, 0.0, delta_source
        quantized = max(1, round(abs(requested_delta) * scale_factor))
        if requested_delta < 0:
            quantized *= -1
    elif direction == "strengthen":
        quantized = 1
        delta_source = "directional_min_step"
    elif direction == "weaken":
        quantized = -1
        delta_source = "directional_min_step"
    else:
        quantized = 0
        delta_source = "unspecified"

    max_int = (1 << (bits - 1)) - 1
    min_int = -(1 << (bits - 1))
    quantized = max(min(quantized, max_int), min_int)
    return quantized, quantized / scale_factor, delta_source


def _shared_weight_bounds(
    rules: list[LearningRuleIR],
) -> tuple[float | None, float | None]:
    weight_min = next(
        (rule.weight_min for rule in rules if rule.weight_min is not None), None
    )
    weight_max = next(
        (rule.weight_max for rule in rules if rule.weight_max is not None), None
    )
    return weight_min, weight_max


def build_dreamhand_learning_sync_artifact(
    ir: NetworkIR, backend: str
) -> dict[str, Any]:
    """Build a JSON-serializable learning sync artifact for one backend."""
    normalized_backend = _normalize_backend(backend)
    defaults = _BACKEND_DEFAULTS[normalized_backend]
    capability = get_backend_capability(normalized_backend)
    learning_support = capability.concept_support.get("stdp_learning", "unsupported")
    bits = int(defaults["quantization_bits"])

    global_rules = [
        rule
        for rule in ir.learning_rules
        if rule.source is None and rule.target is None
    ]
    global_weight_min, global_weight_max = _shared_weight_bounds(global_rules)

    rules_payload: list[dict[str, Any]] = []
    for rule in ir.learning_rules:
        source, target, scope, connection = _resolve_rule_connection(ir, rule)
        weight_min = (
            rule.weight_min if rule.weight_min is not None else global_weight_min
        )
        weight_max = (
            rule.weight_max if rule.weight_max is not None else global_weight_max
        )
        rule_for_quant = LearningRuleIR(
            kind=rule.kind,
            source=source,
            target=target,
            rate=rule.rate,
            window=rule.window,
            weight_min=weight_min,
            weight_max=weight_max,
            provenance=list(rule.provenance),
            attributes=dict(rule.attributes),
        )
        reference_scale = _reference_weight_scale(rule_for_quant, connection)
        max_int = (1 << (bits - 1)) - 1
        scale_factor = max_int / reference_scale
        quantized_delta, dequantized_delta, delta_source = _quantize_delta(
            rule_for_quant,
            bits=bits,
            scale_factor=scale_factor,
        )
        rules_payload.append(
            {
                "learning_rule": rule.kind,
                "source": source,
                "target": target,
                "scope": scope,
                "learning_rate": rule.rate,
                "timing_window_seconds": rule.window,
                "weight_min": weight_min,
                "weight_max": weight_max,
                "reference_weight_scale": reference_scale,
                "scale_factor": scale_factor,
                "quantized_delta": quantized_delta,
                "dequantized_delta": dequantized_delta,
                "delta_source": delta_source,
                "update_direction": rule.attributes.get("update_direction"),
                "provenance": [
                    {
                        "line": provenance.line,
                        "concept": provenance.concept,
                        "raw": provenance.raw,
                    }
                    for provenance in rule.provenance
                ],
            }
        )

    return {
        "backend": normalized_backend,
        "hardware_family": defaults["hardware_family"],
        "hardware_generation": defaults["hardware_generation"],
        "synchronization_mode": defaults["synchronization_mode"],
        "quantization_bits": bits,
        "native_learning_supported": defaults["native_learning_supported"]
        and learning_support != "unsupported",
        "capability_verdict": learning_support,
        "capabilities": {
            "supported_learning_rules": sorted(capability.learning_rules),
            "supports_weight_quantization": capability.supports_weight_quantization,
            "timing_resolution_seconds": capability.timing_resolution_seconds,
            "notes": list(capability.notes),
        },
        "rules": rules_payload,
    }


def build_dreamhand_learning_sync_artifacts(
    ir: NetworkIR, backends: tuple[str, ...] = ("loihi", "akida")
) -> dict[str, dict[str, Any]]:
    """Build Dream-Hand learning sync artifacts keyed by backend."""
    return {
        _normalize_backend(backend): build_dreamhand_learning_sync_artifact(ir, backend)
        for backend in backends
    }
