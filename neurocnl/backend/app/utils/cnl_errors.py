"""Helpers for preserving structured CNL diagnostics at route boundaries."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

_GENERIC_PARSE_EXAMPLES = [
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
]

_FIELD_EXAMPLES: dict[str, list[str]] = {
    "threshold": [
        "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
    ],
    "refractory_period": [
        "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds",
    ],
    "tau": [
        "The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds",
    ],
    "synaptic_weight": [
        "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
    ],
    "subject": [
        "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0",
    ],
    "network_timestep": [
        "The network MUST operate WITH timestep of 1 ms",
    ],
    "delay_quantization_step": [
        "The network MUST use discrete delays quantized to 1 ms",
    ],
}

_CODE_HINTS: dict[str, str] = {
    "parse_error": "Rewrite the sentence so it matches a supported CNL grammar family.",
    "unsupported_sentence_family": (
        "Rewrite the sentence using one supported CNL form such as threshold, decay, refractory, or synaptic weight."
    ),
    "no_valid_cnl_sentences": "Add at least one non-empty CNL sentence before generating or exporting.",
    "contract_violation": "Adjust the declared neuron parameters so they satisfy the Layer 1 contract.",
    "loihi_contract_violation": "Rewrite the timing or neuron parameters so they stay within the Loihi contract.",
    "zero_weight_synapse": "Use a non-zero synaptic weight so the connection has an observable effect.",
    "contradictory_params": "Keep one consistent value per neuron parameter across the whole spec.",
    "self_referencing_connection": "Rewrite the connection to target a different population or remove the self-loop.",
    "orphan_population": "Add behavior or connectivity sentences for this population so it participates in the network.",
    "dangling_source_neuron": "Declare the source neuron or population before referencing it in a connection.",
    "dangling_target_neuron": "Declare the target neuron or population before referencing it in a connection.",
    "lowering_failed": "Add the missing executable CNL sentences or remove concepts that cannot be lowered yet.",
    "not_deployable": "Rewrite the spec so it fits the selected hardware target's constraints before deploying.",
    "training_failed": "Review the adapter error and rerun with a supported backend, mode, and payload.",
    "adapter_selection_error": "Choose an available training backend and one of its supported training modes.",
    "duration_too_large": "Lower the requested simulation duration so it stays within the interactive limit.",
    "lava_dispatch_failed": (
        "Check that lava-nc is installed and the NIR graph contains only supported node types "
        "(Input, Output, LIF, Linear). If using a remote worker, verify NEUROCNL_LAVA_WORKER_URL "
        "is reachable and responding within the timeout."
    ),
}


class StructuredJobError(RuntimeError):
    """Exception carrying a JSON-safe error payload for async job failures."""

    def __init__(self, payload: dict[str, Any]) -> None:
        super().__init__(_payload_message(payload))
        self.payload = payload


def build_parse_failure_detail(parse_results: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Return a structured route-safe payload for parser failures."""
    items = [
        normalize_cnl_error_item(result.get("error_detail"), source="parser")
        for result in parse_results
        if not result.get("valid") and result.get("error_detail") is not None
    ]
    messages = [item["message"] for item in items if item.get("message") is not None]
    return {
        "code": "parse_failed",
        "error": "parse_failed",
        "message": messages[0] if messages else "CNL parsing failed.",
        "items": items,
        "messages": messages,
    }


def build_validation_failure_detail(
    *messages: str,
    validation: Mapping[str, Any] | None = None,
    items: Iterable[Mapping[str, Any] | None] | None = None,
    code: str = "validation_failed",
) -> dict[str, Any]:
    normalized_items = list(_iter_validation_items(validation, items))
    if not normalized_items and messages:
        normalized_items = [
            normalize_cnl_error_item(
                {"code": code, "message": message},
                source="validation",
            )
            for message in messages
            if message
        ]
    elif not normalized_items and not messages:
        normalized_items = [
            normalize_cnl_error_item(
                {
                    "code": code,
                    "message": "Validation failed.",
                },
                source="validation",
            )
        ]

    message_list = [message for message in messages if message] or [
        item["message"] for item in normalized_items if item.get("message")
    ]

    return {
        "error": "validation_failed",
        "items": normalized_items,
        "messages": message_list,
    }


def build_lowering_failure_detail(exc: Exception) -> dict[str, Any]:
    item = normalize_cnl_error_item(
        {
            "code": "lowering_failed",
            "message": str(exc),
        },
        source="lowering",
    )
    return {
        "error": "lowering_failed",
        "items": [item],
        "messages": [item["message"]],
    }


def build_backend_failure_detail(
    error: str,
    *messages: str,
    items: Iterable[Mapping[str, Any] | None] | None = None,
    code: str | None = None,
    source: str = "backend",
    **extra: Any,
) -> dict[str, Any]:
    normalized_items = [
        normalize_cnl_error_item(item, source=source, default_code=code or error)
        for item in (items or [])
        if item is not None
    ]
    if not normalized_items and messages:
        normalized_items = [
            normalize_cnl_error_item(
                {
                    "code": code or error,
                    "message": message,
                },
                source=source,
            )
            for message in messages
            if message
        ]

    message_list = [message for message in messages if message] or [
        item["message"] for item in normalized_items if item.get("message")
    ]
    detail: dict[str, Any] = {
        "error": error,
        "items": normalized_items,
        "messages": message_list,
    }
    detail.update(extra)
    return detail


