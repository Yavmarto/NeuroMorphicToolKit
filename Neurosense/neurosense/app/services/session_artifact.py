"""Shared helpers for NeuroSense recorded-session artifacts."""

from __future__ import annotations

import importlib
import json
from pathlib import Path
from typing import Any, cast

ARTIFACT_SCHEMA_VERSION = "1.0"
FLAGSHIP_WORKFLOW_ID = "forearm_emg_record_replay"
FLAGSHIP_WORKFLOW_LABEL = "2-channel forearm EMG -> filter -> spike encoding -> record -> replay"
FLAGSHIP_DEFAULT_PRESET_ID = "emg_prosthetic"


def _load_h5py() -> Any:
    """Load h5py lazily so type checking does not require third-party stubs."""
    return cast(Any, importlib.import_module("h5py"))


def decode_hdf5_value(value: Any, default: str = "") -> str:
    """Decode HDF5 attribute values into plain strings."""
    if value is None:
        return default
    if isinstance(value, bytes):
        return value.decode("utf-8")
    return str(value)


def deserialize_json_attr(value: Any, default: Any) -> Any:
    """Decode a JSON-serialized HDF5 attribute when present."""
    if value in (None, ""):
        return default

    raw_value = value.decode("utf-8") if isinstance(value, bytes) else str(value)

    try:
        return json.loads(raw_value)
    except json.JSONDecodeError:
        return default


def normalize_channel_labels(channel_labels: list[str] | None, channels: int) -> list[str]:
    """Return a stable channel-label list for recorded artifacts."""
    if channel_labels:
        return [str(label) for label in channel_labels[:channels]]
    return [f"Ch{i + 1}" for i in range(channels)]


def infer_capture_mode(device_type: str) -> str:
    """Infer capture mode from the active acquisition source."""
    return "synthetic" if device_type == "synthetic" else "live"


def infer_support_level(device_type: str, capture_mode: str) -> str:
    """Infer support level for the recorded acquisition path."""
    if capture_mode == "synthetic" or device_type == "synthetic":
        return "validated"
    if device_type in {"pynq", "prophesee"}:
        return "prototype"
    return "experimental"


def build_default_hardware_provenance(
    *,
    device_type: str,
    capture_mode: str,
    support_level: str,
    hardware_provenance: dict[str, Any] | None,
) -> dict[str, Any]:
    """Create canonical hardware provenance metadata."""
    provenance = dict(hardware_provenance or {})
    provenance.setdefault("device_type", device_type)
    provenance.setdefault("capture_mode", capture_mode)
    provenance.setdefault("support_level", support_level)

    if device_type == "cyton":
        provenance.setdefault("target_validation_board", "OpenBCI Cyton")
    elif device_type == "ganglion":
        provenance.setdefault("target_validation_board", "OpenBCI Ganglion")
    elif device_type == "synthetic":
        provenance.setdefault("board_family", "BrainFlow Synthetic Board")

    return provenance


def parse_markers(artifact_file: Any) -> list[dict[str, Any]]:
    """Load marker metadata from an HDF5 artifact."""
    if "markers" not in artifact_file:
        return []

    marker_group = artifact_file["markers"]
    if "timestamps" not in marker_group or "labels" not in marker_group:
        return []

    timestamps = marker_group["timestamps"][:]
    labels = [decode_hdf5_value(label) for label in marker_group["labels"][:]]
    return [
        {"timestamp_seconds": float(timestamp), "label": label}
        for timestamp, label in zip(timestamps, labels)
    ]


