"""Persistence and secret storage for backend deployment setup."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from .deployment_contracts import (
    DeploymentJob,
    DeploymentTarget,
    SECRET_FIELD_NAMES,
    utc_now_iso,
)


def _read_json_file(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def _write_json_file(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


class FileBackedSecretStore:
    """Development secret store that persists secrets outside public manifests."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._secrets: dict[str, str] = _read_json_file(path, {})
        if not isinstance(self._secrets, dict):
            self._secrets = {}

    def put(self, *, target_id: str, field_name: str, value: str) -> str:
        digest = hashlib.sha256(f"{target_id}:{field_name}".encode("utf-8")).hexdigest()
        ref = f"file-secret:{digest[:24]}"
        self._secrets[ref] = value
        self._persist()
        return ref

    def get(self, ref: str) -> str:
        return str(self._secrets.get(ref) or "")

    def delete_many(self, refs: list[str]) -> None:
        changed = False
        for ref in refs:
            if ref in self._secrets:
                del self._secrets[ref]
                changed = True
        if changed:
            self._persist()

    def _persist(self) -> None:
        _write_json_file(self._path, self._secrets)
        try:
            self._path.chmod(0o600)
        except OSError:
            pass


class DeploymentStore:
    def __init__(self, state_path: Path, secret_store: FileBackedSecretStore) -> None:
        self._state_path = state_path
        self._secret_store = secret_store
        state = _read_json_file(state_path, {})
        if not isinstance(state, dict):
            state = {}
        self._targets = [
            DeploymentTarget.from_json(item)
            for item in state.get("targets", [])
            if isinstance(item, dict)
        ]
        self._jobs = [
            DeploymentJob.from_json(item)
            for item in state.get("jobs", [])
            if isinstance(item, dict)
        ]
        self._selected_target_id = str(state.get("selectedTargetId") or "")

    def list_targets(self) -> list[dict[str, Any]]:
        return [target.to_json() for target in self._targets]

    def get_target(self, target_id: str) -> DeploymentTarget:
        for target in self._targets:
            if target.id == target_id:
                return target
        raise KeyError(f"Unknown deployment target '{target_id}'")

    def upsert_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        payload = dict(payload)
        target_id = str(payload.get("id") or "").strip()
        if target_id:
            try:
                existing = self.get_target(target_id)
                payload = {**existing.to_json(), **payload, "id": target_id}
            except KeyError:
                pass
        target = DeploymentTarget.from_json(self._extract_secrets(payload))
        target.updated_at = utc_now_iso()
        next_targets = [item for item in self._targets if item.id != target.id]
        next_targets.append(target)
        self._targets = next_targets
        if not self._selected_target_id:
            self._selected_target_id = target.id
        self._persist()
        return target.to_json()

    def delete_target(self, target_id: str) -> None:
        target = self.get_target(target_id)
        self._secret_store.delete_many(list(target.secret_refs.values()))
        self._targets = [item for item in self._targets if item.id != target_id]
        if self._selected_target_id == target_id:
            self._selected_target_id = self._targets[0].id if self._targets else ""
        self._persist()

    def selected_target(self) -> dict[str, Any] | None:
        if not self._selected_target_id:
            return None
        try:
            return self.get_target(self._selected_target_id).to_json()
        except KeyError:
            return None

    def set_selected_target(self, target_id: str) -> None:
        self.get_target(target_id)
        self._selected_target_id = target_id
        self._persist()

    def list_jobs(self) -> list[dict[str, Any]]:
        return [job.to_json() for job in self._jobs]

    def get_job(self, job_id: str) -> DeploymentJob:
        for job in self._jobs:
            if job.id == job_id:
                return job
        raise KeyError(f"Unknown deployment job '{job_id}'")

    def save_job(self, job: DeploymentJob) -> dict[str, Any]:
        self._jobs = [item for item in self._jobs if item.id != job.id]
        self._jobs.append(job)
        self._jobs = self._jobs[-100:]
        self._persist()
        return job.to_json()

    def update_target_readiness(
        self,
        target_id: str,
        *,
        readiness: str,
        deployed_version: str = "",
        failure_reason: str = "",
    ) -> None:
        target = self.get_target(target_id)
        target.last_readiness = readiness
        target.last_deployed_version = deployed_version or target.last_deployed_version
        target.last_failure_reason = failure_reason
        target.updated_at = utc_now_iso()
        self._persist()

    def _extract_secrets(self, payload: dict[str, Any]) -> dict[str, Any]:
        target_id = str(payload.get("id") or payload.get("displayName") or "target")
        secret_refs = dict(payload.get("secretRefs") or {})
        for field_name in list(SECRET_FIELD_NAMES):
            value = payload.pop(field_name, None)
            if isinstance(value, str) and value:
                secret_refs[field_name] = self._secret_store.put(
                    target_id=target_id,
                    field_name=field_name,
                    value=value,
                )
        payload["secretRefs"] = secret_refs
        return payload

    def _persist(self) -> None:
        _write_json_file(
            self._state_path,
            {
                "targets": [target.to_json() for target in self._targets],
                "jobs": [job.to_json() for job in self._jobs],
                "selectedTargetId": self._selected_target_id,
            },
        )

