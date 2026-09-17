"""Per-neuron spike-train correlation for captured SNN activity.

The v1 network view computes "fire together, wire together" co-activation
client-side over *layer-level* spike rates (CEL-140). That is deliberately a
coarse proxy: it compares how whole layers' aggregate firing rates move
together, not individual neurons. This module adds the real per-neuron measure
the CEL-138 proposal flagged as a backend follow-up.

Given a layer's captured spike matrix ``(T, N)`` — one row per simulation
timestep, one column per neuron, values 0/1 — it computes the pairwise Pearson
correlation of every neuron pair (for binary trains this is the phi
coefficient) plus connected-component clusters above a threshold.

The computation is pure NumPy so it can be unit-tested without torch, a
running job, or a trained network. Zip loading mirrors the layer lookup used
by ``routers/training.py`` for the activity download and comparison endpoints.
"""

from __future__ import annotations

import base64
import io
import zipfile
from dataclasses import dataclass
from typing import Any

import numpy as np

# Minimum co-present timesteps before a pair's correlation is reported. Below
# this a Pearson coefficient over binary trains is too noisy to be meaningful.
DEFAULT_MIN_SAMPLES = 8

# Correlation at or above this joins two neurons into the same cluster.
DEFAULT_CLUSTER_THRESHOLD = 0.5

# Upper bound on the neurons correlated in one call. Pairwise correlation is
# O(n^2), so a wide layer is capped to its most active neurons (the ones a
# "fire together" grouping is actually about) rather than allowed to blow up.
DEFAULT_MAX_NEURONS = 512

# Upper bound on returned links. Clusters are always computed over *all*
# pairs, so capping the response never changes the grouping — only how many
# individual pairs are shipped to the client.
DEFAULT_MAX_LINKS = 2000


@dataclass(frozen=True)
class NeuronLink:
    """One pair of neurons and their spike-train correlation."""

    source: int
    target: int
    correlation: float
    co_active_samples: int


@dataclass(frozen=True)
class NeuronCorrelationResult:
    """Per-neuron correlation snapshot for one layer of one job.

    ``neuron_indices`` maps each analyzed column back to its position in the
    original ``(T, N)`` spike matrix, so callers can address individual
    neurons even after the most-active-neuron cap has been applied.
    """

    neuron_count: int
    analyzed_neuron_count: int
    time_samples: int
    truncated: bool
    threshold: float
    min_samples: int
    links: list[NeuronLink]
    clusters: list[list[int]]
    neuron_indices: list[int]
    spike_counts: list[int]

    @property
    def total_pairs(self) -> int:
        """Number of neuron pairs examined (before the link cap)."""
        return self.analyzed_neuron_count * (self.analyzed_neuron_count - 1) // 2


def _as_spike_matrix(spikes: np.ndarray[Any, Any]) -> np.ndarray[Any, Any]:
    """Coerce arbitrary captured activity into a ``(T, N)`` float matrix.

    The capture stack stores one flattened ``(N,)`` spike row per timestep, so
    a well-formed array is already 2-D. Anything with extra trailing dims is
    flattened into the neuron axis; a 1-D array is a single neuron over time.
    """
    matrix = np.asarray(spikes, dtype=np.float64)
    if matrix.ndim == 0:
        return matrix.reshape(1, 1)
    if matrix.ndim == 1:
        return matrix.reshape(-1, 1)
    if matrix.ndim > 2:
        return matrix.reshape(matrix.shape[0], -1)
    return matrix


