"""POST /api/notebook/run — queue a Jupyter notebook for execution."""

from __future__ import annotations

import asyncio
import json
import logging
import shutil
from collections.abc import Callable
from pathlib import Path

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from backend.app.routers.notebook import JUPYTER_WORKER_URL, NOTEBOOK_DIR
from backend.app.schemas.jobs import JobQueued
from backend.app.services.job_store import job_store
from backend.app.services.notebook_paths import resolve_notebook_path
from backend.app.services.progress_bus import progress_bus

router = APIRouter()
_logger = logging.getLogger(__name__)

# Tracks in-flight notebook execution jobs so a cancel request can reach both
# the local asyncio task and (when execution is delegated to the Jupyter
# worker) the worker-side job that actually owns the kernel.
_running_tasks: dict[str, asyncio.Task] = {}
_worker_job_ids: dict[str, str] = {}

_WORKER_POLL_INTERVAL_SECONDS = 2
# Stall timeout, not a total-duration budget: reset every time new worker
# job output is observed (see _execute_notebook_via_worker below). A job can
# run arbitrarily long — e.g. a multi-hundred-epoch training loop packed
# into a single notebook cell — as long as it keeps producing output; only
# a job with no new output at all for this many seconds trips it.
# Must stay <= nmtk_env_manager/handlers.py's _CELL_EXECUTION_TIMEOUT_SECONDS
# (the per-cell stall ceiling inside the Jupyter worker), which resets on
# the same "new activity" signal.
# Must stay <= handlers._CELL_EXECUTION_TIMEOUT_SECONDS (jupyter worker stall).
_WORKER_EXECUTION_TIMEOUT_SECONDS = 3 * 60 * 60


class NotebookRunRequest(BaseModel):
    notebook_path: str
    platform: str = "snntorch_sim"
    kernel_name: str = ""


def _resolve_notebook_kernel_name(path: Path, requested_kernel_name: str) -> str:
    requested = requested_kernel_name.strip()
    if requested:
        return requested
    try:
        notebook = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return "python3"
    kernelspec = notebook.get("metadata", {}).get("kernelspec", {})
    if isinstance(kernelspec, dict):
        name = kernelspec.get("name", "")
        if isinstance(name, str) and name.strip():
            return name.strip()
    return "python3"


def _maybe_publish(
    line: str,
    platform: str,
    publish: Callable[[dict], None],
) -> None:
    """Parse a stdout/stderr line for __nmtk_progress__ JSON and publish an epoch event."""
    stripped = line.strip()
    if not stripped:
        return
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return
    if not isinstance(payload, dict) or not payload.get("__nmtk_progress__"):
        return
    event = {
        "type": "epoch",
        "epoch": int(payload["epoch"]),
        "total_epochs": int(payload.get("total_epochs", 0)) or None,
        "loss": float(payload.get("loss", 0.0)),
        "accuracy": (float(payload["accuracy"]) if payload.get("accuracy") is not None else None),
        "layer_spike_rates": payload.get("layer_spike_rates") or {},
        "platform": platform,
        "phase": payload.get("phase", "train"),
    }
    publish(event)


def _maybe_capture_activity(line: str) -> tuple[int, str] | None:
    """Parse a stdout/stderr line for the `__nmtk_activity__` marker emitted
    by `_nmtk_emit_activity` and return `(epoch, activity_npy_b64)`, or
    None. A separate marker (not mixed into `_maybe_publish`'s per-epoch
    payload) since this line carries a full per-neuron activity capture,
    not a small progress update.

    The notebook now emits one of these per captured epoch (epoch 1, the
    final epoch, and every Nth epoch in between — see
    `notebook._ACTIVITY_CAPTURE_CADENCE_EPOCHS`), so callers must accumulate
    by epoch rather than overwrite a single last-value slot."""
    stripped = line.strip()
    if not stripped:
        return None
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict) or not payload.get("__nmtk_activity__"):
        return None
    b64 = payload.get("activity_npy_b64")
    if not isinstance(b64, str) or not b64:
        return None
    try:
        epoch = int(payload.get("epoch"))
    except (TypeError, ValueError):
        return None
    return (epoch, b64)


# Prefixes printed by weight_visualizer and attribution_visualizer notebook cells.
# Each maps a marker prefix to the metadata key used to store its b64 payload.
_VISUALIZATION_IMAGE_PREFIXES: dict[str, str] = {
    "weight_map: ": "weight_map",
    "attribution_map: ": "attribution_map",
    "weight_data: ": "weight_data",
}


