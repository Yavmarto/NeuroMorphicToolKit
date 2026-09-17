"""Brunel (2000) balanced E/I network helpers for brian2_sim verification.

ponytail: scaled miniature (default 40E/10I) — full N=10k paper scale needs
a dedicated Brian2 script outside CNL/NIR until sparse codegen lands.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import nir
import numpy as np

# Default miniature sizes (Brunel uses f=0.8 excitatory fraction).
DEFAULT_N_EXT = 20
DEFAULT_N_E = 40
DEFAULT_N_I = 10
DEFAULT_P = 0.1
DEFAULT_G = 5.0  # inhibitory gain; async-irregular regime near g≈4–6 in paper units
DEFAULT_J = 0.1
DEFAULT_SEED = 2000


@dataclass(frozen=True, slots=True)
class BrunelMetrics:
    """Population spike statistics for dynamics verification."""

    mean_rate_hz: float
    cv_isi: float
    spike_count: int
    neuron_count: int


@dataclass(frozen=True, slots=True)
class BrunelRegimeCheck:
    """Pass/fail against Brunel async-irregular heuristics."""

    ok: bool
    mean_rate_hz: float
    cv_isi: float
    notes: tuple[str, ...]


def brunel_cnl_spec(
    *,
    n_ext: int = DEFAULT_N_EXT,
    n_e: int = DEFAULT_N_E,
    n_i: int = DEFAULT_N_I,
    seed: int = DEFAULT_SEED,
) -> str:
    """Return CNL for a recurrent E/I network (Studio / compile_to_nir entry)."""
    return f"""Define a network named brunel_ei with timestep 0.001.
