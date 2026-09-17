"""Thread-safe in-memory store for active SpiNNaker2 simulation backends."""

import threading

from ..backends.spinnaker2_backend import SpiNNaker2SimBackend


class SpiNNaker2JobStore:
    """Process-local registry of active SpiNNaker2 backend instances keyed by run_id.

    Scope: in-memory only; not persisted across restarts.  The store uses a
    reentrant lock because results may be fetched concurrently with a running
    simulation.
    """

    def __init__(self) -> None:
        self._store: dict[str, SpiNNaker2SimBackend] = {}
        self._lock = threading.RLock()

    def put(self, run_id: str, backend: SpiNNaker2SimBackend) -> None:
        """Register a backend under the given run_id.

        Args:
            run_id (str): Unique identifier for this simulation run.
            backend (SpiNNaker2SimBackend): The backend instance to store.
        """
        with self._lock:
            self._store[run_id] = backend

    def get(self, run_id: str) -> SpiNNaker2SimBackend | None:
        """Retrieve the backend registered for run_id, or None if not found.

        Args:
            run_id (str): The simulation run identifier.

        Returns:
            SpiNNaker2SimBackend | None: The backend if found, otherwise None.
        """
        with self._lock:
            return self._store.get(run_id)

    def remove(self, run_id: str) -> None:
        """Remove the backend entry for run_id (no-op if absent).

        Args:
            run_id (str): The simulation run identifier to remove.
        """
        with self._lock:
            self._store.pop(run_id, None)


# Module-level singleton — mirrors the pattern used by job_store.py
spinnaker2_job_store = SpiNNaker2JobStore()
