"""Asynchronous, persisted updates for launcher-managed Akida runtimes."""

from __future__ import annotations

import os
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from .provisioning_helpers import ensure_agent_wheel
from .runtime_artifact import (
    NeurochipRuntimeArtifact,
    discover_neurochip_runtime_artifact,
    inspect_neurochip_runtime_artifact,
)
from .runtime_shared import _module_root

_ACTIVE_UPDATE_STATES = {"queued", "running"}
_MAX_PERSISTED_UPDATE_JOBS = 50


class _RuntimeVersionMismatch(RuntimeError):
    """The host reported a different Neurochip version than the release bundled."""


class _InstallStatusMissing(RuntimeError):
    """The remote install finished without reporting an install status."""


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _runtime_update_failure(error: str) -> tuple[str, str, str]:
    """Map one raw remote failure onto a typed, redacted user-facing verdict.

    Matching is by substring over pip/ssh output, so ordering matters: the
    narrow markers have to win before the broad ones. In particular the pip
    resolver branch must precede everything that could also match its text —
    "these package versions have conflicting dependencies" once fell through
    to a version branch and told the user to retry a resolution failure that
    can only ever fail the same way.
    """
    normalized = error.lower()
    if "permission denied" in normalized or "authentication" in normalized:
        return (
            "ssh_auth_failed",
            "The selected Akida host rejected its saved SSH credential.",
            "Open CNL Studio Setup, edit the selected Akida target, and save a working SSH credential.",
        )
    if any(
        marker in normalized
        for marker in ("username is required", "password is configured", "sshkeypath")
    ):
        return (
            "ssh_auth_failed",
            "The selected Akida host does not have complete managed SSH credentials.",
            "Open CNL Studio Setup, edit the selected Akida target, and provide its SSH login credential.",
        )
    if any(
        marker in normalized
        for marker in (
            "connection refused",
            "no route to host",
            "timed out",
            "could not resolve",
        )
    ):
        return (
            "ssh_unreachable",
            "The selected Akida host could not be reached over SSH.",
            "Make sure the host is powered on and reachable, then retry the Akida update in Backend Setup.",
        )
    if "sudo" in normalized:
        return (
            "sudo_required",
            "The selected Akida host could not install or restart its managed service.",
            "Edit the target with an SSH account that can use sudo, then retry the Akida update.",
        )
    if any(
        marker in normalized
        for marker in (
            "resolutionimpossible",
            "cannot install",
            "no matching distribution",
            "could not find a version that satisfies",
            "conflicting dependencies",
        )
    ):
        return (
            "dependency_conflict",
            "The paired Akida host could not install the Akida SDK packages this backend release requires.",
            "Update the backend to a release with a corrected Akida package set — retrying this update will fail the same way.",
        )
    if "artifact" in normalized or "wheel" in normalized:
        return (
            "artifact_missing",
            "This backend release does not contain a valid Neurochip runtime artifact.",
            "Update the backend again after a corrected release is available.",
        )
    if "health" in normalized or "could not be reached" in normalized:
        return (
            "service_unhealthy",
            "The new Neurochip service did not become healthy, so the previous runtime was restored when available.",
            "Review the selected host readiness in CNL Studio and retry the Akida update.",
        )
    return (
        "install_failed",
        "The selected Akida runtime could not be updated.",
        "Retry the Akida update from Backend Setup or review the target in CNL Studio Setup.",
    )


