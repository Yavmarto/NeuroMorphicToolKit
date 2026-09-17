"""Density aggregation for large-scale spike data."""

from typing import Literal

import numpy as np

from ...contracts.design_contracts import (
    BulkSpikeFrame,
    NodeBulkData,
    PreviewNodePlayback,
)

_LARGE_NETWORK_THRESHOLD = 5_000


def should_use_bulk_frame(total_neuron_count: int) -> bool:
    """Return True when spike count warrants compact bulk encoding."""
    return total_neuron_count > _LARGE_NETWORK_THRESHOLD


def _scale_hint_for(total_neurons: int) -> Literal["raster", "particle", "density"]:
    if total_neurons <= 1_000:  # noqa: PLR2004
        return "raster"
    if total_neurons <= 100_000:  # noqa: PLR2004
        return "particle"
    return "density"


def _build_node_bulk_data(
    spike_trains: dict[str, list[float]],  # "{node_id}:{local_index}" -> [spike_time_ms, ...]
    duration_ms: float,
    grid_w: int,
    grid_h: int,
) -> NodeBulkData:
    """Build one node's NodeBulkData from its own spike_trains dict.

    Keys are "{node_id}:{local_index}" (unchanged upstream format); only the
    suffix after ':' is needed to recover local_index, since spike_trains
    here is already scoped to a single node. Sorted numerically on that
    index rather than lexicographically — lexicographic sort would order
    "n:10" before "n:2" once a node has 10+ neurons.
    """
    keys_sorted = sorted(spike_trains.keys(), key=lambda k: int(k.rsplit(":", 1)[-1]))

    data: list[float] = []
    for local_idx, key in enumerate(keys_sorted):
        for t in spike_trains[key]:
            data.append(float(local_idx))
            data.append(float(t))

    grid = np.zeros((grid_h, grid_w), dtype=np.float32)
    n_neurons = len(keys_sorted)
    if n_neurons > 0 and duration_ms > 0:
        for local_idx, key in enumerate(keys_sorted):
            row_idx = min(int(local_idx * grid_h / n_neurons), grid_h - 1)
            for t in spike_trains[key]:
                col_idx = min(int((t / duration_ms) * grid_w), grid_w - 1)
                grid[row_idx, col_idx] += 1.0
        max_val = grid.max()
        if max_val > 0:
            grid /= max_val

    return NodeBulkData(
        data=data,
        density_grid=grid.flatten().tolist(),
        grid_w=grid_w,
        grid_h=grid_h,
        neuron_count=n_neurons,
    )


def build_bulk_spike_frame(
    playback_nodes: list[PreviewNodePlayback],
    total_neurons: int,
    duration_ms: float,
    grid_w: int = 64,
    grid_h: int = 64,
) -> BulkSpikeFrame:
    """Convert per-node playback data into a node-partitioned BulkSpikeFrame.

    Args:
        playback_nodes: One PreviewNodePlayback per canvas node.
        total_neurons: Network-wide neuron count (drives scale_hint only).
        duration_ms: Simulation window length in milliseconds.
        grid_w: Width of each node's density grid (time axis).
        grid_h: Height of each node's density grid (neuron axis).

    Returns:
        A BulkSpikeFrame with one NodeBulkData per node in playback_nodes.
    """
    nodes = {
        node.node_id: _build_node_bulk_data(node.spike_trains, duration_ms, grid_w, grid_h)
        for node in playback_nodes
    }
    return BulkSpikeFrame(nodes=nodes, scale_hint=_scale_hint_for(total_neurons))
