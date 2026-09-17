"""Generic training API routes."""

import asyncio
import base64
import io
import json
import zipfile
from collections.abc import AsyncIterator
from typing import Annotated

import numpy as np
from fastapi import APIRouter, HTTPException, Query, Request, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, TypeAdapter

from backend.app.middleware.rate_limit import limiter
from backend.app.schemas.jobs import JobComplete, JobFailed, JobState
from backend.app.services.neuron_correlation import (
    DEFAULT_CLUSTER_THRESHOLD,
    DEFAULT_MAX_LINKS,
    DEFAULT_MAX_NEURONS,
    DEFAULT_MIN_SAMPLES,
    available_activity_layers,
    compute_neuron_correlation,
    load_layer_spikes,
)
from backend.app.services.progress_bus import progress_bus

router = APIRouter()


@router.get("/training/jobs/{job_id}", response_model=JobState)
@limiter.limit("60/minute")
async def get_training_job(
    request: Request, response: Response, job_id: str
) -> JobState:
    from backend.app.services.job_store import job_store

    job = await job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")
    return TypeAdapter(JobState).validate_python(job)


def _resolve_activity_b64(
    metadata: dict, epoch: int | None
) -> tuple[str | None, list[int]]:
    """Look up captured activity for *epoch* in job *metadata*.

    Supports the current per-epoch map (``activity_npy_b64_by_epoch``,
    written by `kernel_runner`'s epoch-aware `_maybe_capture_activity`) and
    falls back to the legacy single-blob field (``activity_npy_b64``) for
    jobs completed before per-epoch capture existed.

    When *epoch* is ``None``, returns the latest (highest-numbered) captured
    epoch — this is what every caller that doesn't pass ``epoch`` got before
    per-epoch capture existed, so omitting it keeps existing callers working
    unchanged.

    Returns ``(b64_or_none, sorted_available_epochs)``; the epoch list lets
    the caller report which epochs *were* captured when the requested one
    wasn't.
    """
    by_epoch = metadata.get("activity_npy_b64_by_epoch")
    if isinstance(by_epoch, dict) and by_epoch:
        parsed: dict[int, str] = {}
        for key, value in by_epoch.items():
            try:
                parsed[int(key)] = value
            except (TypeError, ValueError):
                continue
        available = sorted(parsed)
        if not available:
            return None, []
        if epoch is None:
            return parsed[available[-1]], available
        return parsed.get(epoch), available

    legacy = metadata.get("activity_npy_b64")
    if isinstance(legacy, str) and legacy:
        return legacy, []
    return None, []


@router.get("/training/jobs/{job_id}/activity.npy")
@limiter.limit("30/minute")
async def get_activity_npy(
    request: Request, response: Response, job_id: str, epoch: int | None = None
) -> Response:
    """Return the captured activity zip for *job_id*.

    ``epoch`` (optional query param) selects a specific captured epoch; when
    omitted, the latest captured epoch is returned (matching the pre-epoch-
    scrubber behaviour). If ``epoch`` is given but wasn't captured, responds
    404 with the list of epochs that *were* captured so the frontend can
    snap the scrubber to a valid value.
    """
    from backend.app.services.job_store import job_store

    job_data = await job_store.get(job_id)
    if job_data is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")

    job: JobState = TypeAdapter(JobState).validate_python(job_data)
    if not isinstance(job, JobComplete):
        raise HTTPException(status_code=400, detail="Job not complete")

    result = getattr(job, "result", None)
    if not isinstance(result, dict) or "metadata" not in result:
        raise HTTPException(status_code=404, detail="No metadata found")

    b64_str, available_epochs = _resolve_activity_b64(result["metadata"], epoch)
    if not b64_str:
        if epoch is not None and available_epochs:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"No activity captured for epoch {epoch} on this job. "
                    f"Captured epochs: {available_epochs}"
                ),
                headers={
                    "X-Available-Epochs": ",".join(str(e) for e in available_epochs)
                },
            )
        raise HTTPException(
            status_code=404, detail="No activity.npy found for this job"
        )

    binary_data = base64.b64decode(b64_str)
    served_epoch = (
        epoch
        if epoch is not None
        else (available_epochs[-1] if available_epochs else None)
    )
    headers = {
        "Content-Disposition": f'attachment; filename="activity_{job_id}.zip"',
        "X-Available-Epochs": ",".join(str(e) for e in available_epochs),
    }
    if served_epoch is not None:
        headers["X-Served-Epoch"] = str(served_epoch)
    return Response(
        content=binary_data,
        media_type="application/zip",
        headers=headers,
    )


# Keys accepted by the visualization image endpoint. Fixed allowlist so the
# endpoint cannot be used to read arbitrary job metadata.
_ALLOWED_VIZ_IMAGE_KEYS = frozenset({"weight_map", "attribution_map", "weight_data"})


