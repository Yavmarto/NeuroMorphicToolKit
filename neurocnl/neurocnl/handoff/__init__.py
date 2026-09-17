"""NeuroCNL handoff public API (Neurochip + NeuroSim)."""

from __future__ import annotations

from typing import Any

from importlib import import_module

_EXPORT_MAP = {
    "build_dreamhand_learning_sync_artifact": (
        "neurocnl.handoff.dreamhand_learning_sync",
        "build_dreamhand_learning_sync_artifact",
    ),
    "build_dreamhand_learning_sync_artifacts": (
        "neurocnl.handoff.dreamhand_learning_sync",
        "build_dreamhand_learning_sync_artifacts",
    ),
    "NeurochipEndpointConfig": (
        "neurocnl.handoff.neurochip_pynq_handoff",
        "NeurochipEndpointConfig",
    ),
    "NeurochipPynqClient": (
        "neurocnl.handoff.neurochip_pynq_handoff",
        "NeurochipPynqClient",
    ),
    "PynqHandoffRejectedError": (
        "neurocnl.handoff.neurochip_pynq_handoff",
        "PynqHandoffRejectedError",
    ),
    "PynqHandoffResult": (
        "neurocnl.handoff.neurochip_pynq_handoff",
        "PynqHandoffResult",
    ),
    "map_pynq_artifact_to_deploy_request": (
        "neurocnl.handoff.neurochip_pynq_handoff",
        "map_pynq_artifact_to_deploy_request",
    ),
    "HandoffProvenance": (
        "neurocnl.handoff.neurochip_teensy_mapper",
        "HandoffProvenance",
    ),
    "HandoffResult": ("neurocnl.handoff.neurochip_teensy_mapper", "HandoffResult"),
    "TeensyHandoffRejectedError": (
        "neurocnl.handoff.neurochip_teensy_mapper",
        "TeensyHandoffRejectedError",
    ),
    "map_network_ir_to_teensy_payload": (
        "neurocnl.handoff.neurochip_teensy_mapper",
        "map_network_ir_to_teensy_payload",
    ),
    "NeurosimHandoffRejectedError": (
        "neurocnl.handoff.neurosim_cnl_handoff",
        "NeurosimHandoffRejectedError",
    ),
    "build_neurosim_handoff_spec": (
        "neurocnl.handoff.neurosim_cnl_handoff",
        "build_neurosim_handoff_spec",
    ),
}

__all__ = sorted(_EXPORT_MAP)


def __getattr__(name: str) -> Any:
    try:
        module_name, attribute_name = _EXPORT_MAP[name]
    except KeyError as exc:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}") from exc

    module = import_module(module_name)
    value = getattr(module, attribute_name)
    globals()[name] = value
    return value


def __dir__() -> list[str]:
    return sorted(set(globals()) | set(__all__))
