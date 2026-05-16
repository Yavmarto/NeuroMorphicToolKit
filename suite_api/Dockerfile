FROM python:3.11-slim

# Build context must be the repo root (see docker-compose.yml).
# suite_api imports neurocnl, neurohub, neurosense, and selected neurochip
# software routes directly,
# and accesses neurocnl/backend/ + neurocnl/neurosim/ + Neurobench/neurobench/
# via sys.path insertions in each domain's __init__.py.
WORKDIR /repo

# ── neurocnl: heavy deps BEFORE source copy ───────────────────────────────────
# Installing torch and snntorch before any COPY keeps this layer cache-stable
# across all source edits. Previously COPY neurocnl/ appeared first, so any
# .py change busted the cache and forced a full ~10-minute reinstall every
# deploy. Now that only happens when you deliberately change torch/snntorch
# versions in this RUN line.
RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch \
 && pip install --no-cache-dir snntorch

# Copy source and install the package — torch already present so pip skips it
COPY neurocnl/ neurocnl/
RUN pip install --no-cache-dir "neurocnl/[training]"

# ── Modules installed as top-level packages ───────────────────────────────────
COPY Neurohub/ Neurohub/
RUN pip install --no-cache-dir Neurohub/

COPY Neurosense/ Neurosense/
RUN pip install --no-cache-dir Neurosense/

COPY Neurochip/ Neurochip/
ENV PYTHONPATH="/repo/neurocnl:/repo/Neurochip"
# jinja2 is a dep of both Neurochip and suite_api — installed by those, not needed here

# ── Neurobench: no pyproject.toml — directory only, accessed via sys.path ─────
COPY Neurobench/neurobench/ Neurobench/neurobench/

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
USER app
EXPOSE 9000
CMD ["uvicorn", "suite_api.main:app", "--host", "0.0.0.0", "--port", "9000"]
