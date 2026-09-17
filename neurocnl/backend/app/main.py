"""neurocnl Studio — FastAPI backend.

Wraps the neurocnl library with a REST API used by the Flutter web frontend.
"""

import asyncio
import os
import shutil
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from datetime import UTC
from pathlib import Path

import structlog
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from backend.app.middleware.auth import APIKeyMiddleware
from backend.app.middleware.metrics import PrometheusMiddleware
from backend.app.middleware.rate_limit import limiter
from backend.app.middleware.request_id import RequestIDMiddleware
from backend.app.middleware.response_time import ResponseTimeMiddleware
from backend.app.routers import (
    datasets,
    deploy,
    deploy_targets,
    export,
    generate,
    jobs,
    kernel_runner,
    neurosim_handoff,
    nir_inspect,
    notebook,
    parse,
    simulate,
    simulators,
    target_reachability,
    templates,
    training,
    validate,
    workspaces,
)
from backend.app.routers.prosthetic import analysis as prosthetic_analysis
from backend.app.routers.prosthetic import export as prosthetic_export
from backend.app.routers.prosthetic import hardware as prosthetic_hardware
from backend.app.routers.prosthetic import simulate as prosthetic_sim
from backend.app.routers.prosthetic import sleep as prosthetic_sleep
from backend.app.schemas.runtime import HealthResponse
from neurocnl.logging_config import setup_logging
from neurosim.app.routers import components as sim_components
from neurosim.app.routers import export as sim_export
from neurosim.app.routers import generation as sim_generation
from neurosim.app.routers import nir_canvas as sim_nir_canvas
from neurosim.app.routers import preview as sim_preview
from neurosim.app.routers import projects as sim_projects
from neurosim.app.routers import simulation_ws as sim_ws
from neurosim.app.routers import spinnaker2 as sim_spinnaker2
from neurosim.app.routers import sweep as sim_sweep
from neurosim.app.routers.custom_nodes import router as sim_custom_nodes_router
from neurosim.app.routers.templates import router as sim_templates_router
from neurosim.app.routers.validation import router as sim_validation_router
from neurosim.app.services.components import load_components, shutdown_component_watcher
from neurosim.app.services.project_store import ProjectStore

setup_logging()

logger = structlog.get_logger(__name__)


async def _job_cleanup_task() -> None:
    """Background task to clean up old jobs every hour."""
    from backend.app.services.job_store import job_store

    while True:
        try:
            # Clean up jobs older than 24h
            await job_store.cleanup_expired_jobs(86400)
        except Exception as e:
            logger.error("job_cleanup_error", error=str(e))
        await asyncio.sleep(3600)  # Sleep for 1 hour


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None, None]:
    # Startup: import neurocnl eagerly so first request is fast
    import neurocnl  # noqa: F401
    import neurosim as _neurosim_pkg
    from backend.app.services.dataset_cache import dataset_cache
    from backend.app.services.job_store import job_store
    from backend.app.services.workspace_store import workspace_store

    resolved_neurosim_path = str(Path(_neurosim_pkg.__file__).resolve())
    expected_neurosim_root = str(
        (Path(__file__).resolve().parents[2] / "neurosim").resolve()
    )
    logger.info("neurosim_package_resolved", path=resolved_neurosim_path)
    if not resolved_neurosim_path.startswith(expected_neurosim_root):
        logger.warning(
            "neurosim_unexpected_package_path",
            resolved=resolved_neurosim_path,
            expected_prefix=expected_neurosim_root,
        )

    # Production-safety checks — warn operators about insecure defaults
    if "*" in cors_allowed_origins:
        logger.warning(
            "cors_open_to_all_origins",
            message=(
                "CORS is open to all origins. Set CORS_ALLOWED_ORIGINS for production deployments."
            ),
        )
    if os.getenv("AUTH_ENABLED", "").lower() not in {"true", "1", "yes"}:
        logger.warning(
            "auth_disabled",
            message=(
                "API key authentication is disabled. "
                "Set AUTH_ENABLED=true for production deployments."
            ),
        )

    # Pre-warm the Nengo decoder cache so the first preview request isn't slower
    from neurosim.app.services.preview_runner import ensure_nengo_runtime_cache

    ensure_nengo_runtime_cache()

    # Initialize persistent job store and dataset cache registry
    await job_store.initialize()
    await dataset_cache.initialize()
    await workspace_store.initialize()
    await ProjectStore.initialize()

    # Recover any jobs left in 'running' state from a previous crash
    recovered = await job_store.recover_stale_running_jobs()
    if recovered:
        logger.info("startup_recovered_orphaned_jobs", count=recovered)

    # Start cleanup task
    cleanup_task = asyncio.create_task(_job_cleanup_task())

    yield

    # Shutdown: drain active jobs, then cancel cleanup task
    cancelled = await job_store.drain()
    if cancelled:
        logger.warning("shutdown_cancelled_active_jobs", count=cancelled)
    cleanup_task.cancel()
    await ProjectStore.close()
    shutdown_component_watcher()


