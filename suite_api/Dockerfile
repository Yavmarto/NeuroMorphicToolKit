FROM python:3.11-slim

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

# Copy source and install the package — heavy deps above already present
COPY neurocnl/ neurocnl/
RUN pip install --no-cache-dir "neurocnl/[training,rockpool,synsense,norse]" \
 && python -c "import nir; assert hasattr(nir, 'CubaLI'), 'nir>=1.0.5 required'; from neurocnl.runtime.sc_neurocore_simulator import sc_neurocore_nir_bridge_available; assert sc_neurocore_nir_bridge_available(), 'sc-neurocore NIR bridge missing'"

# ── Modules installed as top-level packages ───────────────────────────────────
COPY Neurohub/ Neurohub/
RUN pip install --no-cache-dir Neurohub/

# Neurosense: brainflow (~31MB) and scipy/h5py wheels — cache-stable before source copy
COPY docker/neurosense-pip-requirements.txt /tmp/neurosense-pip-requirements.txt
RUN pip install --no-cache-dir -r /tmp/neurosense-pip-requirements.txt

COPY Neurosense/ Neurosense/
RUN pip install --no-cache-dir --no-deps Neurosense/

COPY Neurochip/ Neurochip/
ENV PYTHONPATH="/repo/neurocnl:/repo/Neurochip"
# jinja2 is a dep of both Neurochip and suite_api — installed by those, not needed here

# ── Neurobench wrapper (declares neurocnl ^0.0.0 on PyPI — reinstall local) ───
COPY Neurobench/neurobench/ Neurobench/neurobench/
RUN pip install --no-cache-dir Neurobench/neurobench/ \
 && pip install --no-cache-dir --no-deps "neurocnl/[training,rockpool,synsense,norse]"

# ── suite_api ─────────────────────────────────────────────────────────────────
COPY suite_api/ suite_api/
RUN pip install --no-cache-dir suite_api/

RUN addgroup --system app && adduser --system --ingroup app app \
 && mkdir -p /home/app/.cache /home/app/data && chown -R app:app /home/app
# /repo is intentionally NOT chowned — all COPY'd and pip-installed files are
# 644/755 (world-readable) so the app user can read them without owning them.
# Chowning /repo recursively was walking thousands of inodes for no benefit.
ENV HOME=/home/app
ENV XDG_CACHE_HOME=/home/app/.cache
ENV NEUROCNL_DATA_DIR=/home/app/data
ENV NEUROHUB_DB_URL=sqlite:////home/app/data/neurohub.db
ENV NMTK_REPO_ROOT=/repo
USER app
EXPOSE 9000
CMD ["uvicorn", "suite_api.main:app", "--host", "0.0.0.0", "--port", "9000"]
