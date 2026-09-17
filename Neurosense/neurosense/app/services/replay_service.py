"""
Session replay service -- plays back recorded HDF5 sessions at
configurable speed, emitting data as if it were live acquisition.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncGenerator
from typing import Any

import numpy as np

from ..storage import default_recordings_dir
from .session_artifact import load_artifact_data

_RECORDINGS_DIR = default_recordings_dir()


class ReplayService:
    """Manages replay of recorded sessions at configurable playback speed."""

    def __init__(self) -> None:
        self._active: bool = False
        self._session_id: str | None = None
        self._speed: float = 1.0
        self._cancel_event: asyncio.Event | None = None

    @property
    def is_active(self) -> bool:
        return self._active

    async def start(
        self,
        session_id: str,
        speed: float = 1.0,
    ) -> dict[str, Any]:
        """Begin replay of a recorded session.

        Returns replay metadata dict.
        Raises FileNotFoundError if the session HDF5 is missing.
        Raises RuntimeError if a replay is already active.
        """
        if self._active:
            raise RuntimeError("A replay is already active. Stop it first.")

        file_path = _RECORDINGS_DIR / f"{session_id}.hdf5"
        if not file_path.exists():
            raise FileNotFoundError(f"Session file not found: {file_path}")

        self._session_id = session_id
        self._speed = max(0.1, min(speed, 10.0))
        self._cancel_event = asyncio.Event()
        self._active = True

        return {
            "session_id": session_id,
            "speed": self._speed,
            "status": "replaying",
        }

    async def stop(self) -> dict[str, Any]:
        """Stop the currently active replay."""
        if not self._active:
            raise RuntimeError("No active replay to stop.")

        if self._cancel_event:
            self._cancel_event.set()

        session_id = self._session_id
        self._active = False
        self._session_id = None
        self._cancel_event = None

        return {
            "session_id": session_id,
            "status": "stopped",
        }

    async def stream_chunks(
        self,
        chunk_samples: int = 50,
    ) -> AsyncGenerator[np.ndarray[Any, Any], None]:
        """Yield data chunks from the session file at the configured speed.

        Each chunk is a (channels x chunk_samples) numpy array.
        """
        if not self._active or self._session_id is None:
            return

        file_path = _RECORDINGS_DIR / f"{self._session_id}.hdf5"

        try:
            raw, timestamps, metadata = load_artifact_data(file_path)
            if raw is None:
                return

            sampling_rate = float(metadata["sampling_rate_hz"])
            total_samples = raw.shape[1]
            chunk_duration = chunk_samples / sampling_rate
            previous_timestamp = None

            if timestamps is None or len(timestamps) == 0:
                delay = chunk_duration / self._speed
            else:
                delay = None

            for start in range(0, total_samples, chunk_samples):
                if self._cancel_event and self._cancel_event.is_set():
                    break
                end = min(start + chunk_samples, total_samples)
                yield raw[:, start:end]

                if delay is not None:
                    await asyncio.sleep(delay)
                    continue

                current_timestamp = float(timestamps[start])
                if previous_timestamp is None:
                    previous_timestamp = current_timestamp
                    await asyncio.sleep(chunk_duration / self._speed)
                    continue

                replay_delay = (
                    max(
                        current_timestamp - previous_timestamp,
                        chunk_duration,
                    )
                    / self._speed
                )
                previous_timestamp = current_timestamp
                await asyncio.sleep(replay_delay)

        except ImportError:
            # h5py not available
            return

        finally:
            self._active = False


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
replay_service = ReplayService()
