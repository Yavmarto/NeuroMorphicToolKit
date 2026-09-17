"""POST /api/nir/inspect — inspect a .nir (HDF5) file and return its tree."""

from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Annotated, Any

import h5py
import numpy as np
from fastapi import APIRouter, File, HTTPException, UploadFile

router = APIRouter()


def _walk_hdf5(item: h5py.Group | h5py.Dataset, name: str) -> dict[str, Any]:
    """Recursively build a JSON-serialisable tree node from an HDF5 item."""
    if isinstance(item, h5py.Group):
        return {
            "name": name,
            "type": "group",
            "attrs": _serialise_attrs(item.attrs),
            "children": [_walk_hdf5(item[k], k) for k in item],
        }

    # Dataset
    preview: list[Any] | None = None
    try:
        data = item[()]  # type: ignore[index]
        flat = np.ravel(data)
        # ponytail: prioritize non-zeros so sparse arrays don't look empty
        non_zeros = flat[flat != 0] if flat.dtype.kind in "bcifu" else flat
        preview = non_zeros.tolist()[:16] if non_zeros.size > 0 else flat.tolist()[:16]
    except Exception:  # noqa: BLE001
        preview = None

    return {
        "name": name,
        "type": "dataset",
        "shape": list(item.shape),
        "dtype": str(item.dtype),
        "attrs": _serialise_attrs(item.attrs),
        "preview": preview,
        "children": [],
    }


def _serialise_attrs(attrs: h5py.AttributeManager) -> dict[str, Any]:
    """Convert HDF5 attributes to plain Python types."""
    result: dict[str, Any] = {}
    for key, value in attrs.items():
        try:
            if isinstance(value, np.ndarray):
                result[key] = value.tolist()
            elif isinstance(value, np.generic):
                result[key] = value.item()
            elif isinstance(value, bytes):
                result[key] = value.decode("utf-8", errors="replace")
            else:
                result[key] = value
        except Exception:  # noqa: BLE001
            result[key] = str(value)
    return result


@router.post("/nir/inspect")
async def inspect_nir(file: Annotated[UploadFile, File()]) -> dict[str, Any]:
    """Inspect a .nir file (HDF5 format) and return its full group/dataset tree."""
    filename = file.filename or ""
    if not filename.endswith(".nir"):
        raise HTTPException(status_code=400, detail="Only .nir files are accepted.")

    contents = await file.read()

    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as tmp:
            tmp.write(contents)
            tmp_path = Path(tmp.name)

        with h5py.File(tmp_path, "r") as f:
            root: dict[str, Any] = {
                "name": "/",
                "type": "group",
                "attrs": _serialise_attrs(f.attrs),
                "children": [_walk_hdf5(f[k], k) for k in f],
            }

        return {
            "file_name": filename,
            "file_size_bytes": len(contents),
            "root": root,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Failed to parse HDF5 file: {exc}") from exc
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)