app = FastAPI(
    title="neurocnl Studio API",
    version="0.3.0",
    description="""
REST API wrapping the neurocnl controlled natural language library.

This API provides endpoints for parsing, validating, and simulating neuromorphic networks
defined using Controlled Natural Language (CNL).

[Full Documentation](/documentation)
""",
    lifespan=lifespan,
    docs_url=None,  # Custom docs URL
)


@app.get("/docs", include_in_schema=False)
async def custom_swagger_ui_html() -> HTMLResponse:
    """Customized Swagger UI for neurocnl branding."""
    return get_swagger_ui_html(
        openapi_url=app.openapi_url or "/openapi.json",
        title=f"{app.title} - API Documentation",
        oauth2_redirect_url=app.swagger_ui_oauth2_redirect_url,
        swagger_js_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js",
        swagger_css_url="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css",
    )


# Rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Prometheus metrics middleware
app.add_middleware(PrometheusMiddleware)
app.add_middleware(SlowAPIMiddleware)

# Request ID middleware — must be added before CORS
app.add_middleware(RequestIDMiddleware)
app.add_middleware(ResponseTimeMiddleware)

# Auth middleware — must be added before CORS
app.add_middleware(APIKeyMiddleware)

# CORS — restrict to allowed origins
cors_allowed_origins = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ALLOWED_ORIGINS", os.getenv("ALLOWED_ORIGINS", "*")
    ).split(",")
    if origin.strip()
]

# Starlette prevents allow_credentials=True if allow_origins=["*"]
allow_credentials = "*" not in cors_allowed_origins

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_allowed_origins,
    allow_credentials=allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount routers
app.include_router(parse.router, prefix="/api", tags=["parse"])
app.include_router(validate.router, prefix="/api", tags=["validate"])
app.include_router(generate.router, prefix="/api", tags=["generate"])
app.include_router(simulate.router, prefix="/api", tags=["simulate"])
app.include_router(simulators.router, prefix="/api", tags=["simulators"])
app.include_router(templates.router, prefix="/api", tags=["templates"])
app.include_router(datasets.router, prefix="/api", tags=["datasets"])
app.include_router(export.router, prefix="/api", tags=["export"])
app.include_router(deploy.router, prefix="/api", tags=["deploy"])
app.include_router(deploy_targets.router, prefix="/api", tags=["deploy-targets"])
app.include_router(jobs.router, prefix="/api", tags=["jobs"])
app.include_router(workspaces.router, prefix="/api", tags=["workspaces"])
app.include_router(neurosim_handoff.router, prefix="/api", tags=["handoff"])
app.include_router(notebook.router, prefix="/api")
app.include_router(prosthetic_sim.router, prefix="/api/prosthetic", tags=["prosthetic"])
app.include_router(
    prosthetic_sleep.router, prefix="/api/prosthetic", tags=["prosthetic"]
)
app.include_router(
    prosthetic_export.router, prefix="/api/prosthetic", tags=["prosthetic"]
)
app.include_router(
    prosthetic_analysis.router, prefix="/api/prosthetic", tags=["prosthetic"]
)
app.include_router(
    prosthetic_hardware.router, prefix="/api/prosthetic", tags=["prosthetic"]
)
app.include_router(training.router, prefix="/api", tags=["training"])
app.include_router(nir_inspect.router, prefix="/api", tags=["nir"])
app.include_router(target_reachability.router, prefix="/api", tags=["targets"])
app.include_router(kernel_runner.router, prefix="/api")
app.include_router(sim_components.router)
app.include_router(sim_export.router)
app.include_router(sim_generation.router)
app.include_router(sim_nir_canvas.router)
app.include_router(sim_preview.router)
app.include_router(sim_projects.router)
app.include_router(sim_ws.router)
app.include_router(sim_spinnaker2.router)
app.include_router(sim_sweep.router)
app.include_router(sim_templates_router)
app.include_router(sim_validation_router)
app.include_router(sim_custom_nodes_router)


