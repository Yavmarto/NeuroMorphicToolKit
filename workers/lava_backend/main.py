"""Dedicated Lava runtime worker.

This isolates the Python 3.10 + lava-nc runtime from the main Neurochip
service while preserving the existing Neurochip Lava HTTP contract.
"""

from __future__ import annotations

from fastapi import FastAPI

from neurochip.app.routers import lava

app = FastAPI(
    title="Lava Backend Worker",
    version="0.1.0",
    description="Isolated Lava simulator worker for Neurochip runtime requests.",
)
app.include_router(lava.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "lava-backend"}