@router.get("/training/jobs/{job_id}/visualization_image/{image_key}")
@limiter.limit("60/minute")
async def get_visualization_image(
    request: Request, response: Response, job_id: str, image_key: str
) -> Response:
    """Return a visualization PNG image captured during notebook execution.

    *image_key* must be one of ``weight_map`` or ``attribution_map``. The
    image is captured by the kernel runner after the notebook cell prints
    ``weight_map: <path>`` or ``attribution_map: <path>`` to stdout.
    """
    from backend.app.services.job_store import job_store

    if image_key not in _ALLOWED_VIZ_IMAGE_KEYS:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Unknown image key {image_key!r}. Allowed: {sorted(_ALLOWED_VIZ_IMAGE_KEYS)}"
            ),
        )

    job_data = await job_store.get(job_id)
    if job_data is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")

    job: JobState = TypeAdapter(JobState).validate_python(job_data)
    if not isinstance(job, JobComplete):
        raise HTTPException(status_code=400, detail="Job not complete")

    result = getattr(job, "result", None)
    if not isinstance(result, dict) or "metadata" not in result:
        raise HTTPException(
            status_code=404,
            detail=f"No {image_key} image found for this job.",
        )

    viz = result["metadata"].get("visualization_images", {})
    b64_str = viz.get(image_key)
    if not isinstance(b64_str, str) or not b64_str:
        raise HTTPException(
            status_code=404,
            detail=(
                f"No {image_key} image was captured for this job. "
                "Add the corresponding visualizer node to the Train canvas and re-run."
            ),
        )

    binary_data = base64.b64decode(b64_str)
    return Response(
        content=binary_data,
        media_type="image/png",
        headers={
            "Content-Disposition": f'inline; filename="{image_key}_{job_id}.png"',
            "Cache-Control": "public, max-age=3600",
        },
    )


# 15 s when nothing is happening. Keeps proxies and clients from timing the
# connection out, costs nothing to send, and is ignored by EventSource consumers.
_SSE_HEARTBEAT_INTERVAL_S = 15.0


@router.get("/training/jobs/{job_id}/events")
async def stream_training_events(request: Request, job_id: str) -> StreamingResponse:
    """Server-Sent Events stream of live training progress for *job_id*.

    Emits one ``data: <json>\\n\\n`` message per event published by the running
    adapter. Events have a ``type`` field — typically ``epoch``, ``phase``,
    ``done``, or ``failed``. The stream closes naturally after the adapter
    finishes and the bus is closed; clients should also disconnect when they
    see a terminal ``done``/``failed`` payload.
    """
    from backend.app.services.job_store import job_store

    job = await job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")

    queue = progress_bus.subscribe(job_id)

    async def _event_stream() -> AsyncIterator[str]:
        # Replay durably-logged history first — covers both a client that
        # reconnects mid-run (e.g. a different device/GUI) and one that
        # subscribes after the job already finished.
        history = await job_store.list_job_events(job_id)
        if history:
            for event in history:
                yield f"data: {json.dumps({**event, 'replayed': True})}\n\n"
            parsed_job: JobState = TypeAdapter(JobState).validate_python(
                await job_store.get(job_id)
            )
            if isinstance(parsed_job, JobComplete | JobFailed):
                progress_bus.unsubscribe(job_id, queue)
                return
        else:
            # Pre-migration job with no logged events: fall back to
            # synthesizing the terminal event from the job row so an
            # already-finished job doesn't stream silence.
            parsed_job = TypeAdapter(JobState).validate_python(job)
            match parsed_job:
                case JobComplete():
                    terminal = {
                        "type": "done",
                        "status": parsed_job.status,
                        "result": parsed_job.result,
                        "error": None,
                    }
                    yield f"data: {json.dumps(terminal)}\n\n"
                    progress_bus.unsubscribe(job_id, queue)
                    return
                case JobFailed():
                    terminal = {
                        "type": "failed",
                        "status": parsed_job.status,
                        "result": None,
                        "error": parsed_job.error,
                    }
                    yield f"data: {json.dumps(terminal)}\n\n"
                    progress_bus.unsubscribe(job_id, queue)
                    return
                case _:
                    pass

        try:
            while True:
                if await request.is_disconnected():
                    break
                try:
                    event = await asyncio.wait_for(
                        queue.get(),
                        timeout=_SSE_HEARTBEAT_INTERVAL_S,
                    )
                except TimeoutError:
                    # Heartbeat comment — keeps the TCP connection alive without
                    # triggering EventSource onmessage.
                    yield ": keepalive\n\n"
                    continue
                if progress_bus.is_end_sentinel(event):
                    break
                yield f"data: {json.dumps(event)}\n\n"
        finally:
            progress_bus.unsubscribe(job_id, queue)

    return StreamingResponse(
        _event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",  # disable nginx buffering if present
        },
    )