def _maybe_capture_image(line: str, notebook_dir: str) -> tuple[str, str] | None:
    """Parse a weight_map or attribution_map print line from a generated notebook cell.

    The notebook cell prints ``weight_map: <filename>`` or
    ``attribution_map: <filename>`` where *filename* is relative to the
    notebook's working directory (which is the Jupyter server's root for the
    workspace). This function fetches the PNG bytes via the Jupyter contents
    API and returns ``(metadata_key, base64_png)`` so callers can store the
    result in job metadata for later retrieval.

    Returns ``None`` when the line does not match, the file is unavailable,
    or the Jupyter contents API is not configured.
    """
    if not JUPYTER_WORKER_URL:
        return None
    stripped = line.strip()
    matched_key: str | None = None
    filename: str | None = None
    for prefix, key in _VISUALIZATION_IMAGE_PREFIXES.items():
        if stripped.startswith(prefix):
            matched_key = key
            filename = stripped[len(prefix) :].strip()
            break
    if matched_key is None or not filename:
        return None
    # Build the content-API path relative to the Jupyter root.
    rel_path = f"{notebook_dir.rstrip('/')}/{filename}" if notebook_dir else filename
    try:
        import httpx

        with httpx.Client(timeout=10.0) as client:
            resp = client.get(
                f"{JUPYTER_WORKER_URL}/api/contents/{rel_path}",
                params={"format": "base64", "content": "1"},
            )
            if resp.status_code != 200:
                _logger.warning(
                    "visualization_image_fetch_failed",
                    extra={"path": rel_path, "status": resp.status_code},
                )
                return None
            payload = resp.json()
            b64_content = payload.get("content")
            if not isinstance(b64_content, str) or not b64_content:
                return None
            # The contents API wraps base64 in newlines; strip them.
            return (matched_key, b64_content.replace("\n", ""))
    except Exception:  # noqa: BLE001
        _logger.debug("visualization_image_fetch_error", exc_info=True)
        return None


