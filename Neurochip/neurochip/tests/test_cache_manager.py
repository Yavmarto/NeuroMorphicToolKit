import pytest

from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.cache_manager import CacheManager


@pytest.fixture
def mock_network():
    return NetworkInput(
        num_neurons=10,
        num_synapses=20,
        neuron_model="lif",
        weight_bit_width=8,
        network_depth=1,
        populations=[{"name": "p1", "size": 10}],
        connections=[{"pre": "p1", "post": "p1", "weight_count": 20}],
    )


def test_cache_miss_and_hit(mock_network, tmp_path):
    cache_manager = CacheManager(cache_dir=tmp_path)

    # Miss
    artifact = cache_manager.get_cached_artifact(mock_network, "test_gen")
    assert artifact is None

    # Store
    test_data = b"test_artifact"
    cache_manager.cache_artifact(mock_network, "test_gen", test_data)

    # Hit
    artifact = cache_manager.get_cached_artifact(mock_network, "test_gen")
    assert artifact == test_data


def test_cache_key_params(mock_network, tmp_path):
    cache_manager = CacheManager(cache_dir=tmp_path)
    test_data1 = b"data1"
    test_data2 = b"data2"

    cache_manager.cache_artifact(mock_network, "gen", test_data1, param=1)
    cache_manager.cache_artifact(mock_network, "gen", test_data2, param=2)

    assert cache_manager.get_cached_artifact(mock_network, "gen", param=1) == test_data1
    assert cache_manager.get_cached_artifact(mock_network, "gen", param=2) == test_data2


def test_cache_different_generators(mock_network, tmp_path):
    cache_manager = CacheManager(cache_dir=tmp_path)
    cache_manager.cache_artifact(mock_network, "gen1", b"data1")
    cache_manager.cache_artifact(mock_network, "gen2", b"data2")

    assert cache_manager.get_cached_artifact(mock_network, "gen1") == b"data1"
    assert cache_manager.get_cached_artifact(mock_network, "gen2") == b"data2"


def test_cache_write_failure_does_not_block_artifact_generation(mock_network, tmp_path, caplog):
    cache_path = tmp_path / "not-a-directory"
    cache_path.write_text("cache unavailable")
    cache_manager = CacheManager(cache_dir=cache_path)

    cache_manager.cache_artifact(mock_network, "test_gen", b"artifact")

    assert "cache write unavailable" in caplog.text.lower()
