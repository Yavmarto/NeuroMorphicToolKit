"""Orchestration service for first-run backend deployment."""

from __future__ import annotations

import os
import threading
import time
import urllib.request
from pathlib import Path
from typing import Any
from uuid import uuid4

from .deployment_contracts import (
    DEPLOYMENT_CONTAINER_ENGINES,
    DeploymentEvent,
    DeploymentJob,
    DeploymentTarget,
    TERMINAL_JOB_STAGES,
    bounded_terminal_output,
    redact_payload,
    redact_text,
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
        self._log_persistence_timers: dict[str, threading.Timer] = {}
        self._remote_readiness_cache: tuple[str, float, bool] | None = None

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
        if os.environ.get("NMTK_BACKEND_DEPLOYMENT_READY", "").lower() in (
            "1",
            "true",
            "yes",
        ):
            return True
        selected = self._store.selected_target()
        if not selected or selected.get("lastReadiness") != "ready":
            return False
        if selected.get("targetType") != "remote_host":
            return True

        host = str(selected.get("host") or "").strip()
        backend_port = int(selected.get("backendPort") or 9000)
        target_id = str(selected.get("id") or "")
        cache_key = f"{target_id}:{host}:{backend_port}"
        cached = self._remote_readiness_cache
        now = time.monotonic()
        if cached and cached[0] == cache_key and now - cached[1] < 5:
            return cached[2]

        urls = (
            f"http://{host}:{backend_port}/api/suite/health",
            f"http://{host}:8090/health",
            f"http://{host}:{backend_port}/api/neurocnl/health",
        )
        ready = bool(host and target_id)
        if ready:
            try:
                for url in urls:
                    with urllib.request.urlopen(url, timeout=1.5) as response:
                        if response.status != 200:
                            ready = False
                            break
            except (OSError, ValueError):
                ready = False
        self._remote_readiness_cache = (cache_key, now, ready)
        if not ready and target_id:
            self._store.update_target_readiness(
                target_id,
                readiness="failed",
                failure_reason=(
                    "Required client-facing services are not reachable from "
                    f"launcher control at {host}."
                ),
            )
        return ready

    def bootstrap_remote_user(self, payload: dict[str, Any]) -> dict[str, Any]:
        """One-time root SSH bootstrap: create a dedicated non-root deploy user.

        Deliberately bypasses `self._store` entirely -- root credentials in
        `payload` are used for a single SSH session and never persisted.
        """
        from .deployment_user_bootstrap import ssh_root_bootstrap

        container_engine = str(payload.get("containerEngine") or "docker")
        if container_engine not in DEPLOYMENT_CONTAINER_ENGINES:
            raise ValueError(f"Unsupported container engine: {container_engine}")

        return ssh_root_bootstrap(
            host=str(payload.get("host") or ""),
            ssh_port=int(payload.get("sshPort") or 22),
            root_username=str(payload.get("rootUsername") or "root"),
            root_password=str(payload.get("rootPassword") or ""),
            root_private_key=str(payload.get("rootPrivateKey") or ""),
            deploy_username=str(payload.get("deployUsername") or "nmtk"),
            container_engine=container_engine,
        )

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
            clean_install=bool(payload.get("cleanInstall") or False),
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
        job = self._store.get_job(job_id)
        if job.stage in TERMINAL_JOB_STAGES:
            with self._lock:
                thread = self._threads.get(job_id)
            if thread is not None and thread is not threading.current_thread():
                thread.join(timeout=1)
                job = self._store.get_job(job_id)
        return job.to_json()

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
            executor.run(
                target,
                lambda stage, message, percent: self._emit(
                    job, stage, message, percent
                ),
                log=lambda line: self._emit_log(job, line),
                clean_install=job.clean_install,
            )
            if self._is_cancelled(job.id):
                self.cancel_job(job.id)
                return
            # A completed job promises that the selected deployment is ready.
            # Persist that state before making the terminal result observable
            # so clients cannot receive "completed" and then see readiness
            # still unset during the same refresh.
            self._store.set_selected_target(target.id)
            self._store.update_target_readiness(
                target.id,
                readiness="ready",
                deployed_version=target.image_tag,
            )
            job.stage = "completed"
            job.percent = 100
            job.stage_label = "Ready"
            job.terminal_outcome = "completed"
            job.updated_at = utc_now_iso()
            self._cancel_log_persistence(job.id)
            self._store.save_job(job)
        except Exception as exc:  # noqa: BLE001
            failed_phase = job.stage
            safe_error = redact_text(str(exc))
            summary = self._failure_summary(failed_phase)
            self._emit(job, "failed", summary, job.percent)
            job.error = safe_error
            job.failure_details = {
                "code": "deployment_phase_failed",
                "phase": failed_phase,
                "summary": summary,
                "recovery": safe_error,
                "technicalDetails": safe_error[-8000:],
                "existingConnectionReachable": self.is_ready(),
            }
            job.terminal_outcome = "failed"
            job.updated_at = utc_now_iso()
            self._cancel_log_persistence(job.id)
            self._store.save_job(job)
            self._store.update_target_readiness(
                target.id,
                readiness=(
                    "degraded"
                    if str(exc).startswith("degraded optional capability:")
                    else "failed"
                ),
                failure_reason=safe_error,
            )

    @staticmethod
    def _failure_summary(stage: str) -> str:
        return {
            "installing": "The selected container engine could not be prepared",
            "uploading_assets": "The deployment bundle could not be uploaded",
            "pulling_images": "The NMTK images could not be downloaded",
            "starting_containers": "The NMTK services could not be started",
            "verifying": "Required NMTK services did not become reachable",
        }.get(stage, "Server deployment failed")

    def _emit(
        self, job: DeploymentJob, stage: str, message: str, percent: float
    ) -> None:
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
        self._cancel_log_persistence(job.id)
        self._store.save_job(job)

    def _emit_log(self, job: DeploymentJob, line: str) -> None:
        """Append a raw remote-command output line to the job's log tail.

        Unlike `_emit`, this does NOT change `stage`, `percent`, or
        `stage_label` — the headline keeps showing the high-level phase
        while real terminal output streams underneath it. The line is
        redacted (mirroring `DeploymentEvent.to_json`) and empty lines are
        dropped. An event is appended too so the SSE stream carries it.
        """
        if self._is_cancelled(job.id) and job.stage not in TERMINAL_JOB_STAGES:
            raise RuntimeError("Deployment cancelled")
        clean = redact_text(line.rstrip("\r\n"))
        if not clean.strip():
            return
        event = DeploymentEvent(
            job_id=job.id,
            stage=job.stage,
            message=clean,
            percent=job.percent,
        )
        job.last_log_line = clean
        job.logs.append(clean)
        job.terminal_output = bounded_terminal_output([*job.terminal_output, clean])
        job.events.append(event.to_json())
        job.updated_at = utc_now_iso()
        self._schedule_log_persistence(job)

    def _schedule_log_persistence(self, job: DeploymentJob) -> None:
        """Persist a growing transcript at most once per debounce window."""
        with self._lock:
            if job.id in self._log_persistence_timers:
                return
            timer = threading.Timer(
                0.3,
                self._persist_debounced_log,
                args=(job,),
            )
            timer.daemon = True
            self._log_persistence_timers[job.id] = timer
            timer.start()

    def _persist_debounced_log(self, job: DeploymentJob) -> None:
        with self._lock:
            self._log_persistence_timers.pop(job.id, None)
        self._store.save_job(job)

    def _cancel_log_persistence(self, job_id: str) -> None:
        with self._lock:
            timer = self._log_persistence_timers.pop(job_id, None)
        if timer is not None:
            timer.cancel()

    def _is_cancelled(self, job_id: str) -> bool:
        with self._lock:
            return job_id in self._cancelled
