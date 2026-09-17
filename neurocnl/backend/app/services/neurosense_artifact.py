"""Helpers for preparing NeuroSense artifacts for NeuroCNL replay workflows."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import h5py


def _decode_attr(value: Any, default: str = "") -> str:
    if value is None:
        return default
    if isinstance(value, bytes):
        return value.decode("utf-8")
    return str(value)


def prepare_neurosense_replay(
    artifact_path: str | Path,
    *,
    start_time_seconds: float | None = None,
    end_time_seconds: float | None = None,
    preview_frames: int = 5,
) -> dict[str, Any]:
    """Prepare a canonical NeuroSense artifact as NeuroCNL-compatible EMG frames."""
    path = Path(artifact_path)
    if not path.exists():
        raise FileNotFoundError(f"Session artifact not found: {path}")

    with h5py.File(path, "r") as artifact:
        schema_version = _decode_attr(artifact.attrs.get("artifact_schema_version"))
        if schema_version != "1.0":
            raise ValueError(
                f"Unsupported artifact schema version: '{schema_version}'. Expected '1.0'."
            )

        raw = artifact["raw"][:]
        timestamps = artifact["timestamps"][:] if "timestamps" in artifact else None
        channels = int(artifact.attrs.get("channels", raw.shape[0]))
        sampling_rate_hz = float(artifact.attrs.get("sampling_rate_hz", 0.0))

        if timestamps is not None and len(timestamps) > 0:
            start_idx = int((timestamps < (start_time_seconds or 0.0)).sum())
            end_idx = (
                int((timestamps <= end_time_seconds).sum())
                if end_time_seconds is not None
                else len(timestamps)
            )
            sliced_raw = raw[:, start_idx:end_idx]
            sliced_timestamps = timestamps[start_idx:end_idx]
        else:
            start_idx = int((start_time_seconds or 0.0) * sampling_rate_hz)
            end_idx = (
                int(end_time_seconds * sampling_rate_hz)
                if end_time_seconds is not None
                else raw.shape[1]
            )
            sliced_raw = raw[:, start_idx:end_idx]
            sliced_timestamps = [index / sampling_rate_hz for index in range(start_idx, end_idx)]

        spike_batch_count = 0
        total_spike_events = 0
        if "spikes" in artifact:
            spike_group = artifact["spikes"]
            spike_batch_count = len(spike_group.keys())
            for batch_key in spike_group.keys():
                batch = spike_group[batch_key]
                for channel_index in range(channels):
                    channel_key = f"ch_{channel_index}"
                    if channel_key in batch:
                        total_spike_events += int(batch[channel_key].shape[0])

        frame_preview = []
        for frame_index in range(min(preview_frames, sliced_raw.shape[1])):
            frame_preview.append(
                {
                    "timestamp": float(sliced_timestamps[frame_index]),
                    "emg_channels": [
                        float(sliced_raw[channel_index, frame_index])
                        for channel_index in range(channels)
                    ],
                }
            )

        return {
            "artifact_path": str(path),
            "session_id": _decode_attr(artifact.attrs.get("session_id")),
            "artifact_schema_version": schema_version,
            "device_type": _decode_attr(artifact.attrs.get("device_type")),
            "signal_type": _decode_attr(artifact.attrs.get("signal_type")),
            "capture_mode": _decode_attr(artifact.attrs.get("capture_mode")),
            "support_level": _decode_attr(artifact.attrs.get("support_level")),
            "channels": channels,
            "sampling_rate_hz": sampling_rate_hz,
            "frame_count": int(sliced_raw.shape[1]),
            "preview_frames": frame_preview,
            "spike_batch_count": spike_batch_count,
            "spike_event_count": total_spike_events,
        }
