"""Utilities for consuming canonical NeuroSense HDF5 session artifacts."""

from __future__ import annotations

from pathlib import Path
from typing import Any

try:
    import h5py as h5py  # type: ignore  # noqa: PLC0414 - explicit re-export for strict mypy (implicit_reexport=False)
except ModuleNotFoundError:  # pragma: no cover - exercised by launcher preflight/imports
    h5py = None


def _decode_attr(value: object, default: str = "") -> str:
    if value is None:
        return default
    if isinstance(value, bytes):
        return value.decode("utf-8")
    return str(value)


def summarize_neurosense_artifact(file_path: str | Path) -> dict[str, Any]:
    """Load a compact summary of a canonical NeuroSense artifact."""
    if h5py is None:
        raise RuntimeError(
            "NeuroSense HDF5 artifact support requires the optional 'h5py' dependency."
        )

    artifact_path = Path(file_path)
    if not artifact_path.exists():
        raise FileNotFoundError(f"Session artifact not found: {artifact_path}")

    with h5py.File(artifact_path, "r") as artifact:
        schema_version = _decode_attr(artifact.attrs.get("artifact_schema_version"))
        if schema_version != "1.0":
            raise ValueError(
                f"Unsupported artifact schema version: '{schema_version}'. Expected '1.0'."
            )

        channels = int(artifact.attrs.get("channels", 0))
        timestamps = artifact["timestamps"][:] if "timestamps" in artifact else []
        raw = artifact["raw"][:] if "raw" in artifact else None
        filtered = artifact["filtered"][:] if "filtered" in artifact else None

        total_spike_events = 0
        spike_batches = 0
        if "spikes" in artifact:
            spike_group = artifact["spikes"]
            spike_batches = len(spike_group.keys())
            for batch_key in spike_group.keys():
                batch = spike_group[batch_key]
                for channel_index in range(channels):
                    channel_key = f"ch_{channel_index}"
                    if channel_key in batch:
                        total_spike_events += int(batch[channel_key].shape[0])

        return {
            "artifact_path": str(artifact_path),
            "session_id": _decode_attr(artifact.attrs.get("session_id")),
            "artifact_schema_version": schema_version,
            "device_type": _decode_attr(artifact.attrs.get("device_type")),
            "signal_type": _decode_attr(artifact.attrs.get("signal_type")),
            "capture_mode": _decode_attr(artifact.attrs.get("capture_mode")),
            "support_level": _decode_attr(artifact.attrs.get("support_level")),
            "channels": channels,
            "sampling_rate_hz": float(artifact.attrs.get("sampling_rate_hz", 0.0)),
            "duration_seconds": float(artifact.attrs.get("duration_seconds", 0.0)),
            "sample_count": int(raw.shape[1]) if raw is not None else len(timestamps),
            "filtered_available": filtered is not None,
            "timestamp_count": len(timestamps),
            "spike_batch_count": spike_batches,
            "spike_event_count": total_spike_events,
        }