Define an input port named external with shape ({n_ext},).
Define a LIF neuron named excitatory with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define a LIF neuron named inhibitory with time constant 0.01, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define a linear transformation named w_ext_e with weight matrix shape ({n_e}, {n_ext}) annotated with metadata weight_init equal to "xavier" annotated with metadata seed equal to {seed}.
Define a linear transformation named w_e_e with weight matrix shape ({n_e}, {n_e}) annotated with metadata weight_init equal to "xavier" annotated with metadata seed equal to {seed + 1}.
Define a linear transformation named w_e_i with weight matrix shape ({n_i}, {n_e}) annotated with metadata weight_init equal to "xavier" annotated with metadata seed equal to {seed + 2}.
Define a linear transformation named w_i_e with weight matrix shape ({n_e}, {n_i}) annotated with metadata weight_init equal to "xavier" annotated with metadata seed equal to {seed + 3}.
Define a linear transformation named w_i_i with weight matrix shape ({n_i}, {n_i}) annotated with metadata weight_init equal to "xavier" annotated with metadata seed equal to {seed + 4}.
Define an output port named output with shape ({n_e},).
external connects to w_ext_e.
w_ext_e connects to excitatory.
excitatory connects to w_e_e.
w_e_e connects to excitatory.
excitatory connects to w_e_i.
w_e_i connects to inhibitory.
inhibitory connects to w_i_e.
w_i_e connects to excitatory.
inhibitory connects to w_i_i.
w_i_i connects to inhibitory.
excitatory connects to output.
"""


def apply_brunel_weights(
    graph: nir.NIRGraph,
    *,
    p: float = DEFAULT_P,
    g: float = DEFAULT_G,
    j: float = DEFAULT_J,
    seed: int = DEFAULT_SEED,
) -> nir.NIRGraph:
    """Re-sign and sparsify compiled Linear weights to Brunel-style E/I coupling."""
    rng = np.random.default_rng(seed)
    nodes = dict(graph.nodes)
    inhibitory_names = {"w_i_e", "w_i_i"}

    for name, node in nodes.items():
        if not isinstance(node, nir.Linear):
            continue
        weight = np.asarray(node.weight, dtype=float)
        mask = rng.random(weight.shape) < p
        scaled = np.where(mask, j, 0.0)
        if name in inhibitory_names:
            scaled = -g * np.abs(scaled)
        nodes[name] = nir.Linear(weight=scaled)

    return nir.NIRGraph(nodes=nodes, edges=list(graph.edges), type_check=False)


def population_spike_times(
    spikes: dict[str, list[int]],
    *,
    dt_ms: float = 1.0,
) -> list[float]:
    """Flatten per-neuron spike index lists into sorted times in ms."""
    times: list[float] = []
    for index_list in spikes.values():
        times.extend(float(t) * dt_ms for t in index_list)
    return sorted(times)


def mean_firing_rate_hz(
    spikes: dict[str, list[int]],
    *,
    neuron_count: int,
    duration_ms: float,
    dt_ms: float = 1.0,
) -> float:
    """Mean population firing rate in Hz."""
    if neuron_count <= 0 or duration_ms <= 0:
        return 0.0
    total_spikes = sum(len(v) for v in spikes.values())
    return total_spikes / neuron_count / (duration_ms / 1000.0)


def coefficient_of_variation_isi(
    spikes: dict[str, list[int]],
    *,
    dt_ms: float = 1.0,
) -> float:
    """CV of inter-spike intervals across neurons (irregular ≈ 1 in Brunel AI regime)."""
    intervals: list[float] = []
    for index_list in spikes.values():
        if len(index_list) < 2:
            continue
        times = [float(t) * dt_ms for t in sorted(index_list)]
        intervals.extend(times[i + 1] - times[i] for i in range(len(times) - 1))
    if len(intervals) < 2:
        return 0.0
    arr = np.asarray(intervals, dtype=float)
    mean = float(arr.mean())
    if mean <= 0:
        return 0.0
    return float(arr.std(ddof=0) / mean)


def summarize_spikes(
    spikes: dict[str, list[int]],
    *,
    neuron_count: int,
    duration_ms: float,
    dt_ms: float = 1.0,
) -> BrunelMetrics:
    """Aggregate raster statistics for one monitored population."""
    return BrunelMetrics(
        mean_rate_hz=mean_firing_rate_hz(
            spikes,
            neuron_count=neuron_count,
            duration_ms=duration_ms,
            dt_ms=dt_ms,
        ),
        cv_isi=coefficient_of_variation_isi(spikes, dt_ms=dt_ms),
        spike_count=sum(len(v) for v in spikes.values()),
        neuron_count=neuron_count,
    )


def check_async_irregular_regime(
    metrics: BrunelMetrics,
    *,
    rate_min_hz: float = 1.0,
    rate_max_hz: float = 80.0,
    cv_min: float = 0.5,
) -> BrunelRegimeCheck:
    """Heuristic pass for Brunel-style irregular asynchronous firing.

    ponytail: wide bands — full paper replication needs longer runs and
    larger N; these thresholds catch silent/frozen vs bursty failure modes.
    """
    notes: list[str] = []
    ok = True
    if metrics.spike_count == 0:
        ok = False
        notes.append("no spikes recorded")
    if not (rate_min_hz <= metrics.mean_rate_hz <= rate_max_hz):
        ok = False
        notes.append(
            f"mean rate {metrics.mean_rate_hz:.2f} Hz outside "
            f"[{rate_min_hz}, {rate_max_hz}]"
        )
    if metrics.cv_isi < cv_min and metrics.spike_count > metrics.neuron_count:
        ok = False
        notes.append(f"CV_ISI {metrics.cv_isi:.2f} below {cv_min} (too regular)")
    if not notes:
        notes.append(
            f"async-irregular heuristic pass: "
            f"{metrics.mean_rate_hz:.1f} Hz, CV_ISI={metrics.cv_isi:.2f}"
        )
    return BrunelRegimeCheck(
        ok=ok,
        mean_rate_hz=metrics.mean_rate_hz,
        cv_isi=metrics.cv_isi,
        notes=tuple(notes),
    )


def expected_regime_summary() -> str:
    """One-line reference to Brunel (2000) regime labels for reports."""
    return (
        "Brunel 2000: low g → synchronous regular (SR); mid g ≈ 4–6 → "
        "asynchronous irregular (AI); high g → fast oscillations (FO)."
    )
