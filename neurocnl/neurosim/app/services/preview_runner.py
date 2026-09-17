"""Service for running simulation previews using Nengo."""

import logging
import os
import tempfile
import time
import uuid
from collections.abc import MutableMapping
from pathlib import Path
from typing import Any, NamedTuple

import nengo
import numpy as np

from ...contracts.design_contracts import (
    PreviewEdgeEvent,
    PreviewNodePlayback,
    PreviewPlayback,
    PreviewPlaybackSummary,
    PreviewSpikeEvent,
    SimulationStatus,
)
from ..schemas.preview import PreviewRequest, PreviewResponse
from .components import load_components
from .density_aggregator import build_bulk_spike_frame, should_use_bulk_frame
from .job_store import job_store
from .nir_support import (
    assess_preview_support,
    can_use_neurocnl_generator,
    generate_neurocnl_model,
    requires_local_faithful_preview,
)

logger = logging.getLogger(__name__)

MIN_PROBE_DATA_DIMENSIONS = 2
MAX_VOLTAGE_NEURONS_PREVIEW = 5


def _get_custom_neuron_type(block: Any, params: dict[str, Any]) -> Any | None:
    """Call an explicit custom ``to_nengo`` implementation when present."""
    if not block.source_path:
        raise ValueError(
            f"Custom component '{block.id}' has no source_path — cannot load"
        )
    import pathlib

    from nmtk_sdk import CustomNode
    from nmtk_sdk.loader import load_custom_node

    cls = load_custom_node(pathlib.Path(block.source_path))
    if cls.to_nengo is CustomNode.to_nengo:
        return None
    return cls().to_nengo(params)


class PreviewPayload(NamedTuple):
    """Combined legacy and structured preview payloads."""

    results: dict[str, Any]
    playback: PreviewPlayback


def ensure_nengo_runtime_cache(
    env: MutableMapping[str, str] | None = None,
) -> Path:
    """Ensure Nengo resolves its decoder cache to a writable runtime path."""

    runtime_env = os.environ if env is None else env

    configured_home = runtime_env.get("HOME", "").strip()
    home_path = Path(configured_home).expanduser() if configured_home else None
    if home_path is None or not home_path.exists() or not home_path.is_dir():
        home_path = Path(tempfile.gettempdir()) / "nmtk-runtime-home"
        home_path.mkdir(parents=True, exist_ok=True)
        runtime_env["HOME"] = str(home_path)

    configured_cache = runtime_env.get("XDG_CACHE_HOME", "").strip()
    cache_root = (
        Path(configured_cache).expanduser()
        if configured_cache
        else home_path / ".cache"
    )
    cache_root.mkdir(parents=True, exist_ok=True)
    runtime_env["XDG_CACHE_HOME"] = str(cache_root)

    decoder_cache_dir = cache_root / "nengo" / "decoders"
    decoder_cache_dir.mkdir(parents=True, exist_ok=True)

    # Nengo is already imported in this module, so also update the live rc config.
    nengo.rc.set("decoder_cache", "path", str(decoder_cache_dir))
    nengo.rc.set("decoder_cache", "enabled", "True")
    return decoder_cache_dir


