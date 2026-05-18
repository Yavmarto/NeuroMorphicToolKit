FROM python:3.11-slim
WORKDIR /repo
ARG NEUROBENCH_INSTALL_TARGET="Neurobench/neurobench"

# Pre-install heavy deps before copying source — nengo, numpy, scipy,
# matplotlib and pandas are large C-extension wheels (200 MB+ combined)
# that take 2-3 min to install. Keeping them above COPY means this layer
# is cache-stable across all Neurobench source edits.
RUN pip install --no-cache-dir \
    "fastapi>=0.109.0" \
    "uvicorn[standard]>=0.27.0" \
    "pydantic>=2.0.0" \
    "pydantic-settings>=2.0.0" \
    "nengo>=4.1.0" \
    "numpy>=2.0.0" \
    "scipy>=1.15.0" \
    "matplotlib>=3.10.0" \
    "pandas>=3.0.0" \
    "slowapi>=0.1.9" \
    "jinja2>=3.1.0" \
    "httpx>=0.27.0"

# WORKDIR is /repo so __file__ = /repo/workers/neurobench_runner/main.py
# and Path(__file__).parents[2] == /repo  ← required by main.py sys.path logic
# Default image installs the core wrapper only. Pass
# --build-arg NEUROBENCH_INSTALL_TARGET='Neurobench/neurobench[executor]'
# to opt into upstream NeuroBench executor dependencies.
COPY workers/neurobench_runner/ workers/neurobench_runner/
COPY Neurobench/neurobench/ Neurobench/neurobench/
RUN pip install --no-cache-dir "${NEUROBENCH_INSTALL_TARGET}"
CMD ["uvicorn", "workers.neurobench_runner.main:app", "--host", "0.0.0.0", "--port", "8003"]
