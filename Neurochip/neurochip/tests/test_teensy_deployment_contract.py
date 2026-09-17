"""Unit tests for Neurochip Teensy Deployment Contract."""

import json
import os

import pytest
from pydantic import ValidationError

from neurochip.contracts.teensy_deployment_contract import (
    MAX_IO_PINS,
    MAX_NEURONS,
    MEMORY_BUDGET_KB,
    SUPPORTED_NEURON_MODELS,
    SUPPORTED_WEIGHT_BIT_WIDTHS,
    TeensyNetworkPayloadContract,
    max_synapses_for_bit_width,
)

# ---------------------------------------------------------------------------
# TeensyNetworkPayloadContract — valid payloads
# ---------------------------------------------------------------------------


class TestTeensyNetworkPayloadValid:
    def test_minimal_payload(self):
        payload = TeensyNetworkPayloadContract(
            num_neurons=100,
            num_synapses=500,
            neuron_model="LIF",
            weight_bit_width=8,
            network_depth=2,
        )
        assert payload.num_neurons == 100

    def test_max_neurons_exact(self):
        payload = TeensyNetworkPayloadContract(
            num_neurons=MAX_NEURONS,
            num_synapses=0,
            neuron_model="LIF",
            weight_bit_width=8,
            network_depth=1,
        )
        assert payload.num_neurons == MAX_NEURONS

    def test_adaptive_lif_rejected(self):
        """AdaptiveLIF is not supported on Teensy 4.1 (LIF only)."""
        with pytest.raises(ValidationError, match="not supported"):
            TeensyNetworkPayloadContract(
                num_neurons=50,
                num_synapses=100,
                neuron_model="AdaptiveLIF",
                weight_bit_width=16,
                network_depth=2,
            )

    def test_all_bit_widths(self):
        for bw in SUPPORTED_WEIGHT_BIT_WIDTHS:
            payload = TeensyNetworkPayloadContract(
                num_neurons=50,
                num_synapses=100,
                neuron_model="LIF",
                weight_bit_width=bw,
                network_depth=2,
            )
            assert payload.weight_bit_width == bw


# ---------------------------------------------------------------------------
# TeensyNetworkPayloadContract — rejection
# ---------------------------------------------------------------------------


class TestTeensyNetworkPayloadRejected:
    def test_exceeds_neuron_capacity(self):
        with pytest.raises(ValidationError, match="exceeds"):
            TeensyNetworkPayloadContract(
                num_neurons=5000,
                num_synapses=0,
                neuron_model="LIF",
                weight_bit_width=8,
                network_depth=1,
            )

    def test_unsupported_neuron_model(self):
        with pytest.raises(ValidationError, match="not supported"):
            TeensyNetworkPayloadContract(
                num_neurons=100,
                num_synapses=0,
                neuron_model="Izhikevich",
                weight_bit_width=8,
                network_depth=2,
            )

    def test_unsupported_bit_width(self):
        with pytest.raises(ValidationError, match="not in supported"):
            TeensyNetworkPayloadContract(
                num_neurons=100,
                num_synapses=0,
                neuron_model="LIF",
                weight_bit_width=4,
                network_depth=2,
            )

    def test_exceeds_synapse_capacity(self):
        # Far more synapses than can fit at 32-bit weights
        with pytest.raises(ValidationError, match="num_synapses"):
            TeensyNetworkPayloadContract(
                num_neurons=100,
                num_synapses=500_000,
                neuron_model="LIF",
                weight_bit_width=32,
                network_depth=2,
            )

    def test_exceeds_memory_budget(self):
        # Many synapses that exceed memory at 32-bit
        max_syn = max_synapses_for_bit_width(32)
        with pytest.raises(ValidationError):
            TeensyNetworkPayloadContract(
                num_neurons=100,
                num_synapses=max_syn + 1000,
                neuron_model="LIF",
                weight_bit_width=32,
                network_depth=2,
            )


# ---------------------------------------------------------------------------
# max_synapses_for_bit_width
# ---------------------------------------------------------------------------


class TestMaxSynapsesForBitWidth:
    def test_positive_for_all_supported(self):
        for bw in SUPPORTED_WEIGHT_BIT_WIDTHS:
            assert max_synapses_for_bit_width(bw) > 0

    def test_decreasing_with_bit_width(self):
        assert max_synapses_for_bit_width(8) > max_synapses_for_bit_width(16)
        assert max_synapses_for_bit_width(16) > max_synapses_for_bit_width(32)

    def test_fits_in_budget(self):
        for bw in SUPPORTED_WEIGHT_BIT_WIDTHS:
            max_syn = max_synapses_for_bit_width(bw)
            weight_bytes = max_syn * (bw / 8)
            neuron_bytes = MAX_NEURONS * 6
            index_bytes = max_syn * 8
            total_kb = (weight_bytes + neuron_bytes + index_bytes) / 1024
            assert total_kb <= MEMORY_BUDGET_KB


# ---------------------------------------------------------------------------
# Constants match teensy41.json
# ---------------------------------------------------------------------------


class TestConstantsMatch:
    def test_match_hardware_profile_json(self):
        json_path = os.path.join(
            os.path.dirname(__file__),
            "..",
            "targets",
            "teensy41.json",
        )
        json_path = os.path.normpath(json_path)
        if not os.path.exists(json_path):
            pytest.skip("teensy41.json not found")

        with open(json_path) as f:
            hw = json.load(f)

        assert MAX_NEURONS == hw["neuron_capacity"]
        assert MAX_IO_PINS == hw["io_pins"]
        assert MEMORY_BUDGET_KB == hw["on_chip_memory_kb"]
        assert set(SUPPORTED_WEIGHT_BIT_WIDTHS) == set(hw["weight_bit_widths"])
        assert set(SUPPORTED_NEURON_MODELS) == set(hw["supported_neuron_models"])