def _build_ensemble(
    node: Any,
    components: dict[str, Any],
    ensembles: dict[str, nengo.Ensemble],
    spike_probes: dict[str, nengo.Probe],
    voltage_probes: dict[str, nengo.Probe],
) -> None:
    """Build the Nengo ensemble and probes for a single canvas node."""
    block = components.get(node.component_id)
    if not block:
        return

    params = {parameter.name: parameter.default for parameter in block.parameters}
    params.update(node.parameters)

    n_neurons = max(1, int(params.get("n_neurons", 100)))
    tau_rc = float(params.get("tau_rc", 0.02))
    tau_ref = float(params.get("tau_ref", 0.002))

    # Biological invariant: tau_ref < tau_rc
    if tau_ref >= tau_rc:
        raise ValueError(
            f"Biological invariant violated: tau_ref ({tau_ref}) must be less than tau_rc ({tau_rc})",
        )

    effective_component_id = (
        getattr(block, "base_component_id", None) or node.component_id
    )
    custom_neuron_type = (
        _get_custom_neuron_type(block, params)
        if getattr(block, "is_custom", False)
        else None
    )
    if custom_neuron_type is not None:
        neuron_type = custom_neuron_type
    elif effective_component_id == "adaptive_lif":
        neuron_type = nengo.AdaptiveLIF(tau_rc=tau_rc, tau_ref=tau_ref)
    else:
        neuron_type = nengo.LIF(tau_rc=tau_rc, tau_ref=tau_ref)

    max_rate_limit = 1.0 / tau_ref if tau_ref > 0 else 1000.0
    max_rates = nengo.dists.Uniform(
        min(200, max_rate_limit * 0.5),
        min(400, max_rate_limit * 0.9),
    )

    ensemble = nengo.Ensemble(
        n_neurons=n_neurons,
        dimensions=1,
        neuron_type=neuron_type,
        max_rates=max_rates,
        seed=42,
        label=node.id,
    )
    ensembles[node.id] = ensemble
    spike_probes[node.id] = nengo.Probe(ensemble.neurons, "output")
    voltage_probes[node.id] = nengo.Probe(ensemble.neurons, "voltage")


def _build_preview_model(
    request: PreviewRequest,
) -> tuple[
    nengo.Network,
    dict[str, nengo.Ensemble],
    dict[str, nengo.Probe],
    dict[str, nengo.Probe],
]:
    """Build the Nengo preview network and associated probes."""
    components = load_components()
    ensembles: dict[str, nengo.Ensemble] = {}
    spike_probes: dict[str, nengo.Probe] = {}
    voltage_probes: dict[str, nengo.Probe] = {}

    model = nengo.Network(label="Preview Network")
    with model:
        for node in request.graph.nodes:
            _build_ensemble(node, components, ensembles, spike_probes, voltage_probes)

        for edge in request.graph.edges:
            if (
                edge.source_node_id not in ensembles
                or edge.target_node_id not in ensembles
            ):
                continue

            source = ensembles[edge.source_node_id]
            target = ensembles[edge.target_node_id]
            weight = float(edge.parameters.get("weight", 1.0))
            delay = float(edge.parameters.get("delay", 0.001))
            nengo.Connection(source, target, transform=weight, synapse=delay)

        incoming_nodes = {edge.target_node_id for edge in request.graph.edges}
        for node_id, ensemble in ensembles.items():
            if node_id not in incoming_nodes:
                nengo.Connection(nengo.Node(0.5), ensemble)

    return model, ensembles, spike_probes, voltage_probes


def _normalize_probe_data(
    probe_data: np.ndarray[Any, Any],
    neuron_count: int,
) -> np.ndarray[Any, Any]:
    """Ensure probe data is always a 2D array."""
    if len(probe_data.shape) < MIN_PROBE_DATA_DIMENSIONS:
        return np.zeros((0, neuron_count))
    return probe_data


