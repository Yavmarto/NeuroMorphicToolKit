"""Export router -- export spike-encoded data in various formats."""

import importlib
import io
import json
from pathlib import Path
from typing import Any, Literal, cast

import numpy as np
from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from ..schemas.encoding import EncodingConfig, encoding_config_from_mapping
from ..services.session_artifact import load_artifact_data
from ..storage import default_recordings_dir

router = APIRouter()

_RECORDINGS_DIR = default_recordings_dir()


def _load_h5py() -> Any:
    """Load h5py lazily so type checking does not require third-party stubs."""
    return cast(Any, importlib.import_module("h5py"))


class ExportRequest(BaseModel):
    """Request body for the export endpoint."""

    session_id: str = Field(..., description="ID of the session to export.")
    format: Literal["hdf5", "csv", "aedat", "nir"] = Field(
        default="csv", description="Export file format."
    )
    encoding_config: EncodingConfig | None = Field(
        default=None,
        description="Encoding config override. If None, uses the session's original encoding.",
    )
    start_time: float | None = Field(
        default=None, description="Start time in seconds for windowed export."
    )
    end_time: float | None = Field(
        default=None, description="End time in seconds for windowed export."
    )


@router.post("")
async def export_data(
    request: Request, response: Response, export_request: ExportRequest
) -> StreamingResponse:
    """Export spike-encoded data from a recorded session.

    Supports HDF5, CSV, and AEDAT formats.  Optionally accepts a time
    window to export only a segment of the session.  The encoding
    configuration can be overridden to re-encode with different parameters.
    """
    # Sanitize session_id to prevent path traversal
    safe_session_id = "".join(
        c for c in export_request.session_id if c.isalnum() or c in ("_", "-")
    )
    if not safe_session_id or safe_session_id != export_request.session_id:
        raise HTTPException(status_code=400, detail="Invalid session ID.")
    session_file = _RECORDINGS_DIR / f"{safe_session_id}.hdf5"
    if not session_file.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Session '{export_request.session_id}' not found.",
        )

    # Load session data
    try:
        raw_data, timestamps, sampling_rate, metadata = _load_session_data(
            session_file, export_request.start_time, export_request.end_time
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to load session: {exc}")

    # Re-encode if custom config provided
    spike_data = None
    if export_request.encoding_config is not None:
        from typing import cast

        from ..services.spike_encoder import spike_encoder

        data_to_encode = cast(
            list[list[float]], raw_data.tolist() if hasattr(raw_data, "tolist") else raw_data
        )
        spike_data = spike_encoder.encode_batch(
            data=data_to_encode,
            config=export_request.encoding_config,
            sampling_rate=sampling_rate,
        )

    # Export in requested format
    if export_request.format == "csv":
        return _export_csv(spike_data, metadata, export_request.session_id)
    if export_request.format == "hdf5":
        return _export_hdf5(raw_data, timestamps, spike_data, metadata, export_request.session_id)
    if export_request.format == "aedat":
        return _export_aedat(spike_data, metadata, export_request.session_id)
    if export_request.format == "nir":
        config = export_request.encoding_config or encoding_config_from_mapping(
            metadata.get("encoding_config")
        )
        return _export_nir(config, export_request.session_id)
    raise HTTPException(status_code=400, detail=f"Unsupported format: {export_request.format}")


def _load_session_data(
    file_path: Path, start_time: float | None, end_time: float | None
) -> tuple[np.ndarray[Any, Any], np.ndarray[Any, Any] | None, float, dict[str, Any]]:
    """Load raw data from HDF5, optionally windowed."""
    try:
        raw, timestamps, metadata = load_artifact_data(
            file_path,
            start_time=start_time,
            end_time=end_time,
        )
        if raw is None:
            raw = np.array([[]])
        return raw, timestamps, float(metadata["sampling_rate_hz"]), metadata

    except ImportError:
        return np.array([[]]), None, 250.0, {}


def _export_csv(
    spike_data: dict[str, Any] | None, metadata: dict[str, Any], session_id: str
) -> StreamingResponse:
    """Export spike data as CSV (timestamp, channel, spike_time)."""
    lines = ["timestamp,channel,spike_time\n"]

    if spike_data and "spike_trains" in spike_data:
        for ch_idx, train in enumerate(spike_data["spike_trains"]):
            for spike_time in train:
                lines.append(f"{spike_time:.6f},{ch_idx},{spike_time:.6f}\n")

    content = "".join(lines)
    return StreamingResponse(
        io.BytesIO(content.encode("utf-8")),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={session_id}_spikes.csv"},
    )


def _export_hdf5(
    raw_data: np.ndarray[Any, Any],
    timestamps: np.ndarray[Any, Any] | None,
    spike_data: dict[str, Any] | None,
    metadata: dict[str, Any],
    session_id: str,
) -> StreamingResponse:
    """Export as HDF5 with raw data and spike trains."""
    try:
        h5py = _load_h5py()

        buf = io.BytesIO()
        with h5py.File(buf, "w") as f:
            for key, value in metadata.items():
                if value is None:
                    continue
                if isinstance(value, dict | list | tuple):
                    f.attrs[key] = json.dumps(value)
                elif isinstance(value, str | bytes | int | float | bool):
                    f.attrs[key] = value
                else:
                    f.attrs[key] = json.dumps(value)

            if hasattr(raw_data, "shape") and raw_data.size > 0:
                f.create_dataset("raw", data=raw_data, compression="gzip")
            if timestamps is not None and getattr(timestamps, "size", 0) > 0:
                f.create_dataset("timestamps", data=timestamps, compression="gzip")

            if spike_data and "spike_trains" in spike_data:
                spike_grp = f.create_group("spikes")
                spike_grp.attrs["method"] = spike_data.get("method", "unknown")
                for ch_idx, train in enumerate(spike_data["spike_trains"]):
                    spike_grp.create_dataset(
                        f"channel_{ch_idx}", data=np.array(train, dtype=np.float64)
                    )

        buf.seek(0)
        return StreamingResponse(
            buf,
            media_type="application/x-hdf5",
            headers={"Content-Disposition": f"attachment; filename={session_id}_export.hdf5"},
        )
    except ImportError:
        raise HTTPException(
            status_code=500,
            detail="h5py is required for HDF5 export but is not installed.",
        )


def _export_nir(config: EncodingConfig, session_id: str) -> StreamingResponse:
    """Export the model/encoding configuration as a NIR graph."""
    from ..services.nir_service import nir_service

    # Workspace models directory as required by the objective
    workspace_models_dir = Path("nmtk_workspace/models")
    workspace_models_dir.mkdir(parents=True, exist_ok=True)

    graph = nir_service.encoding_config_to_nir(config)

    # Save to the shared workspace directory
    nir_file = workspace_models_dir / f"{session_id}.nir"
    nir_service.write_nir(graph, str(nir_file))

    # Also return it for download via the API
    buf = io.BytesIO()
    nir_service.write_nir(graph, buf)
    buf.seek(0)

    return StreamingResponse(
        buf,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f"attachment; filename={session_id}.nir"},
    )


def _export_aedat(
    spike_data: dict[str, Any] | None, metadata: dict[str, Any], session_id: str
) -> StreamingResponse:
    """Export in AEDAT 2.0 format (address-event data).

    AEDAT format: each event is (timestamp_us: uint32, address: uint32).
    Channel index is used as the address.
    """
    import struct

    buf = io.BytesIO()

    # AEDAT 2.0 header
    header = b"#!AER-DAT2.0\r\n"
    header += f"# Session: {session_id}\r\n".encode("ascii")
    header += (
        f"# Method: {spike_data.get('method', 'unknown') if spike_data else 'unknown'}\r\n".encode(
            "ascii"
        )
    )
    header += b"#!END\r\n"
    buf.write(header)

    if spike_data and "spike_trains" in spike_data:
        for ch_idx, train in enumerate(spike_data["spike_trains"]):
            for spike_time in train:
                timestamp_us = int(spike_time * 1_000_000) & 0xFFFFFFFF
                address = ch_idx & 0xFFFFFFFF
                buf.write(struct.pack(">II", address, timestamp_us))

    buf.seek(0)
    return StreamingResponse(
        buf,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f"attachment; filename={session_id}_spikes.aedat"},
    )
