"""In-memory background-job registry for long-running env operations.

``create``, ``install``, ``uninstall``, and ``import`` can take seconds to
minutes (pip resolution). The handlers kick them off here and return a job id;
the Flutter UI polls ``GET /nmtk-envs/api/jobs/<id>`` until the state leaves
``working``. State vocabulary matches the app's readiness states.
"""

from __future__ import annotations

from copy import deepcopy
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable

from .manager import EnvironmentError_

_STATE_WORKING = "working"
_STATE_READY = "ready"
_STATE_ERROR = "error"


class JobRegistry:
    """Thread-safe registry that runs callables on a small worker pool."""

    def __init__(self, max_workers: int = 2) -> None:
        self._jobs: dict[str, dict[str, Any]] = {}
        self._kernels: dict[str, Any] = {}
        self._lock = threading.Lock()
        self._pool = ThreadPoolExecutor(
            max_workers=max_workers, thread_name_prefix="nmtk-env"
        )

    def submit(self, kind: str, fn: Callable[[], Any]) -> str:
        job_id = self.create(kind)
        self.run(job_id, fn)
        return job_id

    def create(self, kind: str) -> str:
        job_id = uuid.uuid4().hex
        with self._lock:
            self._jobs[job_id] = {
                "id": job_id,
                "kind": kind,
                "state": _STATE_WORKING,
                "output": [],
            }
        return job_id

    def run(self, job_id: str, fn: Callable[[], Any]) -> None:
        self._pool.submit(self._run, job_id, fn)

    def append_output(self, job_id: str, line: str) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job is None:
                return
            job.setdefault("output", []).append(line)

    def register_kernel(self, job_id: str, kernel_manager: Any) -> None:
        """Associate a running job with its kernel manager so it can be cancelled."""
        with self._lock:
            self._kernels[job_id] = kernel_manager

    def cancel(self, job_id: str) -> bool:
        """Shut down the kernel backing *job_id*, if it is still running.

        Returns False if the job is unknown. The job's own worker thread
        observes the dead kernel and transitions it to the error state via
        the normal `_run` exception path, so this only needs to trigger the
        shutdown, not update job state itself.
        """
        with self._lock:
            job = self._jobs.get(job_id)
            kernel_manager = self._kernels.get(job_id)
        if job is None:
            return False
        if kernel_manager is not None:
            try:
                kernel_manager.shutdown_kernel(now=True)
            except Exception:  # noqa: BLE001 — kernel may already be gone
                pass
        return True

    def _run(self, job_id: str, fn: Callable[[], Any]) -> None:
        try:
            result = fn()
            self._update(job_id, state=_STATE_READY, result=result)
        except EnvironmentError_ as exc:  # expected, user-actionable failures
            self._update(
                job_id, state=_STATE_ERROR, error=str(exc), log=getattr(exc, "log", "")
            )
        except Exception as exc:  # noqa: BLE001 — surface unexpected failures to the UI
            self._update(job_id, state=_STATE_ERROR, error=str(exc))

    def _update(self, job_id: str, **fields: Any) -> None:
        with self._lock:
            if job_id in self._jobs:
                self._jobs[job_id].update(fields)

    def get(self, job_id: str) -> dict[str, Any] | None:
        with self._lock:
            job = self._jobs.get(job_id)
            return deepcopy(job) if job else None