def compute_neuron_correlation(
    spikes: np.ndarray[Any, Any],
    *,
    min_samples: int = DEFAULT_MIN_SAMPLES,
    threshold: float = DEFAULT_CLUSTER_THRESHOLD,
    max_neurons: int = DEFAULT_MAX_NEURONS,
    max_links: int = DEFAULT_MAX_LINKS,
) -> NeuronCorrelationResult:
    """Compute per-neuron spike-train correlation for one layer.

    Args:
        spikes: ``(T, N)`` (or flattenable) array of per-timestep spike
            indicators. Rows are timesteps, columns are neurons.
        min_samples: Minimum timesteps required before correlations are
            reported. Fewer than two active neurons also yields no links.
        threshold: Correlation at or above which two neurons are grouped into
            the same cluster.
        max_neurons: Cap on correlated neurons; the most active are kept.
        max_links: Cap on returned links, strongest correlation first.

    Returns:
        A :class:`NeuronCorrelationResult`. Neurons whose spike train never
        varies (always 0 or always 1) have an undefined correlation and are
        excluded from the links.
    """
    matrix = _as_spike_matrix(spikes)
    time_samples, neuron_count = matrix.shape

    spike_counts_full = matrix.sum(axis=0)
    truncated = neuron_count > max_neurons
    if truncated:
        keep = np.argsort(-spike_counts_full, kind="stable")[:max_neurons]
        indices = sorted(int(i) for i in keep)
    else:
        indices = list(range(neuron_count))

    index_array = np.asarray(indices, dtype=np.intp)
    selected = matrix[:, index_array]
    spike_counts = [int(c) for c in spike_counts_full[index_array]]

    empty = NeuronCorrelationResult(
        neuron_count=neuron_count,
        analyzed_neuron_count=len(indices),
        time_samples=time_samples,
        truncated=truncated,
        threshold=threshold,
        min_samples=min_samples,
        links=[],
        clusters=[],
        neuron_indices=indices,
        spike_counts=spike_counts,
    )

    if time_samples < min_samples or len(indices) < 2:
        return empty

    means = selected.mean(axis=0)
    stds = selected.std(axis=0)
    active = np.flatnonzero(stds > 0)
    if active.size < 2:
        return empty

    active_indices = index_array[active]
    standardised = (selected[:, active] - means[active]) / stds[active]
    correlation = (standardised.T @ standardised) / time_samples

    upper = np.triu_indices(active.size, k=1)
    raw = correlation[upper]
    finite = np.isfinite(raw)
    pair_a = active_indices[upper[0][finite]]
    pair_b = active_indices[upper[1][finite]]
    values = raw[finite]

    order = np.lexsort((pair_b, pair_a, -values))
    all_links = [
        NeuronLink(
            source=int(pair_a[i]),
            target=int(pair_b[i]),
            correlation=round(float(values[i]), 6),
            co_active_samples=time_samples,
        )
        for i in order
    ]

    clusters = _clusters_from_links(all_links, threshold)
    links = all_links[: max_links if max_links > 0 else 0]

    return NeuronCorrelationResult(
        neuron_count=neuron_count,
        analyzed_neuron_count=len(indices),
        time_samples=time_samples,
        truncated=truncated,
        threshold=threshold,
        min_samples=min_samples,
        links=links,
        clusters=clusters,
        neuron_indices=indices,
        spike_counts=spike_counts,
    )


def _clusters_from_links(links: list[NeuronLink], threshold: float) -> list[list[int]]:
    """Connected components over links at or above ``threshold``.

    Size >= 2 only, largest first (ties broken by lowest neuron index) — the
    same shape the client-side proxy returns, so the two can share UI code.
    """
    parent: dict[int, int] = {}

    def find(node: int) -> int:
        parent.setdefault(node, node)
        root = node
        while parent[root] != root:
            root = parent[root]
        while parent[node] != root:
            parent[node], node = root, parent[node]
        return root

    for link in links:
        if link.correlation < threshold:
            continue
        root_a = find(link.source)
        root_b = find(link.target)
        if root_a != root_b:
            parent[root_b] = root_a

    groups: dict[int, list[int]] = {}
    for node in parent:
        groups.setdefault(find(node), []).append(node)

    clusters = [sorted(group) for group in groups.values() if len(group) >= 2]
    clusters.sort(key=lambda group: (-len(group), group[0]))
    return clusters


def available_activity_layers(activity_zip_b64: str) -> list[str]:
    """Return the layer stems stored in a captured activity zip.

    Activity entries are written as ``{layer}_spikes.npy``; the stem (with the
    ``_spikes.npy`` suffix removed) is what callers pass back as ``layer``.
    """
    try:
        zip_bytes = base64.b64decode(activity_zip_b64)
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
            names = archive.namelist()
    except Exception:
        return []

    layers: list[str] = []
    for name in names:
        stem = name.rsplit("/", 1)[-1]
        if stem.endswith("_spikes.npy"):
            layers.append(stem[: -len("_spikes.npy")])
        elif stem.endswith(".npy"):
            layers.append(stem[: -len(".npy")])
    return sorted(set(layers))


def load_layer_spikes(activity_zip_b64: str, layer: str) -> np.ndarray[Any, Any] | None:
    """Load one layer's ``(T, N)`` spike matrix from a captured activity zip.

    The match rule mirrors the activity comparison endpoint: an exact
    ``{layer}.npy`` entry wins, otherwise the first entry whose name starts
    with ``layer`` (so ``hidden`` matches ``hidden_spikes.npy``).
    """
    try:
        zip_bytes = base64.b64decode(activity_zip_b64)
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as archive:
            names = archive.namelist()
            target = f"{layer}.npy"
            match = next(
                (name for name in names if name == target or name.startswith(layer)),
                None,
            )
            if match is None:
                return None
            raw = archive.read(match)
    except Exception:
        return None

    try:
        return np.asarray(np.load(io.BytesIO(raw)))
    except Exception:
        return None
