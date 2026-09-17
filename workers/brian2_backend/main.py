"""Isolated Brian2 runtime worker for NeuroCNL simulator dispatch."""

from __future__ import annotations

import importlib.util
import logging
from pathlib import Path

from fastapi import APIRouter, Body, FastAPI, HTTPException


def _load_brian2_runtime() -> object:
    # ponytail: file import avoids neurocnl/__init__.py, which pulls nengo and other
    # training-stack deps this worker image deliberately omits (--no-deps install).
    runtime_path = (
        Path(__file__).resolve().parents[2]
        / "neurocnl"
        / "neurocnl"
        / "converter"
        / "brian2_runtime.py"
    )
    spec = importlib.util.spec_from_file_location("_brian2_runtime_isolated", runtime_path)
    if spec is None or spec.loader is None or not runtime_path.is_file():
        raise ImportError(f"Brian2 runtime module missing at {runtime_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_runtime = _load_brian2_runtime()
Brian2Backend = _runtime.Brian2Backend
Brian2BackendError = _runtime.Brian2BackendError

from nmtk.http_metrics import attach_fastapi_metrics

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/neurocnl/brian2", tags=["brian2"])
backend = Brian2Backend()

app = FastAPI(
    title="Brian2 Backend Worker",
    version="0.1.0",
    description="Isolated Brian2 simulator worker for NeuroCNL runtime requests.",
)
attach_fastapi_metrics(app)
app.include_router(router)


@router.post("/compile")
def compile_network(payload: dict[str, object] = Body(...)) -> dict[str, object]:
    network = payload.get("network")
    if not isinstance(network, dict):
        raise HTTPException(status_code=422, detail="Request body must include a network object.")
    try:
        session_id = backend.compile(network)
    except Brian2BackendError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"status": "compiled", "session_id": session_id}


@router.post("/run")
def run_network(payload: dict[str, object] = Body(...)) -> dict[str, object]:
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id.strip():
        raise HTTPException(status_code=422, detail="session_id is required.")
    steps = payload.get("steps", 100)
    try:
        steps_int = int(steps)
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=422, detail="steps must be an integer.") from exc
    try:
        return backend.run(session_id, steps=steps_int)
    except Brian2BackendError as exc:
        message = str(exc)
        status_code = 404 if "invalid session" in message.lower() else 422
        raise HTTPException(status_code=status_code, detail=message) from exc


@app.get("/health")
async def health() -> dict[str, object]:
    brian2_importable = importlib.util.find_spec("brian2") is not None
    return {
        "status": "ok",
        "service": "brian2-backend",
        "brian2_importable": brian2_importable,
    }
