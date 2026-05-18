"""Orchestration service for first-run backend deployment."""

from __future__ import annotations

import threading
from pathlib import Path
from typing import Any
from uuid import uuid4

from .deployment_contracts import (
    DeploymentEvent,
    DeploymentJob,
    DeploymentTarget,
    TERMINAL_JOB_STAGES,
    redact_payload,
    utc_now_iso,
)
from .deployment_executors import executor_for_mode
from .deployment_preflight import run_preflight
from .deployment_store import DeploymentStore


class DeploymentService:
    def __init__(self, *, store: DeploymentStore, repo_root: Path) -> None:
        self._store = store
        self._repo_root = repo_root
        self._lock = threading.RLock()
        self._cancelled: set[str] = set()
        self._threads: dict[str, threading.Thread] = {}

    def list_targets(self) -> list[dict[str, Any]]:
        return self._store.list_targets()

    def create_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._store.upsert_target(payload)

    def update_target(self, target_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        return self._store.upsert_target({"id": target_id, **payload})

    def delete_target(self, target_id: str) -> None:
        self._store.delete_target(target_id)

    def selected_target(self) -> dict[str, Any] | None:
        return self._store.selected_target()

    def is_ready(self) -> bool:
        selected = self._store.selected_target()
        return bool(selected and selected.get("lastReadiness") == "ready")

    def preflight(self, payload: dict[str, Any]) -> dict[str, Any]:
        target_payload = payload.get("target")
        if isinstance(target_payload, dict):
            target = DeploymentTarget.from_json(redact_payload(target_payload))
        else:
            target_id = str(payload.get("targetId") or "")
            target = self._store.get_target(target_id)
        result = run_preflight(target, repo_root=self._repo_root)
        return result.to_json()

    def create_job(self, payload: dict[str, Any]) -> dict[str, Any]:
        target_id = str(payload.get("targetId") or "")
        if not target_id and isinstance(payload.get("target"), dict):
            target_json = self.create_target(payload["target"])
            target_id = str(target_json["id"])
        target = self._store.get_target(target_id)
        job = DeploymentJob(
            id=str(payload.get("id") or uuid4()),
            target_id=target.id,
            mode=str(payload.get("mode") or target.mode),
        )
        self._store.save_job(job)
        thread = threading.Thread(
            target=self._run_job,
            args=(job.id,),
            name=f"deployment-job-{job.id}",
            daemon=True,
        )
        with self._lock:
            self._threads[job.id] = thread
        thread.start()
        return job.to_json()

    def get_job(self, job_id: str) -> dict[str, Any]:
        return self._store.get_job(job_id).to_json()

    def cancel_job(self, job_id: str) -> dict[str, Any]:
        with self._lock:
            self._cancelled.add(job_id)
        job = self._store.get_job(job_id)
        if job.stage not in TERMINAL_JOB_STAGES:
            self._emit(job, "cancelled", "Deployment cancelled by user", job.percent)
            job.terminal_outcome = "cancelled"
            self._store.save_job(job)
        return job.to_json()

    def retry_job(self, job_id: str) -> dict[str, Any]:
        job = self._store.get_job(job_id)
        return self.create_job({"targetId": job.target_id, "mode": job.mode})

    def job_events(self, job_id: str) -> list[str]:
        job = self._store.get_job(job_id)
        return [
            DeploymentEvent(
                job_id=str(event.get("jobId") or job.id),
                stage=str(event.get("stage") or job.stage),
                message=str(event.get("message") or ""),
                percent=float(event.get("percent") or 0.0),
                created_at=str(event.get("createdAt") or utc_now_iso()),
            ).to_sse()
            for event in job.events
        ]

    def _run_job(self, job_id: str) -> None:
        job = self._store.get_job(job_id)
        target = self._store.get_target(job.target_id)
        executor = executor_for_mode(
            job.mode,
            repo_root=self._repo_root,
            secret_resolver=self._store.resolve_secret,
        )
        try:
            executor.run(target, lambda stage, message, percent: self._emit(job, stage, message, percent))
            if self._is_cancelled(job.id):
                self.cancel_job(job.id)
                return
            job.stage = "completed"
            job.percent = 100
            job.stage_label = "Ready"
            job.terminal_outcome = "completed"
            job.updated_at = utc_now_iso()
            self._store.save_job(job)
            self._store.set_selected_target(target.id)
            self._store.update_target_readiness(
                target.id,
                readiness="ready",
                deployed_version=target.image_tag,
            )
        except Exception as exc:  # noqa: BLE001
            self._emit(job, "failed", str(exc), job.percent)
            job.error = str(exc)
            job.terminal_outcome = "failed"
            job.updated_at = utc_now_iso()
            self._store.save_job(job)
            self._store.update_target_readiness(
                target.id,
                readiness="failed",
                failure_reason=str(exc),
            )

    def _emit(self, job: DeploymentJob, stage: str, message: str, percent: float) -> None:
        if self._is_cancelled(job.id) and stage not in TERMINAL_JOB_STAGES:
            raise RuntimeError("Deployment cancelled")
        event = DeploymentEvent(
            job_id=job.id,
            stage=stage,
            message=message,
            percent=percent,
        )
        job.stage = stage
        job.percent = max(0.0, min(100.0, float(percent)))
        job.stage_label = message
        job.last_log_line = message
        job.logs.append(message)
        job.events.append(event.to_json())
        job.updated_at = utc_now_iso()
        self._store.save_job(job)

    def _is_cancelled(self, job_id: str) -> bool:
        with self._lock:
            return job_id in self._cancelled
