"""Service layer for generic training — mediates between routes and the adapter registry."""

from __future__ import annotations

from dataclasses import asdict, replace
from pathlib import Path
from typing import Any

import structlog

from backend.app.services.dataset_cache import dataset_cache
from backend.app.services.dataset_catalog import (
    FirebaseCatalogError,
    infer_dataset_format,
    load_dataset_catalog,
)
from backend.app.services.job_store import job_store
from backend.app.services.progress_bus import progress_bus
from backend.app.utils.cnl_errors import StructuredJobError
from neurocnl.training.factory import build_training_registry
from neurocnl.training_registry import (
    AdapterSelectionError,
    TrainingAdapterRegistry,
    TrainingRequest,
    TrainingResult,
)

logger = structlog.get_logger(__name__)


def _build_registry() -> TrainingAdapterRegistry:
    """Build the adapter registry with all registered adapters.

    Imports are lazy to avoid triggering heavy deps at module load time.
    """
    return build_training_registry()


# Module-level registry singleton (lazy-built)
_registry: TrainingAdapterRegistry | None = None


def _get_registry() -> TrainingAdapterRegistry:
    global _registry
    if _registry is None:
        _registry = _build_registry()
    return _registry


def _serialize_training_result(result: TrainingResult) -> dict[str, Any]:
    if result.status != "completed":
        message = result.error or (
            f"Training adapter {result.adapter_name!r} returned status {result.status!r}."
        )
        raise StructuredJobError(
            {
                "error": "training_failed",
                "messages": [message],
                "adapter_name": result.adapter_name,
                "training_mode": result.training_mode,
                "status": result.status,
            }
        )
    return asdict(result)


async def _resolve_dataset_payload(payload: dict[str, Any]) -> dict[str, Any]:
    resolved = dict(payload)
    if resolved.get("use_synthetic_fixture") is True:
        return resolved

    raw_dataset_id = resolved.get("dataset_id") or resolved.get("dataset")
    dataset_id = str(raw_dataset_id).strip() if raw_dataset_id is not None else ""

    dataset_path_value = resolved.get("dataset_path")
    dataset_path = str(dataset_path_value).strip() if dataset_path_value is not None else ""
    entry = None
    try:
        catalog = load_dataset_catalog()
        entry = catalog.get(dataset_id) if dataset_id else None
    except FirebaseCatalogError:
        if not dataset_path:
            raise

    if entry is not None:
        resolved["dataset_id"] = entry.id
        resolved["dataset"] = entry.id
        if not dataset_path:
            ready_path = await dataset_cache.get_ready_path(entry.id)
            if not ready_path:
                raise AdapterSelectionError(
                    f"Dataset '{entry.id}' is not downloaded on the server yet. "
                    "Select it in Setup, wait for the download to complete, then retry training."
                )
            dataset_path = ready_path
        resolved["dataset_path"] = dataset_path
        if entry.format and "dataset_format" not in resolved:
            resolved["dataset_format"] = entry.format
        if entry.loader_config and "dataset_loader_config" not in resolved:
            resolved["dataset_loader_config"] = entry.loader_config
    elif dataset_id:
        ready_path = await dataset_cache.get_ready_path(dataset_id)
        if ready_path:
            resolved["dataset_id"] = dataset_id
            resolved["dataset"] = dataset_id
            if not dataset_path:
                dataset_path = ready_path
            local_entry = await dataset_cache.get_entry_dict(dataset_id)
            if (
                local_entry is not None
                and local_entry.get("format")
                and "dataset_format" not in resolved
            ):
                resolved["dataset_format"] = local_entry["format"]

    if dataset_path:
        path = Path(dataset_path).expanduser()
        if not path.exists():
            raise AdapterSelectionError(
                f"Dataset path '{path}' does not exist on the backend. "
                "Re-download the dataset in Setup and try again."
            )
        resolved["dataset_path"] = str(path.resolve())
        if "dataset_format" not in resolved:
            inferred_format = infer_dataset_format(path.name)
            if inferred_format is not None:
                resolved["dataset_format"] = inferred_format

    return resolved


def _build_publisher_holder() -> dict[str, Any]:
    """Return a mutable holder so ``bind_job_id`` can hand the publisher (and
    the job_id itself) to the worker.

    ``submit`` calls ``bind_job_id`` between creating the job_id and launching
    the worker task, but ``fn`` is already captured by then. We use a one-slot
    dict as the rendezvous: ``bind_job_id`` fills it, ``fn`` reads it.
    """
    return {"publisher": None, "job_id": None}


def _with_job_id(request: TrainingRequest, job_id: str | None) -> TrainingRequest:
    """Return *request* with ``job_id`` merged into its payload.

    Some adapters need their own job_id available in their payload, but
    job_store only mints the job_id *after* the ``TrainingRequest`` is built
    (``bind_job_id`` fires between job creation and worker launch). Threading
    it into the payload dict here, right before the adapter runs, lets
    adapters keep reading every training knob from the flat ``payload`` the
    same way they already do — no new ``TrainingRequest`` field needed.
    """
    if job_id is None:
        return request
    payload = dict(request.payload or {})
    payload.setdefault("job_id", job_id)
    return replace(request, payload=payload)


async def submit_training_job_forced(
    backend_name: str,
    training_mode: str | None,
    payload: dict,
    request_id: str | None = None,
) -> str:
    """Submit a training job without checking availability.

    Used for backward-compatible routes where fallback behavior
    is expected when the adapter is unavailable.
    """
    registry = _get_registry()
    adapter = registry.get_adapter(backend_name)
    resolved_mode = registry.resolve_mode(adapter, training_mode)
    resolved_payload = await _resolve_dataset_payload(payload)
    resolved_request = TrainingRequest(
        backend_name=backend_name,
        training_mode=resolved_mode,
        payload=resolved_payload,
    )

    holder = _build_publisher_holder()

    def _bind(job_id: str) -> None:
        holder["publisher"] = progress_bus.publisher_for(job_id)
        holder["job_id"] = job_id

    def _run_and_serialize() -> dict:
        publisher = holder.get("publisher")
        request_to_run = _with_job_id(resolved_request, holder.get("job_id"))
        result = adapter.run(request_to_run, progress=publisher)
        if publisher is not None:
            publisher(
                {
                    "type": "done" if result.status == "completed" else "failed",
                    "status": result.status,
                    "final_loss": result.final_loss,
                    "n_epochs": result.n_epochs,
                    "duration_seconds": result.duration_seconds,
                    "error": result.error,
                }
            )
        return _serialize_training_result(result)

    job_id = await job_store.submit(
        _run_and_serialize,
        request_id=request_id,
        bind_job_id=_bind,
        on_terminal=progress_bus.close,
    )
    logger.info(
        "training_job_submitted_forced",
        job_id=job_id,
        backend_name=backend_name,
        training_mode=resolved_request.training_mode,
    )
    return job_id
