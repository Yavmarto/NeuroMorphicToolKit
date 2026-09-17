import logging
import os
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.auth import get_api_key
from app.logging_config import request_id_ctx
from app.routers import (
    baselines,
    benchmarks,
    comparison,
    faults,
    perturbation,
    pynq,
    regression,
    reports,
    results,
    runner,
    snn_mlir,
    spinnaker2,
    synsense,
)
from app.schemas.common import HealthResponse, healthy_response
from app.services.result_store import result_store
from app.services.seed_published_results import seed_published_results
from nmtk.http_metrics import attach_fastapi_metrics

logger = logging.getLogger(__name__)


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    seed_published_results(result_store)
    yield


app = FastAPI(title="NeuroBench API", version="0.1.0", lifespan=_lifespan)
attach_fastapi_metrics(app)

# CORS configuration — matches pattern used by Neurochip / neurocnl
_allowed_origins_str = os.getenv("ALLOWED_ORIGINS", "*")
_origins: list[str] = [o.strip() for o in _allowed_origins_str.split(",") if o.strip()]
_allow_credentials = "*" not in _origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)
if "*" in _origins:
    logger.warning(
        "cors_open_to_all_origins: CORS is open to all origins. Set ALLOWED_ORIGINS for production."
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> Response:
    """Catch-all handler: log full traceback and return structured JSON 500."""
    import traceback

    from fastapi.responses import JSONResponse

    logger.error("Unhandled exception: %s\n%s", str(exc), traceback.format_exc())
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})


@app.middleware("http")
async def add_request_id_and_log_request(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    """Middleware to add request ID and log request details.

    Args:
        request (Request): The incoming request.
        call_next (Callable[[Request], Awaitable[Response]]): The next middleware in the chain.

    Returns:
        Response: The outgoing response.
    """
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    request.state.request_id = request_id
    token = request_id_ctx.set(request_id)

    try:
        start_time = time.time()
        response = await call_next(request)
        duration = time.time() - start_time

        response.headers["X-Request-ID"] = request_id

        logger.info(
            "API Request: %s %s - %d",
            request.method,
            request.url.path,
            response.status_code,
            extra={
                "method": request.method,
                "path": request.url.path,
                "status_code": response.status_code,
                "duration_seconds": duration,
            },
        )

        return response
    finally:
        request_id_ctx.reset(token)


app.include_router(
    benchmarks.router,
    prefix="/api/neurobench/benchmarks",
    tags=["benchmarks"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    runner.router,
    prefix="/api/neurobench/run",
    tags=["run"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    synsense.router,
    prefix="/bench/synsense",
    tags=["synsense"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    comparison.router,
    prefix="/api/neurobench/compare",
    tags=["compare"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    faults.router,
    prefix="/api/neurobench/faults",
    tags=["faults"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    perturbation.router,
    prefix="/api/neurobench/perturbation",
    tags=["perturbation"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    baselines.router,
    prefix="/api/neurobench/baselines",
    tags=["baselines"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    results.router,
    prefix="/api/neurobench/results",
    tags=["results"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    regression.router,
    prefix="/api/neurobench/regression",
    tags=["regression"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    reports.router,
    prefix="/api/neurobench/report",
    tags=["report"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    spinnaker2.router,
    prefix="/bench/spinnaker2",
    tags=["spinnaker2"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    pynq.router,
    prefix="/api/neurobench/pynq",
    tags=["pynq"],
    dependencies=[Depends(get_api_key)],
)
app.include_router(
    snn_mlir.router,
    prefix="/api/neurobench/snn_mlir",
    tags=["snn_mlir"],
    dependencies=[Depends(get_api_key)],
)


@app.get("/health", response_model=HealthResponse)
def health_check(request: Request, response: Response) -> HealthResponse:
    """Health check endpoint for the NeuroBench API.

    Returns:
        dict[str, str]: A dictionary indicating the service status.
    """
    return healthy_response()


# Serve Flutter web frontend at / (must be after all API routes)
_frontend_dir = Path(__file__).resolve().parent.parent.parent / "frontend" / "build" / "web"
if _frontend_dir.is_dir():
    app.mount("/", StaticFiles(directory=str(_frontend_dir), html=True), name="frontend")
