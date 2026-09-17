import io
import zipfile
from unittest.mock import MagicMock, patch

import pytest

from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.teensy_generator import _build_template_context, generate_teensy_project


@pytest.fixture
def sample_network():
    return NetworkInput(
        num_neurons=10,
        num_synapses=20,
        neuron_model="LIF",
        populations=[
            {"name": "in", "size": 4},
            {"name": "hidden", "size": 3},
            {"name": "out", "size": 3},
        ],
        connections=[
            {"pre": "in", "post": "hidden", "weight_count": 12},
            {"pre": "hidden", "post": "out", "weight_count": 8},
        ],
        weight_bit_width=8,
        network_depth=3,
    )


def test_build_template_context_without_weights(sample_network):
    context = _build_template_context(sample_network, bit_width=8)

    assert context["num_neurons"] == 10
    assert context["num_synapses"] == 20
    assert len(context["synapses"]) == 20
    assert context["num_inputs"] == 4
    assert context["num_outputs"] == 3
    assert context["input_neuron_ids"] == [0, 1, 2, 3]
    assert context["output_neuron_ids"] == [7, 8, 9]
    assert all(s["weight"] == 0 for s in context["synapses"])

    # Check synapse mapping for second connection (hidden -> out)
    # hidden starts at offset 4, out starts at offset 7
    # pre_offset = 4, post_offset = 7
    # pre_size = 3, post_size = 3
    # num_synapses = min(8, 9) = 8
    # first synapse of second connection: pre = 4 + (0 % 3) = 4, post = 7 + (0 // 3) % 3 = 7
    s = context["synapses"][12]
    assert s["pre"] == 4
    assert s["post"] == 7


def test_build_template_context_with_weights(sample_network):
    weights = [i for i in range(20)]
    context = _build_template_context(sample_network, quantized_weights=weights)

    assert context["weights"] == weights
    assert context["synapses"][0]["weight"] == 0
    assert context["synapses"][19]["weight"] == 19


def test_build_template_context_with_pins(sample_network):
    input_pins = [1, 2, 3, 4]
    output_pins = [5, 6, 7]
    context = _build_template_context(
        sample_network, input_pins=input_pins, output_pins=output_pins
    )

    assert context["input_pins"] == input_pins
    assert context["output_pins"] == output_pins


def test_build_template_context_honors_population_and_connection_parameters():
    network = NetworkInput(
        num_neurons=4,
        num_synapses=4,
        neuron_model="LIF",
        populations=[
            {
                "name": "sensory",
                "size": 2,
                "threshold": 1.0,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            {
                "name": "motor",
                "size": 2,
                "threshold": 0.8,
                "tau_rc": 0.01,
                "tau_ref": 0.004,
            },
        ],
        connections=[
            {
                "pre": "sensory",
                "post": "motor",
                "weight_count": 4,
                "weight": 1.5,
                "delay": 0.003,
            },
        ],
        weight_bit_width=8,
        network_depth=2,
    )

    context = _build_template_context(network, bit_width=8)

    assert context["thresholds"] == [1.0, 1.0, 0.8, 0.8]
    assert context["refractory_steps"] == [2, 2, 4, 4]
    assert context["synapse_delay_steps"] == [3, 3, 3, 3]
    assert context["weights"] == [127, 127, 127, 127]
    assert context["max_delay_steps"] == 3
    assert context["tau_values"][0] != context["tau_values"][2]


@patch("neurochip.app.services.teensy_generator.cache_manager")
@patch("neurochip.app.services.teensy_generator.Environment")
def test_generate_teensy_project_cache_miss(mock_env_class, mock_cache, sample_network):
    mock_cache.get_cached_artifact.return_value = None

    mock_template = MagicMock()
    mock_template.render.return_value = "rendered_content"
    mock_env = MagicMock()
    mock_env.get_template.return_value = mock_template
    mock_env_class.return_value = mock_env

    progress_callback = MagicMock()

    project_bytes = generate_teensy_project(sample_network, progress_callback=progress_callback)

    assert isinstance(project_bytes, bytes)
    assert progress_callback.call_count > 0
    progress_callback.assert_any_call(1.0, "Teensy project generation complete")

    with zipfile.ZipFile(io.BytesIO(project_bytes)) as zf:
        namelist = zf.namelist()
        assert "neurochip_firmware/src/main.ino" in namelist
        assert "neurochip_firmware/src/network_params.h" in namelist
        assert "neurochip_firmware/src/lif_engine.h" in namelist
        assert "neurochip_firmware/platformio.ini" in namelist
        assert "neurochip_firmware/README.md" in namelist

    mock_cache.cache_artifact.assert_called_once()


@patch("neurochip.app.services.teensy_generator.cache_manager")
def test_generate_teensy_project_cache_hit(mock_cache, sample_network):
    cached_data = b"cached_zip_content"
    mock_cache.get_cached_artifact.return_value = cached_data

    progress_callback = MagicMock()

    project_bytes = generate_teensy_project(sample_network, progress_callback=progress_callback)

    assert project_bytes == cached_data
    progress_callback.assert_called_with(1.0, "Cache hit, returning artifact")
