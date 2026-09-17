# isort: skip_file
from neurosim.app.services import density_aggregator as da
from neurosim.contracts.design_contracts import PreviewNodePlayback


def test_should_use_bulk_frame() -> None:
    assert da.should_use_bulk_frame(4000) is False
    assert da.should_use_bulk_frame(6000) is True


def _playback_nodes() -> list[PreviewNodePlayback]:
    return [
        PreviewNodePlayback(
            node_id="pop_a",
            spike_trains={"pop_a:0": [10.0, 20.0], "pop_a:1": [15.0]},
        ),
        PreviewNodePlayback(
            node_id="pop_b",
            spike_trains={"pop_b:0": [5.0, 25.0, 35.0]},
        ),
    ]


def test_build_bulk_spike_frame_is_node_partitioned() -> None:
    frame = da.build_bulk_spike_frame(
        playback_nodes=_playback_nodes(),
        total_neurons=10,
        duration_ms=100.0,
        grid_w=10,
        grid_h=10,
    )

    assert set(frame.nodes.keys()) == {"pop_a", "pop_b"}

    pop_a = frame.nodes["pop_a"]
    assert pop_a.neuron_count == 2
    assert len(pop_a.data) == 6  # 3 spikes * 2 values (local index, time)
    assert pop_a.data[0] == 0.0  # pop_a:0 local index
    assert pop_a.data[1] == 10.0  # pop_a:0 first spike time
    assert len(pop_a.density_grid) == 100  # 10x10

    pop_b = frame.nodes["pop_b"]
    assert pop_b.neuron_count == 1
    assert len(pop_b.data) == 6  # 3 spikes * 2 values

    assert frame.scale_hint == "raster"

    frame_particle = da.build_bulk_spike_frame(_playback_nodes(), 50000, 100.0)
    assert frame_particle.scale_hint == "particle"

    frame_density = da.build_bulk_spike_frame(_playback_nodes(), 200000, 100.0)
    assert frame_density.scale_hint == "density"


def test_build_node_bulk_data_sorts_local_index_numerically_not_lexicographically() -> (
    None
):
    # "pop:10" must sort after "pop:2" — a lexicographic sort would invert this.
    spike_trains = {"pop:2": [5.0], "pop:10": [7.0]}
    node_data = da._build_node_bulk_data(
        spike_trains, duration_ms=100.0, grid_w=10, grid_h=10
    )

    assert node_data.data[0] == 0.0  # "pop:2" is local index 0
    assert node_data.data[1] == 5.0
    assert node_data.data[2] == 1.0  # "pop:10" is local index 1
    assert node_data.data[3] == 7.0