def normalize_cnl_error_item(
    detail: Mapping[str, Any] | None,
    *,
    source: str | None = None,
    default_code: str | None = None,
    default_message: str | None = None,
) -> dict[str, Any]:
    data = dict(detail or {})

    code = _first_non_empty(
        data.get("code"),
        data.get("check"),
        data.get("invariant"),
        data.get("name"),
        default_code,
        "cnl_error",
    )
    message = _first_non_empty(
        data.get("message"),
        data.get("detail"),
        data.get("reason"),
        data.get("description"),
        default_message,
        str(code).replace("_", " "),
    )

    normalized: dict[str, Any] = {
        "code": code,
        "message": message,
        "hint": _first_non_empty(
            data.get("hint"), _derive_hint(code=code, detail=data, source=source)
        ),
        "examples": _normalize_examples(data.get("examples"), detail=data, code=code),
        "line": _normalize_line(data),
        "raw": data.get("raw"),
    }

    for key in (
        "source",
        "field",
        "value",
        "lines",
        "name",
        "reason",
        "check",
        "detail",
        "result",
        "description",
        "severity",
    ):
        if key in data:
            normalized[key] = data[key]

    normalized["source"] = _first_non_empty(
        normalized.get("source"),
        source,
        data.get("source"),
    )
    # Layer-1 invariant results carry `invariant`/`node` and no `name`, but
    # InvariantResult requires `name` — without this, every layer-1 NIR failure
    # turned POST /api/validate into an unhandled pydantic error and the user saw
    # a bare 500. Mirrors the "<node>/<invariant>" tag layer1_validator already
    # uses for passing invariants, so passed and failed entries read alike.
    if not normalized.get("name"):
        invariant = data.get("invariant")
        node = data.get("node")
        if invariant and node:
            normalized["name"] = f"{node}/{invariant}"
        else:
            normalized["name"] = str(invariant or data.get("check") or code)
    normalized.setdefault("check", data.get("check") or code)
    normalized.setdefault("detail", data.get("detail") or message)
    normalized.setdefault("reason", data.get("reason") or message)
    normalized.setdefault("description", data.get("description") or message)
    normalized.setdefault("lines", data.get("lines") or _line_list(normalized.get("line")))
    return normalized


def _iter_validation_items(
    validation: Mapping[str, Any] | None,
    items: Iterable[Mapping[str, Any] | None] | None,
) -> Iterable[dict[str, Any]]:
    if items is not None:
        for item in items:
            if item is not None:
                yield normalize_cnl_error_item(item, source="validation")
        return

    if validation is None:
        return

    for failure in validation.get("layer1", {}).get("failed", []):
        yield normalize_cnl_error_item(failure, source="layer1")
    for failure in validation.get("layer2", {}).get("checks_failed", []):
        yield normalize_cnl_error_item(failure, source="layer2")


def _normalize_examples(
    examples: Any,
    *,
    detail: Mapping[str, Any],
    code: str,
) -> list[str]:
    if isinstance(examples, list) and examples:
        return [str(example) for example in examples if str(example).strip()]

    field = detail.get("field")
    if isinstance(field, str) and field in _FIELD_EXAMPLES:
        return list(_FIELD_EXAMPLES[field])
    return (
        list(_FIELD_EXAMPLES.get("subject", _GENERIC_PARSE_EXAMPLES))
        if code
        in {
            "dangling_source_neuron",
            "dangling_target_neuron",
            "self_referencing_connection",
        }
        else list(_GENERIC_PARSE_EXAMPLES)
    )


def _derive_hint(*, code: str, detail: Mapping[str, Any], source: str | None) -> str:
    if code in _CODE_HINTS:
        return _CODE_HINTS[code]

    field = detail.get("field")
    if isinstance(field, str) and field in _FIELD_EXAMPLES:
        return f"Rewrite the sentence that sets `{field}` so it uses a supported value and stays internally consistent."
    if source == "layer1":
        return "Rewrite the biophysical constraint so the declared neuron parameters remain valid."
    if source == "layer2":
        return "Rewrite the affected sentences so the network topology and cross-references agree."
    if source == "parser":
        return _CODE_HINTS["parse_error"]
    return (
        "Review the failing CNL line and rewrite it into a supported, internally consistent form."
    )


def _normalize_line(detail: Mapping[str, Any]) -> int | None:
    line = detail.get("line")
    if isinstance(line, int):
        return line
    lines = detail.get("lines")
    if isinstance(lines, list):
        for candidate in lines:
            if isinstance(candidate, int):
                return candidate
    return None


def _line_list(line: int | None) -> list[int]:
    return [line] if isinstance(line, int) else []


def _first_non_empty(*values: object) -> Any:
    for value in values:
        if isinstance(value, str):
            if value.strip():
                return value
        elif value is not None:
            return value
    return None


def _payload_message(payload: Mapping[str, Any]) -> str:
    messages = payload.get("messages")
    if isinstance(messages, list) and messages:
        first = messages[0]
        if isinstance(first, str) and first:
            return first
    return str(payload.get("error", "structured_job_error"))