# ── Activity comparison ────────────────────────────────────────────────────


class _JobRef(BaseModel):
    job_id: str
    label: str  # display name, e.g. "snnTorch", "Nengo"
    service: str = "training"  # "training" (SQLite job store) | "neurosim" (in-memory)


class _ActivityCompareRequest(BaseModel):
    jobs: list[_JobRef]
    layer: str = "hidden_spikes"  # filename stem inside the activity zip


def _load_activity_vector(b64_str: str, layer: str) -> np.ndarray | None:
    """Decode activity zip, load the requested layer, and return a 1-D mean vector."""
    try:
        zip_bytes = base64.b64decode(b64_str)
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
            names = zf.namelist()
            target = f"{layer}.npy"
            match = next((n for n in names if n == target or n.startswith(layer)), None)
            if match is None:
                return None
            arr = np.load(io.BytesIO(zf.read(match)))
            # Collapse all dims except the last (neuron dim) → (N,) mean vector
            reduce_axes = tuple(range(arr.ndim - 1))
            return (
                arr.mean(axis=reduce_axes).astype(np.float32)
                if reduce_axes
                else arr.astype(np.float32)
            )
    except Exception:
        return None


def _pick_hidden_node(results: dict) -> dict | None:
    """Return the results entry with the most spikes — proxy for hidden layer."""
    best = max(
        results.items(),
        key=lambda kv: len(kv[1].get("spikes") or []),
        default=None,
    )
    return best[1] if best else None


def _load_neurosim_activity_vector(job_id: str, layer: str) -> np.ndarray | None:
    """Extract a 1-D activity vector from a neurosim (Nengo preview) job.

    Neurosim stores spike times as a flat list of floats (seconds) per node.
    We histogram them into 100 bins to get a comparable rate-proxy vector.
    Same-process import — neurosim routers are mounted directly into this app.
    """
    try:
        # ponytail: direct import — same process, no HTTP needed
        from neurosim.app.services.job_store import job_store as neurosim_store
    except ImportError:
        return None

    job = neurosim_store.get_job(job_id)
    if job is None or not job.results:
        return None

    node_data = job.results.get(layer) or _pick_hidden_node(job.results)
    if node_data is None:
        return None

    spikes_raw = node_data.get("spikes")
    if not spikes_raw:
        return None

    times = np.asarray(spikes_raw, dtype=np.float32).ravel()
    if times.size == 0:
        return np.zeros(100, dtype=np.float32)
    vec, _ = np.histogram(times, bins=100)
    return vec.astype(np.float32)


@router.post("/activity/compare")
@limiter.limit("10/minute")
async def compare_activity(
    request: Request, response: Response, body: _ActivityCompareRequest
) -> dict:
    """Compute pairwise cosine similarity between hidden-layer spike activity arrays.

    Supports two job sources via ``_JobRef.service``:
    - ``"training"`` (default): SQLite-backed backend job store; expects ``activity_npy_b64``
      in job result metadata (produced by the snnTorch adapter).
    - ``"neurosim"``: in-memory neurosim job store (Nengo canvas preview simulations);
      spike times are histogrammed into a 100-bin rate-proxy vector.

    Returns ``{frameworks: [...], matrix: [[...], ...]}``.
    """
    from backend.app.services.job_store import job_store

    vectors: dict[str, np.ndarray] = {}
    for job_ref in body.jobs:
        if job_ref.service == "neurosim":
            vec = _load_neurosim_activity_vector(job_ref.job_id, body.layer)
            if vec is not None:
                vectors[job_ref.label] = vec
            continue

        # Training job store path (default)
        job_data = await job_store.get(job_ref.job_id)
        if job_data is None:
            continue
        parsed: JobState = TypeAdapter(JobState).validate_python(job_data)
        if not isinstance(parsed, JobComplete):
            continue
        result = getattr(parsed, "result", None)
        if not isinstance(result, dict) or "metadata" not in result:
            continue
        # Latest captured epoch — comparison isn't epoch-scoped (yet), so
        # this matches the pre-per-epoch-capture behaviour of always using
        # whatever the one captured export was.
        b64_str, _available_epochs = _resolve_activity_b64(result["metadata"], None)
        if not b64_str:
            continue
        vec = _load_activity_vector(b64_str, body.layer)
        if vec is not None:
            vectors[job_ref.label] = vec

    if len(vectors) < 2:
        raise HTTPException(
            status_code=404,
            detail="Fewer than 2 jobs have activity data for the requested layer",
        )

    labels = list(vectors)
    vecs = np.stack([vectors[label] for label in labels])
    norms = np.linalg.norm(vecs, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)  # avoid division by zero
    normed = vecs / norms
    mat = (normed @ normed.T).tolist()

    return {"frameworks": labels, "matrix": mat}


