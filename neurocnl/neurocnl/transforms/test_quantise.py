"""Tests for quantization transforms."""

import numpy as np

from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR
from neurocnl.transforms.quantise import (
    quantise_network_dict,
    quantise_weights,
    quantise_weights_array,
)


def test_quantise_weights_8bit() -> None:
    """Test standard 8-bit weight quantization."""
    weights = np.array([-1.0, -0.5, 0.0, 0.5, 1.0])
    qw, scale = quantise_weights_array(weights, bits=8)

    # max_val for 8-bit is 127
    assert scale == 127.0
    np.testing.assert_array_equal(qw, [-127, -64, 0, 64, 127])
    assert qw.dtype == np.int32


def test_quantise_weights_custom_scale() -> None:
    """Test quantization with a provided scale factor."""
    weights = np.array([-1.0, 0.5, 1.0])
    qw, scale = quantise_weights_array(weights, bits=8, scale_factor=64.0)

    assert scale == 64.0
    np.testing.assert_array_equal(qw, [-64, 32, 64])


def test_quantise_weights_clip() -> None:
    """Test that weights are properly clipped to max value."""
    weights = np.array([-2.0, 0.0, 2.0])
    # Force scale factor that will cause overflow
    qw, scale = quantise_weights_array(weights, bits=8, scale_factor=100.0)

    assert scale == 100.0
    # Clipped to [-128, 127]
    np.testing.assert_array_equal(qw, [-128, 0, 127])


def test_quantise_network_dict() -> None:
    """Test quantization applied to a serialized network dictionary."""
    net_dict = {
        "network_name": "test_net",
        "populations": [{"id": "pop_0", "params": {"v_threshold": 1.0}}],
        "connections": [{"pre": "pop_0", "post": "pop_0", "weight": 0.5}],
    }

    quantized_dict = quantise_network_dict(net_dict, bits=8)

    # Original max weight is 0.5. To hit 127, scale factor should be 127/0.5 = 254.0
    assert quantized_dict["quantisation"]["scale_factor"] == 254.0
    assert quantized_dict["quantisation"]["bits"] == 8

    # Weight should be 0.5 * 254 = 127
    assert quantized_dict["connections"][0]["weight"] == 127

    # Threshold should be 1.0 * 254 = 254
    assert quantized_dict["populations"][0]["params"]["v_threshold"] == 254


def test_quantise_weights_ir() -> None:
    """Test quantization of NetworkIR objects."""
    ir = NetworkIR(
        populations={
            "pop_0": PopulationIR(name="pop_0", threshold=1.0),
            "pop_1": PopulationIR(name="pop_1", threshold=2.0),
        },
        connections=[
            ConnectionIR(source="pop_0", target="pop_1", weight=0.5),
            ConnectionIR(source="pop_1", target="pop_0", weight=-0.25),
        ],
    )

    q_ir = quantise_weights(ir, bits=4)

    # For 4 bits, max_val is 7, min_val is -8.
    # Max abs weight is 0.5, scale factor = 7 / 0.5 = 14.0
    assert q_ir.metadata["quantisation"]["bits"] == 4
    assert q_ir.metadata["quantisation"]["scale_factor"] == 14.0

    # Weights: 0.5 * 14 = 7, -0.25 * 14 = -3.5 -> -4
    assert q_ir.connections[0].weight == 7.0
    assert q_ir.connections[1].weight == -4.0

    # Thresholds: 1.0 * 14 = 14, 2.0 * 14 = 28
    assert q_ir.populations["pop_0"].threshold == 14.0
    assert q_ir.populations["pop_1"].threshold == 28.0