@app.get("/metrics")
async def metrics():
    """Exposes Prometheus metrics."""
    from fastapi import Response
    from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/health", response_model=HealthResponse)
@limiter.limit("60/minute")
async def health_check(request: Request, response: Response) -> HealthResponse:
    """Reports health and module readiness (nengo, mujoco, etc).

    This handler intentionally stays module-specific rather than calling the
    shared :func:`healthy_response` helper: it is a rich readiness probe the
    launcher's ``HealthStatus`` model consumes (module availability, disk
    usage, canvas store/component state), not a trivial ``{status: "ok"}``
    ping. Its response schema still derives from the shared
    ``HealthResponse`` contract.
    """
    from datetime import datetime

    import neurocnl

    disk_usage = shutil.disk_usage(Path.cwd())
    total_gb = round(disk_usage.total / (1024**3), 2)
    used_gb = round((disk_usage.total - disk_usage.free) / (1024**3), 2)
    free_gb = round(disk_usage.free / (1024**3), 2)

    result: dict = {
        "status": "ok",
        "neurocnl_version": neurocnl.__version__,
        "timestamp": datetime.now(UTC).isoformat(),
        "modules": {},
        "disk": {
            "total_gb": total_gb,
            "used_gb": used_gb,
            "free_gb": free_gb,
            "low_space": free_gb < 5,
        },
        "canvas_store": await ProjectStore.get_default().ping(),
        "canvas_components": len(load_components()) > 0,
    }

    # Helper to check module availability
    def check_module(name: str, import_name: str | None = None) -> None:
        import importlib

        try:
            mod = importlib.import_module(import_name or name)
            result["modules"][name] = {
                "available": True,
                "version": getattr(mod, "__version__", "unknown"),
            }
        except ImportError:
            result["modules"][name] = {"available": False}

    # Core dependencies
    check_module("nengo")

    # If core dependencies are missing, status is degraded
    if not result["modules"]["nengo"]["available"]:
        result["status"] = "degraded"

    # Optional but important dependencies
    check_module("nengo_loihi")
    check_module("mujoco")
    check_module("neuroml")
    check_module("pyneuroml")
    check_module("neurodreamhand")

    # Legacy flat keys for backward compatibility (optional, but good for now)
    result["nengo_version"] = result["modules"]["nengo"].get("version")
    result["nengo_available"] = result["modules"]["nengo"]["available"]
    result["mujoco_available"] = result["modules"]["mujoco"]["available"]
    result["mujoco_version"] = result["modules"]["mujoco"].get("version")

    from fastapi.responses import JSONResponse

    if result["status"] == "degraded":
        return JSONResponse(
            content=HealthResponse(**result).model_dump(),
            status_code=503,
        )
    return HealthResponse(**result)


# Serve static documentation
_docs_dir = Path(__file__).resolve().parent.parent.parent / "site"
if _docs_dir.is_dir():
    app.mount(
        "/documentation",
        StaticFiles(directory=str(_docs_dir), html=True),
        name="documentation",
    )

# Serve Flutter web frontend at / (must be after all API routes)
# neurocnl runs from neurocnl/ so frontend is at frontend/build/web
_frontend_dir = (
    Path(__file__).resolve().parent.parent.parent / "frontend" / "build" / "web"
)
if _frontend_dir.is_dir():
    app.mount(
        "/", StaticFiles(directory=str(_frontend_dir), html=True), name="frontend"
    )
else:

    @app.get("/", include_in_schema=False)
    @limiter.limit("60/minute")
    def read_root(request: Request, response: Response) -> dict[str, str]:
        return {
            "message": "NeuroStudio API (frontend not built — run flutter build web)"
        }
