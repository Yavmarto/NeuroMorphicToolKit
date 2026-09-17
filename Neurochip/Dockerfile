# Stage 1: Builder
FROM python:3.14-slim@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6 AS builder

WORKDIR /app

RUN pip install --no-cache-dir poetry

COPY Neurochip/pyproject.toml Neurochip/poetry.lock* /app/neurochip/
# Neurochip's pyproject declares nmtk_contracts as a ../nmtk_contracts path
# dependency; without it in the build context poetry warns and silently skips
# it, leaving `import nmtk_contracts` broken at runtime.
COPY nmtk_contracts/ /app/nmtk_contracts/

RUN cd neurochip && \
    poetry config virtualenvs.in-project true && \
    poetry install --no-root --without dev

# Stage 2: Final
FROM python:3.14-slim@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6 AS final

# Create a non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /app/neurochip/.venv /app/neurochip/.venv
ENV PATH="/app/neurochip/.venv/bin:$PATH"

COPY Neurochip/neurochip/ /app/neurochip/

# Change ownership of the app directory to the non-root user
RUN chown -R appuser:appgroup /app

# Switch to the non-root user
USER appuser

CMD ["uvicorn", "neurochip.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
