FROM python:3.14-slim
WORKDIR /app

# Pre-install Neurochip base deps before copying source — cache survives
# all source edits; only re-runs when you bump versions here.
RUN pip install --no-cache-dir \
    "fastapi[standard]>=0.111" \
    "uvicorn[standard]>=0.29" \
    "pydantic>=2" \
    "python-multipart>=0.0.22" \
    "jinja2>=3.1" \
    "pyserial>=3.5" \
    "slowapi>=0.1.9" \
    "prometheus-client>=0.19.0"

COPY nmtk/__init__.py /repo/nmtk/__init__.py
COPY nmtk/metrics_core.py /repo/nmtk/metrics_core.py
COPY nmtk/http_metrics.py /repo/nmtk/http_metrics.py
COPY workers/neurochip_hw/ /app/
COPY Neurochip/ /repo/Neurochip/
# Neurochip's pyproject declares nmtk_contracts as a ../nmtk_contracts path
# dependency; without it present in the build context `pip install /repo/Neurochip`
# fails to resolve the dependency.
COPY nmtk_contracts/ /repo/nmtk_contracts/
RUN pip install --no-cache-dir /repo/Neurochip

ENV PYTHONPATH="/repo:/app/Neurochip"

RUN groupadd --system appgroup && useradd --system --gid appgroup appuser \
 && mkdir -p /app/data \
 && chown -R appuser:appgroup /app /repo
USER appuser

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8002"]
