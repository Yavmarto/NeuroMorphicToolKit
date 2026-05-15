FROM python:3.11-slim

# Build context must be the repo root (see docker-compose.yml).
# suite_api imports neurocnl, neurohub, neurosense, and selected neurochip
# software routes directly,
# and accesses neurocnl/backend/ + neurocnl/neurosim/ + Neurobench/neurobench/
# via sys.path insertions in each domain's __init__.py.
WORKDIR /repo

# ── neurocnl: install package; backend/ and neurosim/ stay for sys.path access ──
COPY neurocnl/ neurocnl/
# Install torch CPU-only first so pip doesn't fetch the 2 GB CUDA wheel, which
# segfaults in memory-constrained Docker builds.  neurocnl[training] sees torch
# already satisfied and skips it.
RUN pip install --no-cache-dir \
    --index-url https://download.pytorch.org/whl/cpu \
    torch \
 && pip install --no-cache-dir snntorch \
 && pip install --no-cache-dir "neurocnl/[training]"

# ── Modules installed as top-level packages ───────────────────────────────────
COPY Neurohub/ Neurohub/
RUN pip install --no-cache-dir Neurohub/

COPY Neurosense/ Neurosense/
RUN pip install --no-cache-dir Neurosense/

COPY Neurochip/ Neurochip/
ENV PYTHONPATH="/repo/neurocnl:/repo/Neurochip"
RUN pip install --no-cache-dir jinja2

# ── Neurobench: no pyproject.toml — directory only, accessed via sys.path ─────
COPY Neurobench/neurobench/ Neurobench/neurobench/

# ── suite_api ─────────────────────────────────────────────────────────────────
COPY suite_api/ suite_api/
RUN pip install --no-cache-dir suite_api/

RUN addgroup --system app && adduser --system --ingroup app app
RUN mkdir -p /home/app/.cache && chown -R app:app /repo /home/app
ENV HOME=/home/app
ENV XDG_CACHE_HOME=/home/app/.cache
USER app
EXPOSE 9000
CMD ["uvicorn", "suite_api.main:app", "--host", "0.0.0.0", "--port", "9000"]
