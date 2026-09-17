"""Helpers shared by more than one backend planner."""

from __future__ import annotations


def _append_warning(warnings: list[str], message: str) -> None:
    if message not in warnings:
        warnings.append(message)


def _estimate_memory_kb(n_neurons: int, n_synapses: int, bit_width: int = 32) -> float:
    """Estimate memory usage in KB.

    Formula matches Neurochip constraint_analyzer.py:
        weight_bytes + neuron_state_bytes + index_bytes
    """
    weight_bytes = n_synapses * (bit_width / 8)
    neuron_bytes = n_neurons * 6  # voltage (4B) + refractory counter (2B)
    index_bytes = n_synapses * 8  # pre + post int indices (4B each)
    return (weight_bytes + neuron_bytes + index_bytes) / 1024
