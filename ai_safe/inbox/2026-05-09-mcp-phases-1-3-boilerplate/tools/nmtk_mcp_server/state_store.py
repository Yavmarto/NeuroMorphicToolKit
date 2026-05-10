import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class StatePaths:
    base_dir: Path

    @property
    def sessions_dir(self) -> Path:
        return self.base_dir / "sessions"

    @property
    def jobs_dir(self) -> Path:
        return self.base_dir / "jobs"

    @property
    def artifacts_dir(self) -> Path:
        return self.base_dir / "artifacts"

    @property
    def deerflow_dir(self) -> Path:
        return self.base_dir / "deerflow"


class StateStore:
    def __init__(self, paths: StatePaths) -> None:
        self.paths = paths

    def ensure_layout(self) -> None:
        """Create the expected directory layout."""
        self.paths.sessions_dir.mkdir(parents=True, exist_ok=True)
        self.paths.jobs_dir.mkdir(parents=True, exist_ok=True)
        self.paths.artifacts_dir.mkdir(parents=True, exist_ok=True)
        self.paths.deerflow_dir.mkdir(parents=True, exist_ok=True)

    def write_session(self, session_id: str, payload: dict[str, Any]) -> Path:
        path = self.paths.sessions_dir / f"{session_id}.json"
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    def write_job(self, job_id: str, payload: dict[str, Any]) -> Path:
        path = self.paths.jobs_dir / f"{job_id}.json"
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    def write_deerflow_packet(self, task_id: str, payload: dict[str, Any]) -> Path:
        task_dir = self.paths.deerflow_dir / task_id
        task_dir.mkdir(parents=True, exist_ok=True)
        path = task_dir / "packet.json"
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    def write_deerflow_result(self, task_id: str, payload: dict[str, Any]) -> Path:
        task_dir = self.paths.deerflow_dir / task_id
        task_dir.mkdir(parents=True, exist_ok=True)
        path = task_dir / "result.json"
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return path

    def read_json(self, path: Path) -> dict[str, Any]:
        return json.loads(path.read_text(encoding="utf-8"))
