"""Property-based tests for the PYNQ runtime (Hypothesis).

These tests verify invariants that must hold for *any* valid input,
complementing the unit tests in ``test_pynq_backend_core.py`` and
``test_pynq_backend_simulator.py``.
"""

from __future__ import annotations

from hypothesis import given, settings
from hypothesis import strategies as st

from neurochip.app.services.pynq_simulator import PynqSimulator

# Strategy: valid weight lists (1–100 weights, reasonable range)
valid_weights = st.lists(
    st.floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False),
    min_size=1,
    max_size=100,
)

# Strategy: valid layer shapes. The overlay reads a dense post-by-pre matrix,
# so the weight buffer size is fixed by the shape rather than free.
valid_shapes = st.tuples(
    st.integers(min_value=1, max_value=8), st.integers(min_value=1, max_value=8)
)

# Strategy: valid timestep counts
valid_timesteps = st.integers(min_value=1, max_value=20)


def _layer(input_size: int, output_size: int, threshold: int = 1) -> dict[str, int]:
    return {
        "input_size": input_size,
        "output_size": output_size,
        "weight_offset": 0,
        "threshold": threshold,
        "leak_shift": 0,
        "refractory": 0,
    }


# Strategy: valid thresholds (positive, finite)
valid_thresholds = st.floats(min_value=0.01, max_value=100.0, allow_nan=False, allow_infinity=False)


class TestPynqRuntimeProperties:
    """Invariants that must hold for any valid PYNQ simulator input."""

    @given(shape=valid_shapes, timesteps=valid_timesteps, data=st.data())
    @settings(max_examples=50, deadline=None)
    def test_output_is_one_binary_word_per_neuron_per_timestep(
        self, shape: tuple[int, int], timesteps: int, data: st.DataObject
    ) -> None:
        """The output frame shape is fixed by the network, not by the input.

        Overlay-v1's host sized the output buffer from the input length and its
        engine emitted neuron indices, which made a firing neuron 0 identical to
        silence.
        """
        input_size, output_size = shape
        weights = data.draw(
            st.lists(
                st.floats(min_value=-10.0, max_value=10.0, allow_nan=False, allow_infinity=False),
                min_size=input_size * output_size,
                max_size=input_size * output_size,
            )
        )
        spikes = data.draw(
            st.lists(
                st.integers(min_value=0, max_value=1),
                min_size=input_size * timesteps,
                max_size=input_size * timesteps,
            )
        )

        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=weights, config={}, layers=[_layer(input_size, output_size)])
        result = sim.run(input_spikes=spikes, timesteps=timesteps)

        assert len(result["output_spikes"]) == output_size * timesteps
        assert all(value in (0, 1) for value in result["output_spikes"])

    @given(shape=valid_shapes, timesteps=valid_timesteps, data=st.data())
    @settings(max_examples=50, deadline=None)
    def test_result_always_has_required_keys(
        self, shape: tuple[int, int], timesteps: int, data: st.DataObject
    ) -> None:
        """The result dict must always contain the expected keys."""
        input_size, output_size = shape
        weights = [1.0] * (input_size * output_size)
        spikes = data.draw(
            st.lists(
                st.integers(min_value=0, max_value=1),
                min_size=input_size * timesteps,
                max_size=input_size * timesteps,
            )
        )

        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=weights, config={}, layers=[_layer(input_size, output_size)])
        result = sim.run(input_spikes=spikes, timesteps=timesteps)

        assert "output_spikes" in result
        assert "timesteps" in result
        assert "execution_time_us" in result
        assert result["timesteps"] == timesteps

    @given(weights=valid_weights, threshold=valid_thresholds)
    @settings(max_examples=50, deadline=None)
    def test_configure_never_raises_for_valid_input(
        self, weights: list[float], threshold: float
    ) -> None:
        """Any valid weight list with a positive threshold must configure OK."""
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=weights, config={"threshold": threshold})
        assert sim.current_state == "configured"

    @given(shape=valid_shapes)
    @settings(max_examples=50, deadline=None)
    def test_state_returns_to_configured_after_run(self, shape: tuple[int, int]) -> None:
        """After a successful run, the simulator must be back in CONFIGURED."""
        input_size, output_size = shape
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(
            weights=[1.0] * (input_size * output_size),
            config={},
            layers=[_layer(input_size, output_size)],
        )
        sim.run(input_spikes=[1] * input_size)
        assert sim.current_state == "configured"

    @given(weights=valid_weights)
    @settings(max_examples=30, deadline=None)
    def test_reset_clears_weights(self, weights: list[float]) -> None:
        """After reset, internal weight storage must be empty."""
        sim = PynqSimulator()
        sim.load_overlay("test.bit")
        sim.configure(weights=weights, config={})
        sim.reset()
        assert sim.weights == []
        assert sim.current_state == "loaded"
