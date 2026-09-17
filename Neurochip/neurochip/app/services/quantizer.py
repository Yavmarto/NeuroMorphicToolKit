"""Quantization service — simulates accuracy impact of weight quantization."""

import math
import random
from typing import Any

from neurochip.contracts.deployment_contracts import TargetDevice
from neurochip.contracts.quantization_contracts import QuantizationResult

from ..schemas.estimation import NetworkInput


def _simulate_quantization_accuracy(
    network: NetworkInput,
    bit_width: int,
    baseline_accuracy: float = 0.98,
    seed: int = 42,
) -> dict[str, Any]:
    """
    Simulate accuracy loss from quantization.

    Uses a model where accuracy degrades logarithmically with fewer bits.
    In production, this would wrap neurodreamhand's crossbar_exporter
    to run actual quantized simulation.
    """
    random.seed(seed + bit_width)

    # Logarithmic degradation model: more bits = less accuracy loss
    # At 32-bit (float), loss ~ 0%. At 2-bit, loss ~ 15-25%.
    if bit_width >= 32:
        accuracy_loss = 0.0
    else:
        # Base degradation curve
        loss_factor = max(0.0, 1.0 - math.log2(bit_width) / math.log2(32))
        accuracy_loss = loss_factor * 0.20  # max ~20% loss at 1-bit

    # Add small random noise for realism
    accuracy_loss += random.gauss(0, 0.002)
    accuracy_loss = max(0.0, accuracy_loss)

    accuracy = max(0.0, min(1.0, baseline_accuracy - accuracy_loss))

    # Memory calculations
    baseline_bytes = network.num_synapses * 4  # 32-bit float baseline
    quantized_bytes = network.num_synapses * (bit_width / 8)
    memory_kb = quantized_bytes / 1024
    reduction = baseline_bytes / quantized_bytes if quantized_bytes > 0 else float("inf")

    # Spike fidelity: how closely quantized spikes match original
    fidelity = 1.0 - (accuracy_loss * 0.5)
    fidelity = max(0.0, min(1.0, fidelity))

    # Power estimate: proportional to bit-width (fewer bits = less energy)
    pj_per_op = bit_width * 0.5  # simplified model
    total_ops = network.num_synapses * 10  # ~10 spikes per inference (estimate)
    power_pj = pj_per_op * total_ops

    return {
        "accuracy": round(accuracy, 4),
        "accuracy_loss_pct": round(accuracy_loss * 100, 2),
        "memory_size_kb": round(memory_kb, 2),
        "memory_reduction_factor": round(reduction, 2),
        "spike_fidelity": round(fidelity, 4),
        "power_estimate_pj": round(power_pj, 2),
    }


def quantize(
    network: NetworkInput,
    bit_width: int,
    target_device: str,
    baseline_accuracy: float = 0.98,
    layer_configs: dict[str, int] | None = None,
) -> QuantizationResult:
    """Run quantization analysis at a single bit-width."""
    result = _simulate_quantization_accuracy(network, bit_width, baseline_accuracy)
    device_enum = _resolve_target_device(target_device)
    return QuantizationResult(
        bit_width=bit_width,
        target_device=device_enum,
        method="seeded_mathematical_simulation",
        is_estimate=True,
        accuracy_note=(
            "Accuracy is estimated via mathematical simulation, not measured on hardware. "
            "Validate with the target SDK before deployment."
        ),
        **result,
    )


def quantize_batch(
    network: NetworkInput,
    target_device: str,
    bit_widths: list[int] | None = None,
    baseline_accuracy: float = 0.98,
    layer_configs: dict[str, int] | None = None,
) -> list[QuantizationResult]:
    """Run quantization analysis across multiple bit-widths."""
    device_enum = _resolve_target_device(target_device)
    if bit_widths is None:
        from neurochip.contracts.quantization_contracts import QuantizationConfig

        bit_widths = QuantizationConfig.SUPPORTED_BIT_WIDTHS.get(device_enum, [8, 16, 32])

    # Optimized batch quantization: pre-calculate shared network metrics once.
    num_synapses = network.num_synapses
    baseline_bytes = num_synapses * 4
    total_ops = num_synapses * 10

    results = []
    for bw in bit_widths:
        # Use a more efficient version of the simulation for batch processing
        random.seed(42 + bw)

        if bw >= 32:
            accuracy_loss = 0.0
        else:
            loss_factor = max(0.0, 1.0 - math.log2(bw) / 5.0)  # log2(32) is 5
            accuracy_loss = loss_factor * 0.20

        accuracy_loss += random.gauss(0, 0.002)
        accuracy_loss = max(0.0, accuracy_loss)
        accuracy = max(0.0, min(1.0, baseline_accuracy - accuracy_loss))

        quantized_bytes = num_synapses * (bw / 8)
        memory_kb = quantized_bytes / 1024
        reduction = baseline_bytes / quantized_bytes if quantized_bytes > 0 else float("inf")

        fidelity = max(0.0, min(1.0, 1.0 - (accuracy_loss * 0.5)))
        power_pj = (bw * 0.5) * total_ops

        results.append(
            QuantizationResult(
                target_device=device_enum,
                bit_width=bw,
                accuracy=round(accuracy, 4),
                accuracy_loss_pct=round(accuracy_loss * 100, 2),
                memory_size_kb=round(memory_kb, 2),
                memory_reduction_factor=round(reduction, 2),
                spike_fidelity=round(fidelity, 4),
                power_estimate_pj=round(power_pj, 2),
                method="seeded_mathematical_simulation",
                is_estimate=True,
                accuracy_note=(
                    "Accuracy is estimated via mathematical simulation, not measured on hardware. "
                    "Validate with the target SDK before deployment."
                ),
            )
        )

    return results


def _resolve_target_device(target_device: str) -> TargetDevice:
    """Resolve a request string into the contract enum."""
    for member in TargetDevice:
        if member.value == target_device or member.name.lower() == target_device.lower():
            return member
    raise ValueError(f"Unknown target device: {target_device}")
