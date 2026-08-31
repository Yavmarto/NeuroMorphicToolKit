"""Snapshot tests for Neurochip adapter — constraint analysis, quantization,
power, and latency estimation services.

These are the four service functions that produce structured Pydantic
responses back to the Flutter frontend.  Snapshots guard against silent
mutations to field names, units, or rounding semantics.

PYTHONPATH must include NeuroMorphicToolKit/Neurochip so that
`neurochip.app.*` is importable.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Shared network fixture — small, well-under-capacity LIF network
# ---------------------------------------------------------------------------
_SMALL_NETWORK_KWARGS = dict(
    num_neurons=128,
    num_synapses=512,
    neuron_model="LIF",
    populations=[{"name": "sensory", "size": 64}, {"name": "motor", "size": 64}],
    connections=[{"pre": "sensory", "post": "motor", "weight_count": 512}],
    weight_bit_width=8,
    network_depth=3,
)

_LARGE_NETWORK_KWARGS = dict(
    num_neurons=3500,
    num_synapses=8192,
    neuron_model="LIF",
    populations=[{"name": "enc", "size": 1750}, {"name": "dec", "size": 1750}],
    connections=[{"pre": "enc", "post": "dec", "weight_count": 8192}],
    weight_bit_width=32,
    network_depth=5,
)

_TARGET = "teensy41"


# ---------------------------------------------------------------------------
# 1. Constraint analyzer
# ---------------------------------------------------------------------------


def test_constraint_analyze_small_network_snapshot(snapshot: object) -> None:
    """Pin the ConstraintReport for a small network that comfortably fits Teensy 4.1."""
    from neurochip.app.schemas.estimation import NetworkInput
    from neurochip.app.services.constraint_analyzer import analyze

    network = NetworkInput(**_SMALL_NETWORK_KWARGS)
    report = analyze(network, _TARGET)
    assert report.model_dump() == snapshot


def test_constraint_analyze_large_network_snapshot(snapshot: object) -> None:
    """Pin the ConstraintReport for an oversized network — neuron_fit should fail."""
    from neurochip.app.schemas.estimation import NetworkInput
    from neurochip.app.services.constraint_analyzer import analyze

    network = NetworkInput(**_LARGE_NETWORK_KWARGS)
    report = analyze(network, _TARGET)
    assert report.model_dump() == snapshot


# ---------------------------------------------------------------------------
# 2. Quantization service
# ---------------------------------------------------------------------------


def test_quantize_8bit_snapshot(snapshot: object) -> None:
    """Pin the QuantizationResult for 8-bit weights on Teensy 4.1."""
    from neurochip.app.schemas.estimation import NetworkInput
    from neurochip.app.services.quantizer import quantize

    network = NetworkInput(**_SMALL_NETWORK_KWARGS)
    result = quantize(network, bit_width=8, target_device="teensy_41")
    assert result.model_dump() == snapshot


def test_quantize_batch_snapshot(snapshot: object) -> None:
    """Pin the list of QuantizationResults across [4, 8, 16, 32] bit-widths."""
    from neurochip.app.schemas.estimation import NetworkInput
    from neurochip.app.services.quantizer import quantize_batch

    network = NetworkInput(**_SMALL_NETWORK_KWARGS)
    # Teensy 4.1 supports 8, 16, and 32-bit weights (4-bit not in its profile)
    results = quantize_batch(network, target_device="teensy_41", bit_widths=[8, 16, 32])
    assert [r.model_dump() for r in results] == snapshot


# ---------------------------------------------------------------------------
# 3. Power estimator
# ---------------------------------------------------------------------------


def test_estimate_power_small_network_snapshot(snapshot: object) -> None:
    """Pin the PowerEstimate for the small network on Teensy 4.1."""
    from neurochip.app.schemas.estimation import NetworkInput
    from neurochip.app.services.power_estimator import estimate_power

    network = NetworkInput(**_SMALL_NETWORK_KWARGS)
    result = estimate_power(network, _TARGET)
    assert result.model_dump() == snapshot


# ---------------------------------------------------------------------------
# 4. Latency estimator
# ---------------------------------------------------------------------------


def test_estimate_latency_small_network_snapshot(snapshot: object) -> None:
    """Pin the LatencyEstimate for the small network on Teensy 4.1."""
    from neurochip.app.schemas.estimation import NetworkInput
    from neurochip.app.services.power_estimator import estimate_latency

    network = NetworkInput(**_SMALL_NETWORK_KWARGS)
    result = estimate_latency(network, _TARGET)
    assert result.model_dump() == snapshot
