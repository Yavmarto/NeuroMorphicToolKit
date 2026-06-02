FROM python:3.11-slim

ENV PIP_DEFAULT_TIMEOUT=300
ENV PIP_RETRIES=5

WORKDIR /repo

# Pre-install Neurosense deps before copying source — brainflow, scipy and h5py
# have large wheels; cached here, they only re-run when requirements change.
COPY docker/neurosense-pip-requirements.txt /tmp/neurosense-pip-requirements.txt
RUN pip install --no-cache-dir -r /tmp/neurosense-pip-requirements.txt

# WORKDIR is /repo so __file__ = /repo/workers/neurosense_hw/main.py
# and Path(__file__).parents[2] == /repo  ← required by main.py sys.path logic
COPY workers/neurosense_hw/ workers/neurosense_hw/
COPY Neurosense/ /repo/Neurosense/
RUN pip install --no-cache-dir /repo/Neurosense
CMD ["uvicorn", "workers.neurosense_hw.main:app", "--host", "0.0.0.0", "--port", "8004"]
