# Stage 1: Install dependencies
FROM python:3.12.8-slim-bookworm AS builder

WORKDIR /app

# Neurohub depends on nmtk-contracts @ file:../nmtk_contracts
COPY nmtk_contracts/ /nmtk_contracts/
RUN pip install --no-cache-dir /nmtk_contracts

COPY Neurohub/pyproject.toml .
COPY Neurohub/neurohub/ neurohub/
# Default deployment uses the built-in SQLite fallback (no NEUROHUB_DB_URL
# set) — Neurohub holds no application data of its own, so no external
# database is required. Add the "[postgres]" extra back only if NEUROHUB_DB_URL
# is set to point at a real Postgres instance for the legacy routes.
RUN pip install --no-cache-dir .

# Stage 2: Runtime
FROM python:3.12.8-slim-bookworm

WORKDIR /app

RUN addgroup --system app && adduser --system --ingroup app app

COPY --from=builder --chown=app:app /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder --chown=app:app /usr/local/bin/uvicorn /usr/local/bin/uvicorn
COPY --from=builder --chown=app:app /usr/local/bin/alembic /usr/local/bin/alembic

COPY --chown=app:app Neurohub/neurohub/ neurohub/
COPY --chown=app:app Neurohub/alembic.ini .

USER app

# Number of Uvicorn workers (1-64); validated at startup by the app.
ENV UVICORN_WORKERS=1

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

EXPOSE 8000

CMD sh -c "alembic upgrade head && uvicorn neurohub.app.main:app --host 0.0.0.0 --port 8000 --workers ${UVICORN_WORKERS:-1}"