async def _execute_notebook(
    job_id: str,
    path: Path,
    platform: str,
    kernel_name: str,
    notebook_path: str | None = None,
) -> None:
    publisher = progress_bus.publisher_for(job_id)
    try:
        await job_store.set_running(job_id)
        _logger.info(
            "notebook_execution_start",
            extra={
                "job_id": job_id,
                "path": str(path),
                "platform": platform,
                "kernel_name": kernel_name,
            },
        )
        if JUPYTER_WORKER_URL:
            await _execute_notebook_via_worker(
                job_id,
                path,
                platform,
                kernel_name,
                notebook_path,
                publisher,
            )
            return

        if shutil.which("jupyter") is None:
            err = (
                "Notebook execution is unavailable because the backend cannot find "
                "`jupyter`. Start the Jupyter worker or install Jupyter in this "
                "backend environment, then retry."
            )
            _logger.error(
                "notebook_execution_unavailable",
                extra={"job_id": job_id, "error": err},
            )
            if publisher is not None:
                publisher({"type": "failed", "status": "failed", "error": err})
            await job_store.set_failed(job_id, error=err)
            return

        proc = await asyncio.create_subprocess_exec(
            "jupyter",
            "nbconvert",
            "--to",
            "notebook",
            "--execute",
            "--inplace",
            "--ExecutePreprocessor.kernel_name",
            kernel_name,
            str(path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )

        assert proc.stdout is not None
        activity_by_epoch: dict[int, str] = {}
        viz_images: dict[str, str] = {}
        while True:
            line_bytes = await proc.stdout.readline()
            if not line_bytes:
                break
            line = line_bytes.decode(errors="replace")
            if publisher is not None:
                _maybe_publish(line, platform, publisher)
            captured = _maybe_capture_activity(line)
            if captured is not None:
                epoch, b64 = captured
                activity_by_epoch[epoch] = b64
            # Notebook directory for local-subprocess runs is the parent of path.
            img_captured = _maybe_capture_image(
                line,
                str(path.parent.relative_to(NOTEBOOK_DIR)) if NOTEBOOK_DIR in path.parents else "",
            )
            if img_captured is not None:
                img_key, img_b64 = img_captured
                viz_images[img_key] = img_b64

        returncode = await proc.wait()
        if returncode != 0:
            err = f"Notebook execution failed (exit {returncode})"
            _logger.error(
                "notebook_execution_failed",
                extra={"job_id": job_id, "error": err},
            )
            if publisher is not None:
                publisher({"type": "failed", "status": "failed", "error": err})
            await job_store.set_failed(job_id, error=err)
        else:
            _logger.info(
                "notebook_execution_complete",
                extra={"job_id": job_id},
            )
            if publisher is not None:
                publisher({"type": "done", "status": "completed"})
            result: dict = {"notebook_path": str(path)}
            metadata: dict = {}
            if activity_by_epoch:
                metadata["activity_npy_b64_by_epoch"] = activity_by_epoch
            if viz_images:
                metadata["visualization_images"] = viz_images
            if metadata:
                result["metadata"] = metadata
            await job_store.set_complete(job_id, result=result)
    except OSError as exc:
        _logger.exception(
            "notebook_execution_error",
            extra={"job_id": job_id, "exc": str(exc)},
        )
        if publisher is not None:
            publisher({"type": "failed", "status": "failed", "error": str(exc)})
        await job_store.set_failed(job_id, error=str(exc))
    finally:
        progress_bus.close(job_id)
        _running_tasks.pop(job_id, None)
        _worker_job_ids.pop(job_id, None)


def _worker_notebook_path(path: Path, notebook_path: str | None) -> str:
    """Return the Jupyter-worker-relative path for a generated notebook."""
    raw = (notebook_path or "").strip()
    if raw and not Path(raw).is_absolute():
        return raw
    try:
        return str(path.resolve().relative_to(NOTEBOOK_DIR.resolve()))
    except ValueError:
        return path.name


async def _stop_conflicting_manual_sessions(
    client: httpx.AsyncClient, base_url: str, worker_path: str
) -> None:
    """Stop any manually-started Jupyter session already open against
    *worker_path* (e.g. the user has it open in the embedded JupyterLab view)
    before a Play-triggered run starts its own kernel for the same file.

    Without this, the two kernels resource-contend (e.g. concurrent
    CUDA/framework init in the same container) and the Play-triggered kernel
    can produce zero output for the entire run, eventually failing only once
    the 30-minute stall timeout below trips — silently, with no indication
    the real cause was a leftover manual session. Best-effort: a failure here
    must not block the run itself.
    """
    try:
        resp = await client.get(f"{base_url}/api/sessions")
        resp.raise_for_status()
        sessions = resp.json()
    except httpx.HTTPError:
        return
    for session in sessions:
        if session.get("path") != worker_path:
            continue
        session_id = session.get("id")
        if not session_id:
            continue
        try:
            await client.delete(f"{base_url}/api/sessions/{session_id}")
        except httpx.HTTPError:
            pass


async def _execute_notebook_via_worker(
    job_id: str,
    path: Path,
    platform: str,
    kernel_name: str,
    notebook_path: str | None,
    publisher: Callable[[dict], None] | None,
) -> None:
    worker_path = _worker_notebook_path(path, notebook_path)
    base_url = JUPYTER_WORKER_URL.rstrip("/")
    submit_url = f"{base_url}/nmtk-envs/api/executions"
    seen_output = 0

    async with httpx.AsyncClient(timeout=30.0) as client:
        await _stop_conflicting_manual_sessions(client, base_url, worker_path)
        submit_resp = await client.post(
            submit_url,
            json={"notebookPath": worker_path, "kernelName": kernel_name},
        )
        submit_resp.raise_for_status()
        worker_job_id = str(submit_resp.json()["jobId"])
        _worker_job_ids[job_id] = worker_job_id
        job_url = f"{base_url}/nmtk-envs/api/jobs/{worker_job_id}"

        deadline = asyncio.get_running_loop().time() + _WORKER_EXECUTION_TIMEOUT_SECONDS
        activity_by_epoch: dict[int, str] = {}
        viz_images: dict[str, str] = {}
        while True:
            poll_resp = await client.get(job_url)
            poll_resp.raise_for_status()
            worker_job = poll_resp.json()

            output = worker_job.get("output") or []
            if len(output) > seen_output:
                deadline = asyncio.get_running_loop().time() + _WORKER_EXECUTION_TIMEOUT_SECONDS
            for line in output[seen_output:]:
                if publisher is not None:
                    _maybe_publish(str(line), platform, publisher)
                captured = _maybe_capture_activity(str(line))
                if captured is not None:
                    epoch, b64 = captured
                    activity_by_epoch[epoch] = b64
                # Worker notebook dir is the directory part of worker_path.
                notebook_dir = str(Path(worker_path).parent)
                img_captured = _maybe_capture_image(str(line), notebook_dir)
                if img_captured is not None:
                    img_key, img_b64 = img_captured
                    viz_images[img_key] = img_b64
            seen_output = len(output)

            state = str(worker_job.get("state", ""))
            if state == "ready":
                _logger.info(
                    "notebook_execution_complete",
                    extra={"job_id": job_id, "worker_job_id": worker_job_id},
                )
                if publisher is not None:
                    publisher({"type": "done", "status": "completed"})
                result = worker_job.get("result") or {"notebook_path": worker_path}
                metadata: dict = {**(result.get("metadata") or {})}
                if activity_by_epoch:
                    metadata["activity_npy_b64_by_epoch"] = activity_by_epoch
                if viz_images:
                    metadata["visualization_images"] = viz_images
                if metadata:
                    result = {**result, "metadata": metadata}
                await job_store.set_complete(job_id, result=result)
                return

            if state == "error":
                err = str(worker_job.get("error") or "Notebook execution failed.")
                _logger.error(
                    "notebook_execution_failed",
                    extra={
                        "job_id": job_id,
                        "worker_job_id": worker_job_id,
                        "error": err,
                    },
                )
                if publisher is not None:
                    publisher({"type": "failed", "status": "failed", "error": err})
                await job_store.set_failed(job_id, error=err)
                return

            if asyncio.get_running_loop().time() >= deadline:
                err = "Notebook execution timed out in the Jupyter worker."
                _logger.error(
                    "notebook_execution_timeout",
                    extra={"job_id": job_id, "worker_job_id": worker_job_id},
                )
                if publisher is not None:
                    publisher({"type": "failed", "status": "failed", "error": err})
                await job_store.set_failed(job_id, error=err)
                return

            await asyncio.sleep(_WORKER_POLL_INTERVAL_SECONDS)


@router.post("/notebook/run", response_model=JobQueued, status_code=202)
async def run_notebook(body: NotebookRunRequest) -> JobQueued:
    try:
        path = resolve_notebook_path(body.notebook_path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    kernel_name = _resolve_notebook_kernel_name(path, body.kernel_name)
    job_id = await job_store.create(platform=body.platform, notebook_path=body.notebook_path)
    task = asyncio.create_task(
        _execute_notebook(
            job_id,
            path,
            body.platform,
            kernel_name,
            notebook_path=body.notebook_path,
        )
    )
    _running_tasks[job_id] = task
    return JobQueued(job_id=job_id, request_id=None)


@router.get("/notebook/jobs/active")
async def list_active_notebook_jobs() -> list[dict]:
    """List queued/running notebook execution jobs — polled by the UI to show
    what's currently running on the server, regardless of which client/tab
    started it."""
    return await job_store.list_active_notebook_jobs()


@router.post("/notebook/jobs/{job_id}/cancel", status_code=204)
async def cancel_notebook_job(job_id: str) -> None:
    job = await job_store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job {job_id} not found")

    worker_job_id = _worker_job_ids.get(job_id)
    if worker_job_id is not None and JUPYTER_WORKER_URL:
        base_url = JUPYTER_WORKER_URL.rstrip("/")
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                await client.delete(f"{base_url}/nmtk-envs/api/jobs/{worker_job_id}")
        except httpx.HTTPError as exc:
            _logger.warning(
                "notebook_cancel_worker_unreachable",
                extra={
                    "job_id": job_id,
                    "worker_job_id": worker_job_id,
                    "exc": str(exc),
                },
            )

    task = _running_tasks.get(job_id)
    if task is not None:
        task.cancel()

    if job["status"] in ("queued", "running"):
        progress_bus.publisher_for(job_id)(
            {"type": "failed", "status": "failed", "error": "Cancelled by user"}
        )
        await job_store.set_failed(job_id, error="Cancelled by user")


@router.get("/notebook/sessions")
async def list_notebook_sessions() -> list[dict]:
    """List live Jupyter kernel sessions.

    Covers notebooks run manually inside the embedded JupyterLab UI (step 5),
    which — unlike jobs queued through /notebook/run — aren't tracked in
    job_store at all; Jupyter's own session API is the only source of truth
    for those.
    """
    if not JUPYTER_WORKER_URL:
        return []
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(f"{JUPYTER_WORKER_URL}/api/sessions")
        resp.raise_for_status()
        return resp.json()
    except httpx.HTTPError as exc:
        _logger.warning("notebook_sessions_unreachable", extra={"exc": str(exc)})
        return []


@router.delete("/notebook/sessions/{session_id}", status_code=204)
async def stop_notebook_session(session_id: str) -> None:
    """Shut down a manually-run JupyterLab kernel session (hard stop — any
    in-progress cell aborts and unsaved kernel state is lost)."""
    if not JUPYTER_WORKER_URL:
        raise HTTPException(status_code=503, detail="Jupyter worker is not configured.")
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.delete(f"{JUPYTER_WORKER_URL}/api/sessions/{session_id}")
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail=f"Jupyter Server not reachable: {exc}") from exc
    if resp.status_code == 404:
        raise HTTPException(status_code=404, detail=f"Session {session_id} not found")
    resp.raise_for_status()
