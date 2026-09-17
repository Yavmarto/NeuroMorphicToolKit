"""Tests for `PynqSimulator` / `PynqState`, the in-process PYNQ stand-in.

All tests run without the ``pynq`` library.
"""

import pytest
from pynq_backend_fixtures import ONE_TO_ONE_LAYER, ONE_TO_TWO_LAYER

from neurochip.app.services.pynq_errors import (
    ConfigurationError,
    DmaTransferError,
    MmioWriteError,
    OverlayLoadError,
)
from neurochip.app.services.pynq_simulator import PynqSimulator, PynqState
from neurochip.contracts.pynq_runtime_artifact_contract import MAX_SYNAPSES


class TestPynqSimulator:
    def test_initial_state(self):
        sim = PynqSimulator()
        assert sim.current_state == "unloaded"

    def test_load_overlay_valid(self):
        sim = PynqSimulator()
        sim.load_overlay("snn_overlay.bit")
        assert sim.current_state == "loaded"

    def test_load_overlay_invalid_extension(self):
        sim = PynqSimulator()
        with pytest.raises(OverlayLoadError) as exc_info:
            sim.load_overlay("overlay.bin")
        assert exc_info.value.error_code == "OVERLAY_INVALID_FORMAT"

    def test_configure_before_load_raises(self):
        sim = PynqSimulator()
        with pytest.raises(ConfigurationError) as exc_info:
            sim.configure(weights=[1.0], config={})
        assert exc_info.value.error_code == "CONFIGURE_BEFORE_LOAD"

    def test_configure_stores_weights_and_layers(self):
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(
            weights=[0.5, 0.8],
            config={"threshold": 0.6},
            layers=[ONE_TO_TWO_LAYER],
        )
        assert sim.weights == [0.5, 0.8]
        assert sim.layers == [ONE_TO_TWO_LAYER]
        assert sim.input_size == 1
        assert sim.output_size == 2
        assert sim.current_state == "configured"

    def test_run_before_configure_raises(self):
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        with pytest.raises(ConfigurationError) as exc_info:
            sim.run(input_spikes=[0])
        assert exc_info.value.error_code == "RUN_BEFORE_CONFIGURE"

    def test_run_empty_spikes_raises(self):
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=[1.0], config={}, layers=[ONE_TO_ONE_LAYER])
        with pytest.raises(DmaTransferError) as exc_info:
            sim.run(input_spikes=[])
        assert exc_info.value.error_code == "DMA_EMPTY_BUFFER"

    def test_run_produces_non_trivial_output(self):
        """Simulator must not just echo input — it runs a LIF model."""
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=[2.0], config={}, layers=[dict(ONE_TO_ONE_LAYER, threshold=2)])
        result = sim.run(input_spikes=[1], timesteps=1)
        # An input spike delivers a weight of 2 into a threshold of 2.
        assert result["output_spikes"] == [1]
        assert result["timesteps"] == 1
        assert "execution_time_us" in result

    def test_run_below_threshold_no_fire(self):
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=[1.0], config={}, layers=[dict(ONE_TO_ONE_LAYER, threshold=10)])
        result = sim.run(input_spikes=[1], timesteps=1)
        # One word per neuron per timestep: present, but not firing.
        assert result["output_spikes"] == [0]

    def test_state_machine_full_cycle(self):
        sim = PynqSimulator()
        assert sim.state == PynqState.UNLOADED
        sim.load_overlay("test.bit")
        assert sim.current_state == "loaded"
        sim.configure(weights=[1.0], config={}, layers=[ONE_TO_ONE_LAYER])
        assert sim.current_state == "configured"
        sim.run(input_spikes=[1])
        # After run, state goes back to CONFIGURED
        assert sim.current_state == "configured"

    def test_reset(self):
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=[1.0, 2.0], config={"threshold": 0.5})
        sim.reset()
        assert sim.current_state == "loaded"
        assert sim.weights == []
        assert sim.mmio_registers == {}

    def test_reset_before_load_raises(self):
        sim = PynqSimulator()
        with pytest.raises(ConfigurationError) as exc_info:
            sim.reset()
        assert exc_info.value.error_code == "RESET_BEFORE_LOAD"

    def test_weight_overflow_raises(self):
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        with pytest.raises(MmioWriteError) as exc_info:
            sim.configure(weights=[1.0] * (MAX_SYNAPSES + 1), config={})
        assert exc_info.value.error_code == "MMIO_WEIGHT_OVERFLOW"
