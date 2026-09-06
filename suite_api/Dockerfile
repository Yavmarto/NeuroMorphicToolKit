FROM python:3.12-slim

ENV PIP_DEFAULT_TIMEOUT=300
ENV PIP_RETRIES=5

# Build context must be the repo root (see docker-compose.yml).
# suite_api imports neurocnl, neurohub, neurosense, and selected neurochip
# software routes directly,
# and accesses neurocnl/backend/ + neurocnl/neurosim/ + Neurobench/neurobench/
# via sys.path insertions in each domain's __init__.py.
WORKDIR /repo

# ── neurocnl: heavy deps BEFORE source copy ───────────────────────────────────
# Installing torch and the SNN framework stack before any COPY keeps these
# layers cache-stable across all source edits.  Only rebuild when you
# deliberately bump a version in this RUN block.
RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch \
 && pip install --no-cache-dir \
    "nir>=1.0.5" \
    snntorch \
    "sc-neurocore>=3.13.0,<4" \
    rockpool \
    sinabs \
    norse

# Copy the shared custom-node SDK alongside NeuroCNL.  NeuroSim imports this
# package directly at runtime, while keeping it at the repo root lets the
# launcher and third-party custom nodes use the same public contract.
COPY nmtk_sdk/ nmtk_sdk/

# Copy source and install the package — heavy deps above already present
COPY neurocnl/ neurocnl/
# neurocnl depends on nmtk-contracts by name only (a relative `file:` URL
# requirement is invalid per PEP 508 and pip rejects it outright). Install it
# from source first so the name resolves as already-satisfied below.
COPY nmtk_contracts/ nmtk_contracts/
RUN ln -s /repo/nmtk_contracts /nmtk_contracts \
 && pip install --no-cache-dir /repo/nmtk_contracts
RUN pip install --no-cache-dir "./neurocnl[training,studio,rockpool,synsense,norse]" \
 && python -c "import nir; assert hasattr(nir, 'CubaLI'), 'nir>=1.0.5 required'; from neurocnl.runtime.sc_neurocore_simulator import sc_neurocore_nir_bridge_available; assert sc_neurocore_nir_bridge_available(), 'sc-neurocore NIR bridge missing'; import os; os._exit(0)"

# ── Modules installed as top-level packages ───────────────────────────────────
COPY Neurohub/ Neurohub/
RUN pip install --no-cache-dir Neurohub/

# Neurosense: brainflow (~31MB) and scipy/h5py wheels — cache-stable before source copy
COPY docker/neurosense-pip-requirements.txt /tmp/neurosense-pip-requirements.txt
RUN pip install --no-cache-dir -r /tmp/neurosense-pip-requirements.txt

COPY Neurosense/ Neurosense/
RUN pip install --no-cache-dir --no-build-isolation --no-deps Neurosense/

COPY Neurochip/ Neurochip/
ENV PYTHONPATH="/repo/neurocnl:/repo/Neurochip"
# jinja2 is a dep of both Neurochip and suite_api — installed by those, not needed here

# ── Neurobench wrapper (uses the local, pinned workspace NeuroCNL package) ────
COPY Neurobench/neurobench/ Neurobench/neurobench/
RUN pip install --no-cache-dir Neurobench/neurobench/ \
 && pip install --no-cache-dir --no-deps "./neurocnl[training,studio,rockpool,synsense,norse]"

# ── suite_api ─────────────────────────────────────────────────────────────────
COPY suite_api/ suite_api/
RUN pip install --no-cache-dir suite_api/ \
 && python -c "import suite_api.main"

RUN addgroup --system app && adduser --system --ingroup app app \
 && mkdir -p /home/app/.cache /home/app/data /home/app/notebooks && chown -R app:app /home/app
# /repo is intentionally NOT chowned — all COPY'd and pip-installed files are
# 644/755 (world-readable) so the app user can read them without owning them.
# Chowning /repo recursively was walking thousands of inodes for no benefit.
ENV HOME=/home/app
ENV XDG_CACHE_HOME=/home/app/.cache
ENV NMTK_REPO_ROOT=/repo
# Stamped by .github/workflows/release-docker.yml so the running stack can
# report which release it is (GET /api/suite/health). The default is what an
# unstamped local/source build reports, and the app treats it as "not a
# release" — i.e. never offer an in-app update against it.
# Declared last so a version bump doesn't invalidate any earlier build layer.
ARG NMTK_VERSION=dev
ENV NMTK_VERSION=$NMTK_VERSION
USER app
EXPOSE 9000
CMD ["uvicorn", "suite_api.main:app", "--host", "0.0.0.0", "--port", "9000"]
