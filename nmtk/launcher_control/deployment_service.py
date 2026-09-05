"""Connect-time deployment facade: target CRUD and live readiness.

Nothing in this file opens an SSH connection or needs sudo -- it only reads
`DeploymentStore` and, for `is_ready`, makes plain HTTP calls to a server
that is already running. Job execution, preflight, and the one-time root SSH
bootstrap (all provision-time, SSH-capable) live in `deployment_provisioner`
and are reached here only by delegation, so `DeploymentService` keeps
satisfying `DeploymentServiceProtocol` unchanged.
"""

from __future__ import annotations

import os
import time
import urllib.request
from pathlib import Path
from typing import Any

from .deployment_provisioner import DeploymentJobRunner
from .deployment_store import DeploymentStore


class DeploymentService:
    def __init__(self, *, store: DeploymentStore, repo_root: Path) -> None:
        self._store = store
        self._remote_readiness_cache: tuple[str, float, bool] | None = None
        self._jobs = DeploymentJobRunner(
            store=store, repo_root=repo_root, is_ready=self.is_ready
        )

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
        return self._jobs.bootstrap_remote_user(payload)

    def preflight(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._jobs.preflight(payload)

    def create_job(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self._jobs.create_job(payload)

    def get_job(self, job_id: str) -> dict[str, Any]:
        return self._jobs.get_job(job_id)

    def cancel_job(self, job_id: str) -> dict[str, Any]:
        return self._jobs.cancel_job(job_id)

    def retry_job(self, job_id: str) -> dict[str, Any]:
        return self._jobs.retry_job(job_id)

    def job_events(self, job_id: str) -> list[str]:
        return self._jobs.job_events(job_id)
