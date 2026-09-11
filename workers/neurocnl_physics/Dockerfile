FROM python:3.11-slim
WORKDIR /repo

# Pre-install all deps before copying source — mujoco was already here (correct).
# Adding neurocnl's base deps means this whole layer is cache-stable across
# neurocnl source edits; only the cheap final install re-runs on source changes.
RUN pip install --no-cache-dir \
    "fastapi>=0.109.0" \
    "uvicorn[standard]>=0.27.0" \
    "mujoco" \
    "nengo>=3.2.0" \
    "numpy>=1.24.0" \
    "pydantic>=2.5.0" \
    "sse-starlette>=1.8.0" \
    "slowapi>=0.1.9" \
    "nir>=1.0.0" \
    "structlog>=24.1.0" \
    "prometheus-client>=0.19.0" \
    "aiosqlite>=0.20.0" \
    "sqlalchemy[asyncio]>=2.0.0" \
    "watchdog>=3.0"

# WORKDIR is /repo so __file__ = /repo/workers/neurocnl_physics/main.py
# and Path(__file__).parents[2] == /repo  ← required by main.py sys.path logic
WORKDIR /repo
COPY workers/neurocnl_physics/ workers/neurocnl_physics/
COPY neurocnl/ /repo/neurocnl/
RUN pip install --no-cache-dir --no-deps /repo/neurocnl

# job_store writes jobs.db here; /repo is mounted :ro at runtime
ENV NEUROCNL_DATA_DIR=/tmp

RUN groupadd --system appgroup && useradd --system --gid appgroup appuser \
 && chown -R appuser:appgroup /repo
USER appuser

CMD ["uvicorn", "workers.neurocnl_physics.main:app", "--host", "0.0.0.0", "--port", "8006"]
