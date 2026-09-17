FROM python:3.14.7-slim-bookworm

ENV PIP_DEFAULT_TIMEOUT=300
ENV PIP_RETRIES=5

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create a non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Shared contracts package imported by neurosense.app.schemas.runtime
COPY nmtk_contracts/ /nmtk_contracts/
RUN pip install --no-cache-dir /nmtk_contracts

# Build context: repo root (see Neurosense/docker-compose.yml).
COPY docker/neurosense-pip-requirements.txt /tmp/neurosense-pip-requirements.txt
RUN pip install --no-cache-dir -r /tmp/neurosense-pip-requirements.txt

COPY --chown=appuser:appgroup Neurosense/pyproject.toml Neurosense/README.md ./
COPY --chown=appuser:appgroup Neurosense/neurosense/ ./neurosense/

RUN pip install --no-cache-dir --no-deps .

# Switch to the non-root user
USER appuser

EXPOSE 8000

CMD ["uvicorn", "neurosense.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
