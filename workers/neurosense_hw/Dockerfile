FROM python:3.11-slim
WORKDIR /repo

# Pre-install Neurosense deps before copying source — brainflow, scipy and h5py
# have C-extension wheels that take ~1-2 min; cached here, they only re-run
# when you deliberately bump a version in this RUN line.
RUN pip install --no-cache-dir \
    "fastapi>=0.111" \
    "uvicorn[standard]>=0.29" \
    "pydantic>=2" \
    "brainflow" \
    "scipy" \
    "h5py" \
    "nir>=1.0.0" \
    "python-multipart" \
    "slowapi>=0.1.9"

# WORKDIR is /repo so __file__ = /repo/workers/neurosense_hw/main.py
# and Path(__file__).parents[2] == /repo  ← required by main.py sys.path logic
COPY workers/neurosense_hw/ workers/neurosense_hw/
COPY Neurosense/ /repo/Neurosense/
RUN pip install --no-cache-dir /repo/Neurosense
CMD ["uvicorn", "workers.neurosense_hw.main:app", "--host", "0.0.0.0", "--port", "8004"]