def load_artifact_metadata(file_path: Path) -> dict[str, Any]:
    """Load canonical metadata from a NeuroSense HDF5 artifact."""
    h5py = _load_h5py()

    with h5py.File(str(file_path), "r") as artifact:
        attrs = artifact.attrs
        device_type = decode_hdf5_value(attrs.get("device_type"), "unknown")
        channels = int(attrs.get("channels", 0))
        capture_mode = decode_hdf5_value(
            attrs.get("capture_mode"),
            infer_capture_mode(device_type),
        )
        support_level = decode_hdf5_value(
            attrs.get("support_level"),
            infer_support_level(device_type, capture_mode),
        )

        channel_labels = deserialize_json_attr(attrs.get("channel_labels"), None)
        encoding_config = deserialize_json_attr(
            attrs.get("encoding_config"),
            {"method": "rate", "rate_max_hz": 500.0},
        )
        hardware_provenance = build_default_hardware_provenance(
            device_type=device_type,
            capture_mode=capture_mode,
            support_level=support_level,
            hardware_provenance=deserialize_json_attr(attrs.get("hardware_provenance"), {}),
        )

        return {
            "artifact_schema_version": decode_hdf5_value(
                attrs.get("artifact_schema_version"),
                "legacy",
            ),
            "workflow_id": decode_hdf5_value(attrs.get("workflow_id"), FLAGSHIP_WORKFLOW_ID),
            "workflow_label": decode_hdf5_value(
                attrs.get("workflow_label"),
                FLAGSHIP_WORKFLOW_LABEL,
            ),
            "timestamp": decode_hdf5_value(attrs.get("timestamp")),
            "duration_seconds": float(attrs.get("duration_seconds", 0.0)),
            "device_type": device_type,
            "preset_id": decode_hdf5_value(attrs.get("preset_id"), FLAGSHIP_DEFAULT_PRESET_ID),
            "channels": channels,
            "sampling_rate_hz": int(attrs.get("sampling_rate_hz", 250)),
            "encoding_config": encoding_config,
            "event_markers": parse_markers(artifact),
            "file_path": str(file_path),
            "file_size_bytes": file_path.stat().st_size,
            "subject_id": decode_hdf5_value(attrs.get("subject_id")) or None,
            "signal_type": decode_hdf5_value(attrs.get("signal_type"), "unknown"),
            "capture_mode": capture_mode,
            "channel_labels": normalize_channel_labels(channel_labels, channels),
            "hardware_provenance": hardware_provenance,
            "support_level": support_level,
        }


def load_artifact_data(
    file_path: Path,
    *,
    start_time: float | None = None,
    end_time: float | None = None,
) -> tuple[Any, Any, dict[str, Any]]:
    """Load raw data, timestamps, and metadata from a session artifact."""
    h5py = _load_h5py()

    metadata = load_artifact_metadata(file_path)
    with h5py.File(str(file_path), "r") as artifact:
        raw = artifact["raw"][:] if "raw" in artifact else None
        filtered = artifact["filtered"][:] if "filtered" in artifact else None
        timestamps = artifact["timestamps"][:] if "timestamps" in artifact else None

        data = raw if raw is not None else filtered
        if data is None:
            return None, timestamps, metadata

        if timestamps is not None and timestamps.size:
            start_idx = 0
            end_idx = timestamps.shape[0]

            if start_time is not None:
                start_idx = int((timestamps < start_time).sum())
            if end_time is not None:
                end_idx = int((timestamps <= end_time).sum())

            data = data[:, start_idx:end_idx]
            timestamps = timestamps[start_idx:end_idx]
        else:
            sampling_rate = float(metadata["sampling_rate_hz"])
            start_idx = int((start_time or 0.0) * sampling_rate)
            end_idx = int(end_time * sampling_rate) if end_time is not None else data.shape[1]
            data = data[:, start_idx:end_idx]

        return data, timestamps, metadata


def load_spike_summary(file_path: Path) -> dict[str, Any]:
    """Return a compact summary of canonical spike batches in an artifact."""
    h5py = _load_h5py()

    metadata = load_artifact_metadata(file_path)
    channels = int(metadata["channels"])
    batches: list[dict[str, Any]] = []
    total_spike_events = 0

    with h5py.File(str(file_path), "r") as artifact:
        if "spikes" not in artifact:
            return {
                "batch_count": 0,
                "total_spike_events": 0,
                "batches": [],
            }

        spike_group = artifact["spikes"]
        for batch_key in sorted(spike_group.keys()):
            batch = spike_group[batch_key]
            per_channel_counts: list[int] = []
            for channel_index in range(channels):
                channel_key = f"ch_{channel_index}"
                spike_count = int(batch[channel_key].shape[0]) if channel_key in batch else 0
                per_channel_counts.append(spike_count)

            batch_total = sum(per_channel_counts)
            total_spike_events += batch_total
            batches.append(
                {
                    "batch_id": batch_key,
                    "method": decode_hdf5_value(batch.attrs.get("method"), "unknown"),
                    "per_channel_counts": per_channel_counts,
                    "total_spikes": batch_total,
                }
            )

    return {
        "batch_count": len(batches),
        "total_spike_events": total_spike_events,
        "batches": batches,
    }