class AkidaRuntimeUpdateJobsMixin:
    """Persist and run selected-host Neurochip runtime updates."""

    def _neurochip_runtime_artifact(self) -> NeurochipRuntimeArtifact:
        cached = getattr(self, "_cached_neurochip_runtime_artifact", None)
        if isinstance(cached, NeurochipRuntimeArtifact):
            return cached
        artifact_directory = str(os.getenv("NMTK_NEUROCHIP_ARTIFACT_DIR") or "").strip()
        if artifact_directory:
            artifact = discover_neurochip_runtime_artifact(Path(artifact_directory))
        else:
            neurochip_root = _module_root(self._get_module("Neurochip"))
            artifact = inspect_neurochip_runtime_artifact(
                ensure_agent_wheel(neurochip_root)
            )
        self._cached_neurochip_runtime_artifact = artifact
        return artifact

    def _runtime_update_jobs(self) -> list[dict[str, Any]]:
        jobs = self._settings.setdefault("akidaRuntimeUpdateJobs", [])
        return jobs if isinstance(jobs, list) else []

    def _persist_runtime_update_job(self, job: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            jobs = [
                existing
                for existing in self._runtime_update_jobs()
                if str(existing.get("jobId") or "") != job["jobId"]
            ]
            jobs.append(dict(job))
            self._settings["akidaRuntimeUpdateJobs"] = jobs[
                -_MAX_PERSISTED_UPDATE_JOBS:
            ]
            self._persist_settings()
        return dict(job)

    def _update_runtime_update_job(
        self,
        job_id: str,
        **changes: Any,
    ) -> dict[str, Any]:
        with self._lock:
            job = next(
                (
                    existing
                    for existing in self._runtime_update_jobs()
                    if str(existing.get("jobId") or "") == job_id
                ),
                None,
            )
            if job is None:
                raise KeyError(f"Unknown Akida runtime update job '{job_id}'")
            job.update(changes)
            job["updatedAt"] = _utc_now()
            result = dict(job)
            self._persist_settings()
            return result

    def create_akida_runtime_update_job(self, host_id: str) -> dict[str, Any]:
        """Create or reuse a checksummed update for one paired Akida host."""
        host = self._get_akida_host(host_id)
        try:
            artifact = self._neurochip_runtime_artifact()
        except Exception:  # noqa: BLE001
            now = _utc_now()
            job = {
                "jobId": str(uuid4()),
                "hostId": host_id,
                "artifactVersion": "",
                "artifactSha256": "",
                "stage": "failed",
                "progress": 100,
                "message": "This backend release does not contain a valid Neurochip runtime artifact.",
                "status": "failed",
                "errorCode": "artifact_missing",
                "recovery": "Update the backend again after a corrected release is available.",
                "installedVersion": str(host.get("installedRuntimeVersion") or ""),
                "installMode": "",
                "rolledBack": False,
                "createdAt": now,
                "updatedAt": now,
            }
            self._persist_runtime_update_job(job)
            self._update_akida_host_fields(
                host_id,
                runtimeUpdateState="failed",
                lastRuntimeUpdateJob=job,
            )
            return dict(job)
        with self._lock:
            for existing in reversed(self._runtime_update_jobs()):
                if (
                    str(existing.get("hostId") or "") == host_id
                    and str(existing.get("status") or "") in _ACTIVE_UPDATE_STATES
                ):
                    return dict(existing)
                if (
                    str(existing.get("hostId") or "") == host_id
                    and str(existing.get("artifactSha256") or "") == artifact.sha256
                    and str(existing.get("status") or "") == "completed"
                ):
                    return dict(existing)
        now = _utc_now()
        job = {
            "jobId": str(uuid4()),
            "hostId": host_id,
            "artifactVersion": artifact.version,
            "artifactSha256": artifact.sha256,
            "stage": "queued",
            "progress": 0,
            "message": "Akida runtime update queued",
            "status": "queued",
            "errorCode": "",
            "recovery": "",
            "installedVersion": str(host.get("installedRuntimeVersion") or ""),
            "installMode": "",
            "rolledBack": False,
            "createdAt": now,
            "updatedAt": now,
        }
        self._persist_runtime_update_job(job)
        self._update_akida_host_fields(
            host_id,
            availableRuntimeVersion=artifact.version,
            runtimeUpdateState="queued",
            lastRuntimeUpdateJob=job,
        )
        thread = threading.Thread(
            target=self._run_akida_runtime_update_job,
            args=(job["jobId"], host_id, artifact),
            daemon=True,
            name=f"akida-runtime-update-{host_id}",
        )
        threads = getattr(self, "_akida_runtime_update_threads", None)
        if not isinstance(threads, dict):
            threads = {}
            self._akida_runtime_update_threads = threads
        threads[job["jobId"]] = thread
        thread.start()
        return dict(job)

    def get_akida_runtime_update_job(
        self,
        host_id: str,
        job_id: str,
    ) -> dict[str, Any]:
        """Return one persisted update job after checking host ownership."""
        with self._lock:
            job = next(
                (
                    existing
                    for existing in self._runtime_update_jobs()
                    if str(existing.get("jobId") or "") == job_id
                ),
                None,
            )
            if job is None or str(job.get("hostId") or "") != host_id:
                raise KeyError(f"Unknown Akida runtime update job '{job_id}'")
            return dict(job)

    def _run_akida_runtime_update_job(
        self,
        job_id: str,
        host_id: str,
        artifact: NeurochipRuntimeArtifact,
    ) -> None:
        def progress(stage: str, percent: int, message: str) -> None:
            job = self._update_runtime_update_job(
                job_id,
                stage=stage,
                progress=percent,
                message=message,
                status="running",
            )
            self._update_akida_host_fields(
                host_id,
                availableRuntimeVersion=artifact.version,
                runtimeUpdateState=stage,
                lastRuntimeUpdateJob=job,
            )

        try:
            result = self._provision_akida_host(host_id, progress=progress)
            raw_error = str(result.get("error") or "").strip()
            install_status = (
                result.get("installStatus")
                if isinstance(result.get("installStatus"), dict)
                else {}
            )
            installed_version = str(install_status.get("packageVersion") or "").strip()
            if raw_error:
                raise RuntimeError(raw_error)
            # Both of these used to be plain RuntimeErrors classified by
            # substring, which meant an empty install status and a genuine
            # version difference reported the same verdict — and any remote
            # error mentioning a version stole it from them.
            if not install_status:
                raise _InstallStatusMissing(
                    "Remote install finished without reporting an install status"
                )
            if installed_version != artifact.version:
                raise _RuntimeVersionMismatch(
                    "Installed Neurochip runtime version does not match the bundled version"
                )
            job = self._update_runtime_update_job(
                job_id,
                stage="completed",
                progress=100,
                message="Selected Akida runtime is up to date",
                status="completed",
                installedVersion=installed_version,
                installMode=str(install_status.get("installMode") or ""),
                rolledBack=False,
            )
            self._update_akida_host_fields(
                host_id,
                installedRuntimeVersion=installed_version,
                availableRuntimeVersion=artifact.version,
                runtimeArtifactSha256=artifact.sha256,
                runtimeUpdateState="completed",
                lastRuntimeUpdateJob=job,
            )
        except Exception as exc:  # noqa: BLE001
            raw_error = str(exc)
            # The two locally raised conditions are matched by type, never by
            # text, so remote output can no longer be mistaken for either.
            if isinstance(exc, _InstallStatusMissing):
                error_code, message, recovery = (
                    "install_status_missing",
                    "The paired Akida host finished installing but never reported its install status.",
                    "Check that the selected host can write its install-status file, then retry the Akida update.",
                )
            elif isinstance(exc, _RuntimeVersionMismatch):
                error_code, message, recovery = (
                    "version_mismatch",
                    "The installed Neurochip runtime version did not match the backend release.",
                    "Retry the Akida update from Backend Setup.",
                )
            else:
                error_code, message, recovery = _runtime_update_failure(raw_error)
            job = self._update_runtime_update_job(
                job_id,
                stage="failed",
                progress=100,
                message=message,
                status="failed",
                errorCode=error_code,
                recovery=recovery,
                rolledBack="AKIDA_RUNTIME_ROLLED_BACK=1" in raw_error,
            )
            self._update_akida_host_fields(
                host_id,
                availableRuntimeVersion=artifact.version,
                runtimeUpdateState="failed",
                lastRuntimeUpdateJob=job,
                lastReadinessMessage=message,
            )
