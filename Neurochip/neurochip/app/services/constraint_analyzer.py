"""Constraint Analyzer — compares a network against a hardware target profile."""

import json
import os
from typing import Literal

from neurochip.contracts.hardware_contracts import HardwareProfile

from ..schemas.analysis import ConstraintRejection, ConstraintReport
from ..schemas.estimation import NetworkInput


def _load_target(target_id: str) -> HardwareProfile:
    targets_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "targets")
    filepath = os.path.join(targets_dir, f"{target_id}.json")
    with open(filepath) as f:
        return HardwareProfile(**json.load(f))


def _estimate_memory_kb(network: NetworkInput, bit_width: int) -> float:
    """Estimate memory usage based on synapse count and weight bit-width."""
    bytes_per_weight = bit_width / 8
    weight_memory = network.num_synapses * bytes_per_weight
    # Neuron state: voltage (4 bytes) + refractory counter (2 bytes) per neuron
    neuron_memory = network.num_neurons * 6
    # Connectivity indices: 2 ints (4 bytes each) per synapse
    index_memory = network.num_synapses * 8
    total_bytes = weight_memory + neuron_memory + index_memory
    return total_bytes / 1024


def analyze(network: NetworkInput, target_id: str) -> ConstraintReport:
    """Run constraint analysis: network vs hardware target."""
    target = _load_target(target_id)

    # Neuron capacity check
    neuron_fit: Literal["pass", "warn", "fail"]
    if network.num_neurons > target.neuron_capacity:
        neuron_fit = "fail"
    elif network.num_neurons > target.neuron_capacity * 0.8:
        neuron_fit = "warn"
    else:
        neuron_fit = "pass"

    # Determine best bit-width for target
    target_max_bits = max(target.weight_bit_widths)
    target_min_bits = min(target.weight_bit_widths)
    quantization_needed = network.weight_bit_width > target_max_bits

    # Pick the largest supported bit-width that fits
    if network.weight_bit_width in target.weight_bit_widths:
        required_bits = network.weight_bit_width
    else:
        supported_below = [b for b in target.weight_bit_widths if b <= network.weight_bit_width]
        required_bits = max(supported_below) if supported_below else target_min_bits

    # Memory check
    memory_fit: Literal["pass", "warn", "fail"]
    memory_kb = _estimate_memory_kb(network, required_bits)
    memory_available = float(target.on_chip_memory_kb)
    if memory_kb > memory_available:
        memory_fit = "fail"
    elif memory_kb > memory_available * 0.8:
        memory_fit = "warn"
    else:
        memory_fit = "pass"

    # Unsupported features
    unsupported = []
    rejections: list[ConstraintRejection] = []
    if network.neuron_model not in target.supported_neuron_models:
        unsupported.append(
            f"Neuron model '{network.neuron_model}' not supported by {target.name}. "
            f"Supported: {', '.join(target.supported_neuron_models)}"
        )
    if target.synapse_capacity is not None and network.num_synapses > target.synapse_capacity:
        rejections.append(
            ConstraintRejection(
                field="num_synapses",
                limit=target.synapse_capacity,
                actual=network.num_synapses,
                code="synapse_capacity_exceeded",
                hint=(
                    f"Network has {network.num_synapses} synapses; {target.name} supports at most "
                    f"{target.synapse_capacity}. Prune connections or choose a higher-capacity target."
                ),
            )
        )
    if target.max_populations is not None and len(network.populations) > target.max_populations:
        rejections.append(
            ConstraintRejection(
                field="populations",
                limit=target.max_populations,
                actual=len(network.populations),
                code="population_count_exceeded",
                hint=f"{target.name} supports at most {target.max_populations} populations.",
            )
        )

    # Warnings
    warnings = []
    if quantization_needed:
        warnings.append(
            f"Weights are {network.weight_bit_width}-bit → "
            f"{required_bits}-bit quantization needed for {target.name}"
        )
    if neuron_fit == "warn":
        warnings.append(
            f"Network uses {network.num_neurons}/{target.neuron_capacity} neurons (>{80}% capacity)"
        )
    if memory_fit == "warn":
        warnings.append(
            f"Memory usage {memory_kb:.1f} KB / {memory_available:.0f} KB (>{80}% capacity)"
        )

    # Recommendations
    recommendations = []
    if quantization_needed:
        recommendations.append("Open Quantization Explorer to find optimal bit-width")
    if neuron_fit == "fail":
        recommendations.append("Consider network partitioning — neuron count exceeds capacity")
    if memory_fit == "fail":
        recommendations.append("Reduce weight bit-width or network size to fit memory")
    if unsupported:
        recommendations.append("Switch neuron model or select a different target")
    if rejections:
        recommendations.append("Resolve export-blocking target limit violations before deployment")

    return ConstraintReport(
        target_id=target_id,
        network_neurons=network.num_neurons,
        target_capacity=target.neuron_capacity,
        neuron_fit=neuron_fit,
        weight_bit_width_required=required_bits,
        quantization_needed=quantization_needed,
        memory_usage_kb=round(memory_kb, 2),
        memory_available_kb=memory_available,
        memory_fit=memory_fit,
        unsupported_features=unsupported,
        warnings=warnings,
        recommendations=recommendations,
        rejections=rejections,
    )
