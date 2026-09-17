"""The simulator must behave exactly like the HLS engine.

These are the same cases as `hardware/pynq_z2/hls/snn_overlay_engine_tb.cpp`,
with the same expected outputs. The simulator is what the on-board self-test
compares against and what an on-board vs simulator accuracy delta is measured
from, so a divergence between the two means one of them is wrong.

Overlay-v1 shipped in exactly that state: a simulator running a plausible
integrate-and-fire model, and hardware that could not read its weights at all.
"""

from __future__ import annotations

import pytest

from neurochip.app.services.pynq_simulator import PynqSimulator


def _layer(
    input_size: int,
    output_size: int,
    *,
    weight_offset: int = 0,
    threshold: int = 10,
    leak_shift: int = 0,
    refractory: int = 0,
) -> dict[str, int]:
    return {
        "input_size": input_size,
        "output_size": output_size,
        "weight_offset": weight_offset,
        "threshold": threshold,
        "leak_shift": leak_shift,
        "refractory": refractory,
    }


def _run(
    layers: list[dict[str, int]],
    weights: list[float],
    frames: list[list[int]],
) -> list[list[int]]:
    simulator = PynqSimulator()
    simulator.load_overlay("snn_overlay.bit")
    simulator.configure(weights, {}, layers=layers)

    flat = [value for frame in frames for value in frame]
    result = simulator.run(flat, timesteps=len(frames))

    output_size = layers[-1]["output_size"]
    spikes = result["output_spikes"]
    return [spikes[index * output_size : (index + 1) * output_size] for index in range(len(frames))]


def test_identity_matrix_and_neuron_zero() -> None:
    """v1 defects 1 and 5: weights never arrived, and neuron 0 was silent."""
    weights = [0.0] * 16
    for neuron in range(4):
        weights[neuron * 4 + neuron] = 10.0

    frames = _run([_layer(4, 4)], weights, [[1, 0, 0, 0]])

    assert frames == [[1, 0, 0, 0]]


def test_integrates_across_timesteps() -> None:
    """v1 defect 4: the membrane was reset every timestep, so it never integrated."""
    frames = _run(
        [_layer(1, 1, threshold=10)],
        [3.0],
        [[1]] * 6,
    )

    # 3, 6, 9, 12 -> fires at timestep 3, resets, then 3, 6.
    assert frames == [[0], [0], [0], [1], [0], [0]]


def test_membrane_decays_without_input() -> None:
    """v1 defect 4, second half: there was no leak term at all."""
    leaky = _run(
        [_layer(1, 1, threshold=20, leak_shift=1)],
        [8.0],
        [[1], [1], [0], [0]],
    )
    assert leaky == [[0], [0], [0], [0]]

    # Three spikes with no leak crosses 20; the same input with leak does not.
    assert _run([_layer(1, 1, threshold=20)], [8.0], [[1]] * 3)[-1] == [1]
    assert _run([_layer(1, 1, threshold=20, leak_shift=1)], [8.0], [[1]] * 3)[-1] == [0]


def test_refractory_period_suppresses_firing() -> None:
    frames = _run(
        [_layer(1, 1, threshold=10, refractory=2)],
        [100.0],
        [[1]] * 7,
    )

    assert frames == [[1], [0], [0], [1], [0], [0], [1]]


def test_two_layer_chain() -> None:
    """v1 held exactly one weight matrix."""
    layers = [_layer(2, 2, weight_offset=0), _layer(2, 1, weight_offset=4)]
    weights = [10.0, 0.0, 0.0, 10.0, 10.0, 0.0]

    assert _run(layers, weights, [[1, 0]]) == [[1]]
    # The second layer's weights actually gate the output.
    assert _run(layers, weights, [[0, 1]]) == [[0]]


def test_stream_framing_is_one_frame_per_timestep() -> None:
    """v1 defect 6: the two sides disagreed on how many words a run moves."""
    simulator = PynqSimulator()
    simulator.load_overlay("snn_overlay.bit")
    simulator.configure([0.0] * 6, {}, layers=[_layer(3, 2, threshold=1000)])

    result = simulator.run([0] * 15, timesteps=5)

    assert len(result["output_spikes"]) == 10
    assert result["output_neurons"] == 2


def test_wrongly_sized_input_is_refused() -> None:
    simulator = PynqSimulator()
    simulator.load_overlay("snn_overlay.bit")
    simulator.configure([0.0] * 6, {}, layers=[_layer(3, 2)])

    with pytest.raises(Exception, match="Expected 15 input words"):
        simulator.run([0] * 12, timesteps=5)
