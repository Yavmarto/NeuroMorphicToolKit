import io
import struct
import zipfile
from unittest.mock import MagicMock, patch

import pytest

from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.loihi_generator import (
    _build_template_context,
    _generate_mock_hdf5_bytes,
    generate_loihi_package,
)


@pytest.fixture
def sample_network():
    return NetworkInput(
        num_neurons=2000,
        num_synapses=5000,
        neuron_model="LIF",
        populations=[{"name": "input", "size": 1000}, {"name": "output", "size": 1000}],
        connections=[{"pre": "input", "post": "output", "weight_count": 5000}],
        weight_bit_width=8,
        network_depth=2,
    )


def test_build_template_context(sample_network):
    context = _build_template_context(
        sample_network, bit_width=16, board_id="test_board", num_steps=500
    )

    assert context["network_name"] == "SNN Network"
    assert context["board_id"] == "test_board"
    assert context["num_steps"] == 500
    assert context["bit_width"] == 16
    assert context["num_cores"] == 1  # 2000 // 1024 = 1
    assert len(context["populations"]) == 2
    assert len(context["connections"]) == 1
    assert context["populations"][0]["name"] == "input"
    assert context["connections"][0]["pre"] == "input"


def test_build_template_context_large_network():
    net = NetworkInput(
        num_neurons=5000,
        num_synapses=10000,
        neuron_model="LIF",
        populations=[{"name": "p1", "size": 5000}],
        connections=[],
        weight_bit_width=8,
        network_depth=1,
    )
    context = _build_template_context(net)
    assert context["num_cores"] == 4  # 5000 // 1024 = 4


def test_generate_mock_hdf5_bytes_8bit(sample_network):
    data = _generate_mock_hdf5_bytes(sample_network, bit_width=8)
    # 1 connection: pre_size(I), post_size(I), 5000 weights (b)
    # 4 + 4 + 5000 = 5008 bytes
    assert len(data) == 5008
    # Check first few bytes for pre_size and post_size (1000, 1000)
    pre, post = struct.unpack("II", data[:8])
    assert pre == 1000
    assert post == 1000
    assert data[8] == 0


def test_generate_mock_hdf5_bytes_32bit(sample_network):
    data = _generate_mock_hdf5_bytes(sample_network, bit_width=32)
    # 1 connection: pre_size(I), post_size(I), 5000 weights (f)
    # 4 + 4 + 5000 * 4 = 20008 bytes
    assert len(data) == 20008
    pre, post = struct.unpack("II", data[:8])
    assert pre == 1000
    assert post == 1000
    weight = struct.unpack("f", data[8:12])[0]
    assert weight == 0.0


@patch("neurochip.app.services.loihi_generator.cache_manager")
@patch("neurochip.app.services.loihi_generator.Environment")
def test_generate_loihi_package_cache_miss(mock_env_class, mock_cache, sample_network):
    mock_cache.get_cached_artifact.return_value = None

    mock_template = MagicMock()
    mock_template.render.return_value = "rendered_content"
    mock_env = MagicMock()
    mock_env.get_template.return_value = mock_template
    mock_env_class.return_value = mock_env

    progress_callback = MagicMock()

    package_bytes = generate_loihi_package(
        sample_network, bit_width=8, progress_callback=progress_callback
    )

    assert isinstance(package_bytes, bytes)
    assert progress_callback.call_count > 0
    # Last call should be 1.0
    progress_callback.assert_any_call(1.0, "Loihi package generation complete")

    # Verify zip content
    with zipfile.ZipFile(io.BytesIO(package_bytes)) as zf:
        assert "loihi_deploy/deploy.py" in zf.namelist()
        assert "loihi_deploy/config.json" in zf.namelist()
        assert "loihi_deploy/crossbar_weights.bin" in zf.namelist()
        assert "loihi_deploy/README.md" in zf.namelist()

    mock_cache.cache_artifact.assert_called_once()


@patch("neurochip.app.services.loihi_generator.cache_manager")
def test_generate_loihi_package_cache_hit(mock_cache, sample_network):
    cached_data = b"cached_zip_content"
    mock_cache.get_cached_artifact.return_value = cached_data

    progress_callback = MagicMock()

    package_bytes = generate_loihi_package(sample_network, progress_callback=progress_callback)

    assert package_bytes == cached_data
    progress_callback.assert_called_with(1.0, "Cache hit, returning artifact")
