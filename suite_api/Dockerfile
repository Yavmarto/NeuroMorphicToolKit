FROM python:3.11-slim

# Build context must be the repo root (see docker-compose.yml).
# suite_api imports neurocnl, neurohub, neurosense, neurochip directly,
# and accesses neurocnl/backend/ + neurocnl/neurosim/ + Neurobench/neurobench/
# via sys.path insertions in each domain's __init__.py.
WORKDIR /repo

# ── neurocnl: install package; backend/ and neurosim/ stay for sys.path access ──
COPY neurocnl/ neurocnl/
RUN pip install --no-cache-dir neurocnl/

# ── Modules installed as top-level packages ───────────────────────────────────
COPY Neurohub/ Neurohub/
RUN pip install --no-cache-dir Neurohub/

COPY Neurosense/ Neurosense/
RUN pip install --no-cache-dir Neurosense/

COPY Neurochip/ Neurochip/
RUN pip install --no-cache-dir Neurochip/

# ── Neurobench: no pyproject.toml — directory only, accessed via sys.path ─────
COPY Neurobench/neurobench/ Neurobench/neurobench/

# ── suite_api ─────────────────────────────────────────────────────────────────
COPY suite_api/ suite_api/
RUN pip install --no-cache-dir suite_api/

RUN addgroup --system app && adduser --system --ingroup app app
RUN chown -R app:app /repo
USER app
EXPOSE 9000
CMD ["uvicorn", "suite_api.main:app", "--host", "0.0.0.0", "--port", "9000"]