def _build_results(
    sim: nengo.Simulator,
    request: PreviewRequest,
    ensembles: dict[str, nengo.Ensemble],
    spike_probes: dict[str, nengo.Probe],
    voltage_probes: dict[str, nengo.Probe],
) -> PreviewPayload:
    """Convert simulator probe data into legacy and structured preview payloads."""
    results: dict[str, Any] = {}
    trange = sim.trange()
    spike_events: list[PreviewSpikeEvent] = []
    playback_nodes: list[PreviewNodePlayback] = []
    edge_specs = [
        (
            edge.source_node_id,
            edge.target_node_id,
            float(edge.parameters.get("weight", 1.0)),
            float(edge.parameters.get("delay", 0.001)) * 1000.0,
        )
        for edge in request.graph.edges
    ]

    for node_id, ensemble in ensembles.items():
        spike_data = _normalize_probe_data(
            sim.data[spike_probes[node_id]], ensemble.n_neurons
        )
        neuron_spikes = []
        spike_trains: dict[str, list[float]] = {}
        for index in range(spike_data.shape[1]):
            spike_indices = np.where(spike_data[:, index] > 0)[0]
            spike_times = trange[spike_indices].tolist() if len(trange) > 0 else []
            neuron_spikes.append(spike_times)
            neuron_id = f"{node_id}:{index}"
            spike_trains[neuron_id] = [
                round(float(time_s) * 1000.0, 4) for time_s in spike_times
            ]
            for spike_time_ms in spike_trains[neuron_id]:
                spike_events.append(
                    PreviewSpikeEvent(
                        node_id=node_id,
                        neuron_id=neuron_id,
                        neuron_index=index,
                        time_ms=spike_time_ms,
                    ),
                )

        voltage_data = _normalize_probe_data(
            sim.data[voltage_probes[node_id]], ensemble.n_neurons
        )
        voltage_traces = np.round(
            voltage_data[:, :MAX_VOLTAGE_NEURONS_PREVIEW].T, 4
        ).tolist()
        voltage_trace_map = {
            f"{node_id}:{index}": trace for index, trace in enumerate(voltage_traces)
        }

        results[node_id] = {
            "spikes": neuron_spikes,
            "voltage": voltage_traces,
        }
        playback_nodes.append(
            PreviewNodePlayback(
                node_id=node_id,
                spike_trains=spike_trains,
                voltage_traces=voltage_trace_map,
                spike_count=sum(len(times) for times in spike_trains.values()),
            ),
        )

    edge_events: list[PreviewEdgeEvent] = []
    for source_node_id, target_node_id, weight, delay_ms in edge_specs:
        for spike_event in spike_events:
            if spike_event.node_id != source_node_id:
                continue
            edge_events.append(
                PreviewEdgeEvent(
                    source_node_id=source_node_id,
                    target_node_id=target_node_id,
                    weight=weight,
                    delay_ms=round(delay_ms, 4),
                    time_ms=round(spike_event.time_ms + delay_ms, 4),
                ),
            )

    total_neuron_count = sum(ensemble.n_neurons for ensemble in ensembles.values())
    bulk_spike_frame = None
    if should_use_bulk_frame(total_neuron_count):
        bulk_spike_frame = build_bulk_spike_frame(
            playback_nodes, total_neuron_count, request.duration_ms
        )

    playback = PreviewPlayback(
        duration_ms=round(request.duration_ms, 4),
        sample_count=len(trange),
        nodes=playback_nodes,
        spike_events=sorted(spike_events, key=lambda event: event.time_ms),
        edge_events=sorted(edge_events, key=lambda event: event.time_ms),
        bulk_spike_frame=bulk_spike_frame,
        summary=PreviewPlaybackSummary(
            total_spikes=len(spike_events),
            active_node_count=sum(1 for node in playback_nodes if node.spike_count > 0),
            edge_event_count=len(edge_events),
        ),
    )

    return PreviewPayload(results=results, playback=playback)


def run_preview_sync(request: PreviewRequest, job_id: str) -> None:
    """Execute a preview job for a previously queued job id."""
    job_store.update_job_status(job_id, SimulationStatus.RUNNING)
    try:
        job = job_store.get_job(job_id)
        response = run_preview(
            request,
            job_id=job_id,
            backend_support=getattr(job, "backend_support", None),
            generator_fidelity=getattr(job, "generator_fidelity", None),
        )
        match response.status:
            case SimulationStatus.CANCELLED:
                # Job was cancelled mid-run — do not overwrite results.
                return
            case SimulationStatus.FAILED:
                job_store.update_job_error(job_id, response.error or "Preview failed")
                return
            case _:
                pass
    except Exception as exc:
        job_store.update_job_error(job_id, str(exc))
        return

    job_store.update_job_results(
        job_id,
        response.results,
        playback=response.playback,
        metrics=response.metrics,
        backend_support=response.backend_support,
        generator_fidelity=response.generator_fidelity,
    )


