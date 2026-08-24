"""Authoritative Neurobench worker for execution and durable result state.

Serves the complete Neurobench API and owns execution plus durable state.

Default port: 8003 (kept for backward compat during transition).
Start with: uvicorn workers.neurobench_runner.main:app --port 8003

Suite API proxies the stable /api/neurobench/* and /bench/* paths here.
"""

import sys
from pathlib import Path

# Make neurobench 'app' package importable via sys.path
_NB_PATH = Path(__file__).parents[2] / "Neurobench" / "neurobench"
if str(_NB_PATH) not in sys.path:
    sys.path.insert(0, str(_NB_PATH))

# Reuse the owning application so execution, status, results, baselines, and
# reports all resolve against the same database and lifespan.
from app.main import app  # noqa: E402,F401
