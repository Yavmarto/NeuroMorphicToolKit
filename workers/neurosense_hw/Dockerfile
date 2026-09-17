FROM python:3.11-slim

ENV PIP_DEFAULT_TIMEOUT=300
ENV PIP_RETRIES=5

WORKDIR /repo

# Pre-install Neurosense deps before copying source — brainflow, scipy and h5py
# have large wheels; cached here, they only re-run when requirements change.
COPY docker/neurosense-pip-requirements.txt /tmp/neurosense-pip-requirements.txt
RUN pip install --no-cache-dir -r /tmp/neurosense-pip-requirements.txt \
 && pip install --no-cache-dir prometheus-client

# Neurosense depends on nmtk-contracts @ file:../nmtk_contracts — a relative
# `file:` URL is invalid per PEP 508 and pip rejects it outright, so install
# it from source first (name resolves as already-satisfied below).
COPY nmtk_contracts/ /repo/nmtk_contracts/
RUN pip install --no-cache-dir /repo/nmtk_contracts

# WORKDIR is /repo so __file__ = /repo/workers/neurosense_hw/main.py
# and Path(__file__).parents[2] == /repo  ← required by main.py sys.path logic
COPY workers/neurosense_hw/ workers/neurosense_hw/
COPY nmtk/__init__.py nmtk/__init__.py
COPY nmtk/metrics_core.py nmtk/metrics_core.py
COPY nmtk/http_metrics.py nmtk/http_metrics.py
COPY Neurosense/ /repo/Neurosense/
RUN pip install --no-cache-dir --no-build-isolation --no-deps /repo/Neurosense

RUN groupadd --system appgroup && useradd --system --gid appgroup appuser \
 && chown -R appuser:appgroup /repo
USER appuser

EXPOSE 8004

CMD ["uvicorn", "workers.neurosense_hw.main:app", "--host", "0.0.0.0", "--port", "8004"]