def run_preview(
    request: PreviewRequest,
    job_id: str | None = None,
    progress_callback: Any = None,
    backend_support: Any = None,
    generator_fidelity: Any = None,
) -> PreviewResponse:
    """Run a short simulation for real-time preview using Nengo.

    Constructs a Nengo network from the CanvasGraph, runs it,
    and returns spike data, voltage traces, and timing metrics.

    Args:
        request (PreviewRequest): The preview request including graph and duration.
        job_id (str | None): Optional job ID if this is part of an async job.
        progress_callback (Callable | None): Optional callback to receive partial results.
        backend_support (Any): Optional precomputed backend support metadata for this graph.
        generator_fidelity (Any): Optional precomputed generator fidelity metadata.

    Returns:
        PreviewResponse: Initial job response.
    """
    logger.info(
        "Starting preview simulation - nodes=%d edges=%d duration_ms=%d",
        len(request.graph.nodes),
        len(request.graph.edges),
        request.duration_ms,
    )
    start_time = time.time()

    support = backend_support
    fidelity = generator_fidelity
    if support is None:
        support, fidelity = assess_preview_support(request.graph)

    if support.verdict == "unsupported":
        return PreviewResponse(
            job_id=job_id,
            status=SimulationStatus.FAILED,
            error="Preview is unsupported for the selected backend.",
            results={},
            playback=None,
            backend_support=support,
            generator_fidelity=fidelity,
        )

    use_neurocnl_generator = (
        support.verdict == "faithful"
        and can_use_neurocnl_generator(request.graph)
        and not requires_local_faithful_preview(request.graph)
    )

    model: nengo.Network
    ensembles: dict[str, nengo.Ensemble]
    spike_probes: dict[str, nengo.Probe]
    voltage_probes: dict[str, nengo.Probe]

    if use_neurocnl_generator:
        logger.info("Using neurocnl generator for supported graph topology.")
        model, ensembles, spike_probes, voltage_probes = generate_neurocnl_model(
            request.graph
        )
    else:
        if support.verdict == "faithful":
            logger.info(
                "Using NeuroSim local preview model builder for faithful population-specific preview execution.",
            )
        else:
            logger.info(
                "Using NeuroSim local preview model builder for approximate or unsupported fidelity.",
            )
        model, ensembles, spike_probes, voltage_probes = _build_preview_model(request)

    duration_s = request.duration_ms / 1000.0
    sim_execution_time_ms = 0.0
    results: dict[str, Any] = {}
    playback: PreviewPlayback | None = None

    ensure_nengo_runtime_cache()

    with nengo.Simulator(model, progress_bar=False, seed=42) as sim:
        chunk_size = 0.1  # 100ms chunks for streaming
        remaining = duration_s

        while remaining > 0:
            if job_id:
                job = job_store.get_job(job_id)
                if job and job.cancelled:
                    logger.info("Preview job %s cancelled.", job_id)
                    return PreviewResponse(
                        job_id=job_id,
                        status=SimulationStatus.CANCELLED,
                        results=results,
                        playback=playback,
                    )

            run_time = min(chunk_size, remaining)
            sim.run(run_time)
            remaining -= run_time

            sim_execution_time_ms += run_time * 1000.0

            # Get partial results
            payload = _build_results(
                sim,
                request,
                ensembles,
                spike_probes,
                voltage_probes,
            )
            results = payload.results
            playback = payload.playback
            if progress_callback:
                progress_callback(
                    payload,
                    current_time_ms=round(sim_execution_time_ms, 4),
                )

    end_time = time.time()
    wall_clock_ms = (end_time - start_time) * 1000.0
    overhead_time_ms = wall_clock_ms - sim_execution_time_ms

    out_job_id = job_id or str(uuid.uuid4())

    logger.info(
        "Preview simulation completed - wall_clock_ms=%.2f sim_execution_ms=%.2f setup_overhead_ms=%.2f",
        wall_clock_ms,
        sim_execution_time_ms,
        overhead_time_ms,
    )

    return PreviewResponse(
        job_id=out_job_id,
        status=SimulationStatus.COMPLETED,
        results=results,
        playback=playback,
        metrics={
            "simulation_time_ms": wall_clock_ms,
            "n_neurons": sum(ensemble.n_neurons for ensemble in ensembles.values()),
            "n_connections": len(request.graph.edges),
        },
        backend_support=support,
        generator_fidelity=fidelity,
    )
