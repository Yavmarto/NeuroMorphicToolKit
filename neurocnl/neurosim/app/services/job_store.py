"""Service for managing simulation jobs in-memory."""

from __future__ import annotations

import threading
import uuid
from typing import TYPE_CHECKING, Any

from neurosim.contracts.design_contracts import (
    BackendSupport,
    GeneratorFidelitySummary,
    PreviewPlayback,
    SimulationStatus,
)

if TYPE_CHECKING:
    from neurosim.app.schemas.sweep import SweepStepResult


class SimulationJob:
    """Represents a simulation job and its state."""

    def __init__(self, job_id: str, type: str) -> None:
        self.job_id = job_id
        self.type = type  # "preview" or "sweep"
        self.status = SimulationStatus.QUEUED
        self.results: dict[str, Any] | list[SweepStepResult] | None = None
        self.playback: PreviewPlayback | None = None
        self.metrics: dict[str, Any] | None = None
        self.error: str | None = None
        self.parameter_path: str | None = None
        self.backend_support: BackendSupport | None = None
        self.generator_fidelity: GeneratorFidelitySummary | None = None
        self.cancelled = False

    def to_dict(self) -> dict[str, Any]:
        """Convert job state to a dictionary."""
        return {
            "job_id": self.job_id,
            "status": self.status,
            "results": self.results,
            "playback": self.playback,
            "metrics": self.metrics,
            "error": self.error,
            "parameter_path": self.parameter_path,
            "backend_support": self.backend_support,
            "generator_fidelity": self.generator_fidelity,
        }


class SimulationJobStore:
    """In-memory job registry for active simulation runs.

    Scope: process-local only. Jobs are not persisted across restarts and are not
    shared across multiple worker processes. The store uses a thread lock because
    preview and WebSocket execution can mutate job state from worker threads.
    """

    def __init__(self) -> None:
        self._jobs: dict[str, SimulationJob] = {}
        self._lock = threading.RLock()

    def create_job(self, type: str) -> str:
        """Create a new job and return its ID."""
        job_id = str(uuid.uuid4())
        with self._lock:
            self._jobs[job_id] = SimulationJob(job_id, type)
        return job_id

    def get_job(self, job_id: str) -> SimulationJob | None:
        """Get a job by its ID."""
        with self._lock:
            return self._jobs.get(job_id)

    def update_job_status(self, job_id: str, status: SimulationStatus) -> None:
        """Update the status of a job."""
        with self._lock:
            if job_id in self._jobs:
                self._jobs[job_id].status = status

    def update_job_results(
        self,
        job_id: str,
        results: dict[str, Any] | list[SweepStepResult] | None,
        *,
        playback: PreviewPlayback | None = None,
        metrics: dict[str, Any] | None = None,
        backend_support: BackendSupport | None = None,
        generator_fidelity: GeneratorFidelitySummary | None = None,
    ) -> None:
        """Update the results of a job."""
        with self._lock:
            if job_id in self._jobs:
                self._jobs[job_id].results = results
                self._jobs[job_id].playback = playback
                self._jobs[job_id].metrics = metrics
                if backend_support is not None:
                    self._jobs[job_id].backend_support = backend_support
                if generator_fidelity is not None:
                    self._jobs[job_id].generator_fidelity = generator_fidelity
                self._jobs[job_id].status = SimulationStatus.COMPLETED

    def update_job_error(self, job_id: str, error: str) -> None:
        """Update the error of a job."""
        with self._lock:
            if job_id in self._jobs:
                self._jobs[job_id].error = error
                self._jobs[job_id].status = SimulationStatus.FAILED

    def cancel_job(self, job_id: str) -> bool:
        """Mark a job as cancelled."""
        with self._lock:
            if job_id in self._jobs:
                job = self._jobs[job_id]
                if job.status in [SimulationStatus.QUEUED, SimulationStatus.RUNNING]:
                    job.status = SimulationStatus.CANCELLED
                    job.cancelled = True
                    return True
        return False


# Global job store instance
job_store = SimulationJobStore()
