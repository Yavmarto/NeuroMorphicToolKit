"""NIR router -- import NIR graphs and convert to EncodingConfig."""

from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import APIRouter, File, HTTPException, Request, Response, UploadFile

from ..schemas.encoding import EncodingConfig
from ..services.nir_service import nir_service

router = APIRouter()


@router.post("/import", response_model=EncodingConfig)
async def import_nir(
    request: Request, response: Response, file: UploadFile = File(...)
) -> EncodingConfig:
    """Import a NIR graph and convert it to an EncodingConfig.

    Accepts a .nir file (HDF5 format), parses it into a NIR graph,
    and attempts to map it to one of the supported spike encoding methods.
    """
    if not file.filename or not file.filename.endswith(".nir"):
        raise HTTPException(status_code=400, detail="Only .nir files are supported.")

    tmp_path: Path | None = None
    with NamedTemporaryFile(delete=False, suffix=".nir") as tmp:
        try:
            tmp.write(await file.read())
            tmp_path = Path(tmp.name)
        finally:
            file.file.close()

    try:
        graph = nir_service.read_nir(tmp_path)
        config = nir_service.nir_to_encoding_config(graph)
        return config
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to parse NIR file: {exc}")
    finally:
        if tmp_path is not None and tmp_path.exists():
            tmp_path.unlink()
