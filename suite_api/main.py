"""suite_api — unified NeuroMorphicToolKit backend.

Start with: uvicorn suite_api.main:app --port 9000 --reload
"""
from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

from fastapi import FastAPI
from suite_api.config import settings
from suite_api.middleware import attach_middleware
from suite_api.routers import health
from suite_api.domains.neurohub.lifespan import neurohub_startup, neurohub_shutdown


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    await neurohub_startup()
    yield
    await neurohub_shutdown()


app = FastAPI(
    title="NeuroMorphicToolKit Suite API",
    version="0.1.0",
    description="Unified backend for the NMTK suite.",
    lifespan=lifespan,
)

attach_middleware(app)

app.include_router(health.router, prefix="/api/suite", tags=["health"])

from suite_api.domains.neurocnl.router import router as neurocnl_router
app.include_router(neurocnl_router)

from suite_api.domains.neurosim.router import router as neurosim_router
app.include_router(neurosim_router)

from suite_api.domains.neurochip.router import router as neurochip_router
app.include_router(neurochip_router)

from suite_api.domains.neurobench.router import router as neurobench_router
app.include_router(neurobench_router)

from suite_api.domains.neurosense.router import router as neurosense_router
app.include_router(neurosense_router)

from suite_api.domains.neurohub.router import router as neurohub_router
app.include_router(neurohub_router)