# ── Per-neuron correlation ("fire together, wire together", true measure) ──


class _NeuronLinkResponse(BaseModel):
    source: int
    target: int
    correlation: float
    co_active_samples: int


class _NeuronCorrelationResponse(BaseModel):
    """Per-neuron spike-train correlation for one captured layer.

    Unlike the client-side co-activation proxy (which correlates whole
    layers' aggregate rates), every link here is between two individual
    neurons in the same layer, computed over their raw ``(T, N)`` spike
    trains. ``neuron_indices`` maps an analyzed column back to its position
    in the original spike matrix.
    """

    job_id: str
    layer: str
    epoch: int | None
    neuron_count: int
    analyzed_neuron_count: int
    time_samples: int
    truncated: bool
    threshold: float
    min_samples: int
    total_pairs: int
    links: list[_NeuronLinkResponse]
    clusters: list[list[int]]
    neuron_indices: list[int]
    spike_counts: list[int]


@router.get(
    "/training/jobs/{job_id}/neuron_correlation",
    response_model=_NeuronCorrelationResponse,
)
@limiter.limit("20/minute")
async def get_neuron_correlation(
    request: Request,
    response: Response,
    job_id: str,
    layer: Annotated[str, Query(min_length=1)] = "hidden_spikes",
    epoch: Annotated[int | None, Query(ge=0)] = None,
    threshold: Annotated[float, Query(ge=-1.0, le=1.0)] = DEFAULT_CLUSTER_THRESHOLD,
    min_samples: Annotated[int, Query(ge=1)] = DEFAULT_MIN_SAMPLES,
    max_neurons: Annotated[int, Query(ge=2, le=4096)] = DEFAULT_MAX_NEURONS,
    max_links: Annotated[int, Query(ge=0, le=100_000)] = DEFAULT_MAX_LINKS,
) -> _NeuronCorrelationResponse:
    """Compute real per-neuron spike-train correlation for a completed job.

    Reads the same captured ``activity_npy_b64`` zip the activity download and
    comparison endpoints use, loads one layer's ``(T, N)`` spike matrix, and
    correlates each neuron pair over time. This is the finer-grained Hebbian
    measure the CEL-138 proposal flagged as a backend follow-up; the v1
    network view still uses the layer-level client-side proxy.

    ``layer`` is the activity entry stem (``{layer}_spikes.npy`` in the zip);
    when an epoch is not given, the latest captured epoch is used. Wide layers
    are capped to their ``max_neurons`` most active neurons — ``truncated``
    reports when that happened.
    """
    from backend.app.services.job_store import job_store

    job_data = await job_store.get(job_id)
    if job_data is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")

    job: JobState = TypeAdapter(JobState).validate_python(job_data)
    if not isinstance(job, JobComplete):
        raise HTTPException(status_code=400, detail="Job not complete")

    result = getattr(job, "result", None)
    if not isinstance(result, dict) or "metadata" not in result:
        raise HTTPException(status_code=404, detail="No metadata found")

    b64_str, available_epochs = _resolve_activity_b64(result["metadata"], epoch)
    if not b64_str:
        if epoch is not None and available_epochs:
            raise HTTPException(
                status_code=404,
                detail=(
                    f"No activity captured for epoch {epoch} on this job. "
                    f"Captured epochs: {available_epochs}"
                ),
            )
        raise HTTPException(
            status_code=404, detail="No activity.npy found for this job"
        )

    spikes = load_layer_spikes(b64_str, layer)
    if spikes is None:
        layers = available_activity_layers(b64_str)
        detail = f"No layer {layer!r} in this job's activity."
        if layers:
            detail += f" Available layers: {layers}"
        raise HTTPException(status_code=404, detail=detail)

    computation = await asyncio.to_thread(
        compute_neuron_correlation,
        spikes,
        min_samples=min_samples,
        threshold=threshold,
        max_neurons=max_neurons,
        max_links=max_links,
    )
    served_epoch = (
        epoch
        if epoch is not None
        else (available_epochs[-1] if available_epochs else None)
    )

    return _NeuronCorrelationResponse(
        job_id=job_id,
        layer=layer,
        epoch=served_epoch,
        neuron_count=computation.neuron_count,
        analyzed_neuron_count=computation.analyzed_neuron_count,
        time_samples=computation.time_samples,
        truncated=computation.truncated,
        threshold=computation.threshold,
        min_samples=computation.min_samples,
        total_pairs=computation.total_pairs,
        links=[
            _NeuronLinkResponse(
                source=link.source,
                target=link.target,
                correlation=link.correlation,
                co_active_samples=link.co_active_samples,
            )
            for link in computation.links
        ],
        clusters=computation.clusters,
        neuron_indices=computation.neuron_indices,
        spike_counts=computation.spike_counts,
    )
