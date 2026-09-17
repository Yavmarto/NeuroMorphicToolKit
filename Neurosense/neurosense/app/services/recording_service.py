"""
Recording service -- manages recording lifecycle and HDF5 persistence
with event marker support.
"""

from __future__ import annotations

import asyncio
import importlib
import json
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, cast

import anyio
import numpy as np
import numpy.typing as npt

from ..schemas.encoding import EncodingConfig, build_encoding_config
from ..schemas.sessions import EventMarker, RecordingSession
from ..storage import default_recordings_dir
from .session_artifact import (
    ARTIFACT_SCHEMA_VERSION,
    FLAGSHIP_WORKFLOW_ID,
    FLAGSHIP_WORKFLOW_LABEL,
    build_default_hardware_provenance,
    infer_capture_mode,
    infer_support_level,
    normalize_channel_labels,
)

# Default directory for recorded sessions
_RECORDINGS_DIR = default_recordings_dir()

# Guardrail: Flush data to disk after 50MB of in-memory buffer
_FLUSH_THRESHOLD_MB = 50


def _load_h5py() -> Any:
    """Load h5py lazily so type checking does not require third-party stubs."""
    return cast(Any, importlib.import_module("h5py"))


class RecordingService:
    """Manages recording lifecycle: start, stop, marker insertion, and HDF5 writing."""

    def __init__(self) -> None:
        self._active: bool = False
        self._session_id: str | None = None
        self._start_time: float | None = None
        self._device_type: str | None = None
        self._preset_id: str | None = None
        self._channels: int = 0
        self._sampling_rate_hz: int = 250
        self._encoding_config: EncodingConfig | None = None
        self._markers: list[EventMarker] = []
        self._raw_buffer: list[npt.NDArray[np.float64]] = []
        self._filtered_buffer: list[npt.NDArray[np.float64]] = []
        self._spike_buffer: list[dict[str, Any]] = []
        self._subject_id: str | None = None
        self._file_path: Path | None = None
        self._current_buffer_size_bytes: int = 0
        self._timestamp_iso: str | None = None
        self._signal_type: str = "emg"
        self._capture_mode: str = "live"
        self._channel_labels: list[str] = []
        self._hardware_provenance: dict[str, Any] = {}
        self._support_level: str = "experimental"
        # Track in-flight flush tasks so we can await them on shutdown and
        # prevent silent data loss if the process exits during a flush.
        self._flush_tasks: set[asyncio.Task[None]] = set()

    @property
    def is_active(self) -> bool:
        return self._active

    @property
    def session_id(self) -> str | None:
        return self._session_id

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def start(  # noqa: PLR0917 - public recording contract is positional-compatible
        self,
        device_type: str,
        preset_id: str,
        channels: int,
        sampling_rate_hz: int,
        encoding_config: EncodingConfig,
        subject_id: str | None = None,
        signal_type: str = "emg",
        channel_labels: list[str] | None = None,
        hardware_provenance: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Start a new recording session.

        Returns a dict with session_id and start timestamp.
        Raises RuntimeError if a recording is already active.
        """
        if self._active:
            raise RuntimeError("A recording is already active. Stop it first.")

        self._session_id = uuid.uuid4().hex[:12]
        self._start_time = time.time()
        self._device_type = device_type
        self._preset_id = preset_id
        self._channels = channels
        self._sampling_rate_hz = sampling_rate_hz
        self._encoding_config = encoding_config
        self._subject_id = subject_id
        self._timestamp_iso = datetime.now(UTC).isoformat()
        self._signal_type = signal_type
        self._capture_mode = infer_capture_mode(device_type)
        self._support_level = infer_support_level(device_type, self._capture_mode)
        self._channel_labels = normalize_channel_labels(channel_labels, channels)
        self._hardware_provenance = build_default_hardware_provenance(
            device_type=device_type,
            capture_mode=self._capture_mode,
            support_level=self._support_level,
            hardware_provenance=hardware_provenance,
        )
        self._markers = []
        self._raw_buffer = []
        self._filtered_buffer = []
        self._spike_buffer = []
        self._current_buffer_size_bytes = 0
        self._active = True

        # Ensure recordings directory exists and initialize file
        _RECORDINGS_DIR.mkdir(parents=True, exist_ok=True)
        self._file_path = _RECORDINGS_DIR / f"{self._session_id}.hdf5"

        # Initialize the HDF5 file with metadata and empty datasets
        await anyio.to_thread.run_sync(self._init_hdf5, self._file_path)

        return {
            "session_id": self._session_id,
            "timestamp": self._timestamp_iso,
            "status": "recording",
        }

    async def stop(self) -> RecordingSession:
        """Stop the active recording and persist to HDF5.

        Returns the completed RecordingSession metadata.
        Raises RuntimeError if no recording is active.
        """
        if (
            not self._active
            or self._start_time is None
            or self._session_id is None
            or self._file_path is None
        ):
            raise RuntimeError("No active recording to stop.")

        # Flush any remaining data
        await self._flush_to_disk()

        duration = time.time() - self._start_time
        timestamp_iso = (
            self._timestamp_iso
            or datetime.fromtimestamp(
                self._start_time,
                tz=UTC,
            ).isoformat()
        )

        # Finalize the HDF5 file (update duration, close datasets)
        file_size = await anyio.to_thread.run_sync(self._finalize_hdf5, self._file_path, duration)

        session = RecordingSession(
            id=self._session_id,
            timestamp=timestamp_iso,
            duration_seconds=round(duration, 2),
            device_type=self._device_type or "unknown",
            preset_id=self._preset_id or "unknown",
            channels=self._channels,
            sampling_rate_hz=self._sampling_rate_hz,
            encoding_config=self._encoding_config
            or build_encoding_config("rate", rate_max_hz=500.0),
            event_markers=self._markers,
            file_path=str(self._file_path),
            file_size_bytes=file_size,
            subject_id=self._subject_id,
            artifact_schema_version=ARTIFACT_SCHEMA_VERSION,
            signal_type=self._signal_type,
            capture_mode=self._capture_mode,
            channel_labels=self._channel_labels,
            hardware_provenance=self._hardware_provenance,
            support_level=self._support_level,
        )

        # Reset state
        self._active = False
        self._session_id = None
        self._start_time = None
        self._device_type = None
        self._preset_id = None
        self._encoding_config = None
        self._subject_id = None
        self._file_path = None
        self._raw_buffer = []
        self._filtered_buffer = []
        self._spike_buffer = []
        self._current_buffer_size_bytes = 0
        self._timestamp_iso = None
        self._signal_type = "emg"
        self._capture_mode = "live"
        self._channel_labels = []
        self._hardware_provenance = {}
        self._support_level = "experimental"

        return session

    async def insert_marker(self, label: str) -> EventMarker:
        """Insert a timestamped event marker into the active recording.

        Raises RuntimeError if no recording is active.
        """
        if not self._active or self._start_time is None:
            raise RuntimeError("No active recording. Cannot insert marker.")

        offset = time.time() - self._start_time
        marker = EventMarker(timestamp_seconds=round(offset, 4), label=label)
        self._markers.append(marker)
        return marker

    # ------------------------------------------------------------------
    # Data ingestion (called by streaming pipeline)
    # ------------------------------------------------------------------

    def append_raw(self, data: npt.NDArray[np.float64]) -> None:
        """Append a chunk of raw data (channels x samples) to the buffer."""
        if self._active:
            copied = data.copy()
            self._raw_buffer.append(copied)
            self._current_buffer_size_bytes += copied.nbytes
            self._check_flush()

    def append_filtered(self, data: npt.NDArray[np.float64]) -> None:
        if self._active:
            copied = data.copy()
            self._filtered_buffer.append(copied)
            self._current_buffer_size_bytes += copied.nbytes
            self._check_flush()

    def append_spikes(self, spike_data: dict[str, Any]) -> None:
        if self._active:
            self._spike_buffer.append(spike_data)
            # Spike data size is harder to estimate but usually much smaller
            # than raw/filtered arrays. We don't track it precisely for flush.

    def _check_flush(self) -> None:
        """Triggers asynchronous flush if memory threshold is exceeded."""
        if self._current_buffer_size_bytes >= _FLUSH_THRESHOLD_MB * 1024 * 1024:
            task = asyncio.create_task(self._flush_to_disk())
            self._flush_tasks.add(task)
            task.add_done_callback(self._flush_tasks.discard)

    async def _flush_to_disk(self) -> None:
        """Asynchronously writes buffered data to the HDF5 file."""
        if not self._file_path or (not self._raw_buffer and not self._filtered_buffer):
            return

        # Snapshot buffers and reset
        raw_to_write = self._raw_buffer
        filt_to_write = self._filtered_buffer
        self._raw_buffer = []
        self._filtered_buffer = []
        self._current_buffer_size_bytes = 0

        await anyio.to_thread.run_sync(
            self._write_chunks, self._file_path, raw_to_write, filt_to_write
        )

    # ------------------------------------------------------------------
    # HDF5 persistence (running in ThreadPoolExecutor)
    # ------------------------------------------------------------------

    def _init_hdf5(self, file_path: Path) -> None:
        """Initialize the HDF5 file with metadata and resizable datasets."""
        try:
            h5py = _load_h5py()

            with h5py.File(str(file_path), "w") as f:
                # Metadata
                f.attrs["artifact_schema_version"] = ARTIFACT_SCHEMA_VERSION
                f.attrs["workflow_id"] = FLAGSHIP_WORKFLOW_ID
                f.attrs["workflow_label"] = FLAGSHIP_WORKFLOW_LABEL
                f.attrs["session_id"] = self._session_id or ""
                f.attrs["timestamp"] = self._timestamp_iso or ""
                f.attrs["device_type"] = self._device_type or ""
                f.attrs["preset_id"] = self._preset_id or ""
                f.attrs["channels"] = self._channels
                f.attrs["sampling_rate_hz"] = self._sampling_rate_hz
                f.attrs["signal_type"] = self._signal_type
                f.attrs["capture_mode"] = self._capture_mode
                f.attrs["support_level"] = self._support_level
                f.attrs["channel_labels"] = json.dumps(self._channel_labels)
                f.attrs["hardware_provenance"] = json.dumps(self._hardware_provenance)
                if self._subject_id is not None:
                    f.attrs["subject_id"] = self._subject_id
                if self._encoding_config:
                    f.attrs["encoding_config"] = self._encoding_config.model_dump_json()

                # Resizable datasets
                # (channels, samples) -> (channels, None)
                f.create_dataset(
                    "raw",
                    shape=(self._channels, 0),
                    maxshape=(self._channels, None),
                    dtype="float64",
                    chunks=True,
                    compression="gzip",
                )
                f.create_dataset(
                    "filtered",
                    shape=(self._channels, 0),
                    maxshape=(self._channels, None),
                    dtype="float64",
                    chunks=True,
                    compression="gzip",
                )
                f.create_dataset(
                    "timestamps",
                    shape=(0,),
                    maxshape=(None,),
                    dtype="float64",
                    chunks=True,
                    compression="gzip",
                )
                marker_group = f.create_group("markers")
                marker_group.create_dataset(
                    "timestamps",
                    shape=(0,),
                    maxshape=(None,),
                    dtype="float64",
                )
                marker_group.create_dataset(
                    "labels",
                    shape=(0,),
                    maxshape=(None,),
                    dtype=h5py.string_dtype(encoding="utf-8"),
                )
                f.create_group("spikes")

        except ImportError:
            pass

    def _write_chunks(
        self,
        file_path: Path,
        raw_chunks: list[npt.NDArray[np.float64]],
        filt_chunks: list[npt.NDArray[np.float64]],
    ) -> None:
        """Append data chunks to the existing HDF5 datasets."""
        try:
            h5py = _load_h5py()

            with h5py.File(str(file_path), "a") as f:
                samples_to_append = 0

                if raw_chunks:
                    raw_data = np.concatenate(raw_chunks, axis=1)
                    ds = f["raw"]
                    curr_len = ds.shape[1]
                    ds.resize((self._channels, curr_len + raw_data.shape[1]))
                    ds[:, curr_len:] = raw_data
                    samples_to_append = max(samples_to_append, raw_data.shape[1])

                if filt_chunks:
                    filt_data = np.concatenate(filt_chunks, axis=1)
                    ds = f["filtered"]
                    curr_len = ds.shape[1]
                    ds.resize((self._channels, curr_len + filt_data.shape[1]))
                    ds[:, curr_len:] = filt_data

                    samples_to_append = max(samples_to_append, filt_data.shape[1])

                if samples_to_append:
                    timestamp_ds = f["timestamps"]
                    current_len = timestamp_ds.shape[0]
                    timestamp_ds.resize((current_len + samples_to_append,))
                    start_time = current_len / self._sampling_rate_hz
                    end_time = (current_len + samples_to_append) / self._sampling_rate_hz
                    timestamp_ds[current_len:] = np.linspace(
                        start_time,
                        end_time,
                        num=samples_to_append,
                        endpoint=False,
                    )

        except (ImportError, KeyError):
            pass

    def _finalize_hdf5(self, file_path: Path, duration: float) -> int:
        """Write remaining metadata (duration, markers) and return file size."""
        try:
            h5py = _load_h5py()

            with h5py.File(str(file_path), "a") as f:
                f.attrs["duration_seconds"] = duration

                # Event markers
                marker_grp = f["markers"] if "markers" in f else f.create_group("markers")
                marker_timestamps = marker_grp["timestamps"]
                marker_labels = marker_grp["labels"]
                marker_timestamps.resize((len(self._markers),))
                marker_labels.resize((len(self._markers),))

                if self._markers:
                    marker_timestamps[:] = [m.timestamp_seconds for m in self._markers]
                    marker_labels[:] = [m.label for m in self._markers]

                # Spikes are small enough to write at the end for now
                spike_grp = f["spikes"] if "spikes" in f else f.create_group("spikes")
                for child_name in list(spike_grp.keys()):
                    del spike_grp[child_name]

                if self._spike_buffer:
                    for i, batch in enumerate(self._spike_buffer):
                        batch_grp = spike_grp.create_group(f"batch_{i}")
                        batch_grp.attrs["method"] = batch.get("method", "unknown")
                        for ch, train in enumerate(batch.get("spike_trains", [])):
                            batch_grp.create_dataset(
                                f"ch_{ch}",
                                data=np.array(train, dtype=np.float64),
                            )

            return file_path.stat().st_size

        except ImportError:
            # Fallback for systems without h5py
            if not file_path.exists() or file_path.stat().st_size == 0:
                file_path.write_text(f"session={self._session_id},duration={duration}")
            return file_path.stat().st_size


# ---------------------------------------------------------------------------
# Module-level singleton
# ---------------------------------------------------------------------------
recording_service = RecordingService()
