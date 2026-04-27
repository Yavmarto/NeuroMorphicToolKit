# Architecture Consolidation — Implementation Plan

**Source analysis**: `docs/architecture-consolidation-analysis.md`  
**Target**: Modular monolith — one suite backend (`suite_api/`), one suite frontend (`nmtk/`), optional hardware/compute workers, domain code as internal packages.

---

## How to read this plan

- Every step has an **Acceptance gate** — a command or check that must pass before the next step begins.
- Steps within one phase are sequential unless marked **[parallel-safe]**.
- No step deletes production code until Phase 5. All prior phases are additive or refactoring-in-place.
- When a step says "read `{Module}/AGENTS.md`" that instruction is mandatory before touching any file in that module.
- The symbol **⚠ submodule** marks steps that require a commit inside a git submodule (not the parent repo).

---

## Directory conventions used throughout this plan

```
REPO_ROOT = /Users/yoshimartodihardjo/NeuroMorphicToolKit
suite_api/          new unified FastAPI backend (created Phase 1)
workers/            optional isolated worker processes (created Phase 4)
nmtk/packages/      Flutter feature packages, one per domain (created Phase 3)
```

## Port table (current → target)

| Service | Current port | Target state |
|---|---|---|
| neurocnl | 8000 | Worker (Phase 4) then decommissioned (Phase 5) |
| Neurosim | 8001 | Worker (Phase 4) then decommissioned (Phase 5) |
| Neurochip | 8002 | Partial worker for hardware only (Phase 4) |
| Neurobench | 8003 | Worker for long-running jobs only (Phase 4) |
| Neurosense | 8004 | Worker for hardware I/O only (Phase 4) |
| Neurohub | 8005 | Absorbed into suite_api (Phase 2F) |
| suite_api | **9000** | Primary backend (created Phase 1) |
| neurocnl-physics | 8006 | Worker for MuJoCo simulation (Phase 4) |

---

## Repo structure

This is **not** a single monorepo. It is a **git submodule parent** (`Yavmarto/NeuroMorphicToolKit`) that references 7 independent sibling repositories.

```
github.com/Yavmarto/NeuroMorphicToolKit   ← parent repo (suite infra, docs, scripts, CI)
  .gitmodules references (relative URLs, sibling repos):
  github.com/Completed-Spoon-6/neurocnl
  github.com/Completed-Spoon-6/Neurosim
  github.com/Completed-Spoon-6/Neurochip
  github.com/Completed-Spoon-6/Neurobench
  github.com/Completed-Spoon-6/Neurosense
  github.com/Completed-Spoon-6/Neurohub
  github.com/Completed-Spoon-6/Neuro-Dream-Hand
```

Each submodule repo has its own git history, GitHub CI, issue tracker, and release pipeline. The parent repo **pins** each submodule to a specific commit hash via `.gitmodules` + the staged submodule pointer.

**Consequence for this migration**:

- `suite_api/`, `workers/`, `nmtk/packages/`, `docs/ADR-claude/`, `docker-compose.yml`, `Makefile`, and all root scripts live in the **parent repo** only.
- Steps marked **⚠ submodule** touch a submodule repo. That requires: (1) checkout inside the submodule directory on its own branch, (2) commit in the submodule repo, (3) push to the submodule's remote, (4) update the parent repo's submodule pointer commit, (5) push the updated pointer on the parent's branch.
- Phases 0, 1, 3, 4, and 5 work entirely in the parent repo. Only Phase 2 touches submodule repos.
- `Neuro-Dream-Hand` has no HTTP service and is not touched in any phase of this plan.

---

## Branching plan

### Parent repo — branch structure

Create one long-running integration branch (`consolidation`) off `main`. Every phase gets a short-lived sub-branch that merges back to `consolidation` when its acceptance gates pass. Only one PR ever touches `main`: the final merge at the end of Phase 5.

```
main
└── consolidation                          (created once, at start of Phase 0)
    ├── consolidation/phase-0              (baseline capture + scaffold)
    ├── consolidation/phase-1              (suite_api shell)
    ├── consolidation/phase-2a-neurocnl
    ├── consolidation/phase-2b-neurosim
    ├── consolidation/phase-2c-neurochip
    ├── consolidation/phase-2d-neurobench
    ├── consolidation/phase-2e-neurosense
    ├── consolidation/phase-2f-neurohub
    ├── consolidation/phase-3a-neurocnl
    ├── consolidation/phase-3b-neurosim
    ├── consolidation/phase-3c-neurochip
    ├── consolidation/phase-3d-neurobench
    ├── consolidation/phase-3e-neurosense
    ├── consolidation/phase-3f-neurohub
    ├── consolidation/phase-4-workers
    └── consolidation/phase-5-decommission
```

### Submodule repos — branch structure (Phase 2 only)

Create a `consolidation` branch in each submodule's own repo only when that module's Phase 2 sub-phase begins. The parent repo then pins the submodule pointer to the HEAD of this branch.

| Submodule repo | Branch to create | Phase that creates it |
|---|---|---|
| `Completed-Spoon-6/neurocnl` | `consolidation` | Phase 2A |
| `Completed-Spoon-6/Neurosim` | `consolidation` | Phase 2B |
| `Completed-Spoon-6/Neurochip` | `consolidation` | Phase 2C |
| `Completed-Spoon-6/Neurobench` | `consolidation` | Phase 2D |
| `Completed-Spoon-6/Neurosense` | `consolidation` | Phase 2E |
| `Completed-Spoon-6/Neurohub` | `consolidation` | Phase 2F |

### Auto-merge CI rules

The existing `.github/workflows/auto-merge-agents.yml` auto-merges only branches prefixed `jules/` or `auto/`. All `consolidation/*` branches use a different prefix, so **every consolidation PR requires explicit human approval**. This is intentional: consolidation PRs touch `docker-compose.yml`, `AGENTS.md`, `modules.json`, ADR files, and CI workflows — all protected files per the auto-merge workflow definition.

Do not rename consolidation branches to `jules/` or `auto/` to force auto-merge. These changes are too structural for automated merge.

### Commands — create branches

```bash
# Run once, before Phase 0:
git checkout main && git pull origin main
git checkout -b consolidation
git push -u origin consolidation

# Run at the start of each phase sub-branch:
git checkout consolidation
git checkout -b consolidation/phase-0   # replace with current phase name
```

### Commands — merge a completed phase back to consolidation

Run after all acceptance gates for that phase pass. Use `--no-ff` to preserve the phase boundary in git history.

```bash
git checkout consolidation
git merge --no-ff consolidation/phase-0 -m "Phase 0 complete: baseline capture and scaffold"
git push origin consolidation
git branch -d consolidation/phase-0
git push origin --delete consolidation/phase-0
```

### Commands — update submodule pointer (Phase 2 only)

```bash
# Inside the submodule directory:
cd {submodule-dir}
git checkout -b consolidation
git add -A
git commit -m "Phase 2X: prepare {module} as importable package for suite_api"
git push -u origin consolidation

# Back in parent repo, update the pinned pointer:
cd ..
git add {submodule-dir}
git commit -m "Pin {module} submodule to Phase 2X consolidation commit"
git push origin consolidation/phase-2x-{module}
```

### Tag strategy

Tag the parent repo after each phase's acceptance gates pass. These tags are rollback anchors.

```bash
git tag consolidation-phase-0-done && git push origin consolidation-phase-0-done
git tag consolidation-phase-1-done && git push origin consolidation-phase-1-done
# ... repeat for each phase
```

To roll back to a phase boundary: `git checkout consolidation-phase-N-done`

---

## Phase 0 — Baseline capture and directory scaffold

**Goal**: Lock observable behavior before any change. Create empty directories and skeleton files. Zero runtime behavior changes.

---

### Step 0.1 — Capture OpenAPI contracts for all six backends

**Read before running**: `docs/agents/nmtk-backend-smoke.md`

Start all six backends locally or via Docker, then run:

```bash
python3 scripts/backend_endpoint_smoke.py --all --output-dir docs/api/contracts/
```

If `--output-dir` is not a supported flag, run the script once per module using the ports defined in `.env` or `Makefile` and redirect stdout to:

```
docs/api/contracts/neurocnl-openapi.json
docs/api/contracts/neurosim-openapi.json
docs/api/contracts/neurochip-openapi.json
docs/api/contracts/neurobench-openapi.json
docs/api/contracts/neurosense-openapi.json
docs/api/contracts/neurohub-openapi.json
```

These files become read-only reference contracts for Phase 2 route parity checks. Do not modify them after capture.

**Acceptance gate**: All six JSON files exist under `docs/api/contracts/` and each contains a top-level `"openapi"` key. Verify with:

```bash
python3 -c "
import json, sys, pathlib
for p in pathlib.Path('docs/api/contracts').glob('*-openapi.json'):
    d = json.loads(p.read_text())
    assert 'openapi' in d, f'missing openapi key in {p}'
    print(f'OK {p.name}')
"
```

---

### Step 0.2 — Add health regression test

Create `tests/integration/test_phase0_health_baseline.py` with the following content:

```python
"""Baseline health check for all six module backends.
These tests must pass before any migration step in Phase 1+.
Run with: python3 -m pytest tests/integration/test_phase0_health_baseline.py -v
"""
import httpx
import pytest

HEALTH_ENDPOINTS = [
    ("neurocnl",   "http://localhost:8000/health"),
    ("neurosim",   "http://localhost:8001/health"),
    ("neurochip",  "http://localhost:8002/health"),
    ("neurobench", "http://localhost:8003/health"),
    ("neurosense", "http://localhost:8004/health"),
    ("neurohub",   "http://localhost:8005/api/neurohub/health"),
]

@pytest.mark.parametrize("name,url", HEALTH_ENDPOINTS)
def test_module_health(name: str, url: str) -> None:
    response = httpx.get(url, timeout=5.0)
    assert response.status_code == 200, (
        f"{name} health check failed: {response.status_code} {response.text}"
    )
```

**Acceptance gate**:

```bash
python3 -m pytest tests/integration/test_phase0_health_baseline.py -v
```

All six tests pass. (Requires backends running. Skip with `pytest --ignore=tests/integration` during development when backends are offline, but this gate must pass before any Phase 2 step begins.)

---

### Step 0.3 — Create suite_api directory scaffold

Create the following empty files (content added in Phase 1):

```
suite_api/
suite_api/__init__.py              (empty)
suite_api/main.py                  (stub, see Step 1.1)
suite_api/config.py                (stub, see Step 1.2)
suite_api/middleware/
suite_api/middleware/__init__.py   (empty)
suite_api/domains/
suite_api/domains/__init__.py      (empty)
suite_api/routers/
suite_api/routers/__init__.py      (empty)
suite_api/pyproject.toml           (stub, see Step 1.1)
```

Run `mkdir -p suite_api/middleware suite_api/domains suite_api/routers` then create each `__init__.py` as an empty file.

**Acceptance gate**: `ls suite_api/` shows `__init__.py  config.py  domains  main.py  middleware  pyproject.toml  routers`

---

### Step 0.4 — Create workers directory scaffold

```
workers/
workers/README.md     (see content below)
```

Content for `workers/README.md`:

```markdown
# Workers

Optional isolated processes for hardware I/O and long-running compute.
Each worker is a standalone FastAPI or CLI service started only when its
hardware or heavy dependency is present.

Workers are created in Phase 4 of the consolidation plan.
```

**Acceptance gate**: `ls workers/` shows `README.md`

---

### Step 0.5 — Create nmtk/packages directory scaffold

Read `nmtk/AGENTS.md` before creating anything under `nmtk/`.

```
nmtk/packages/
nmtk/packages/README.md     (see content below)
```

Content for `nmtk/packages/README.md`:

```markdown
# nmtk/packages

Flutter feature packages, one per domain.
Each package replaces a WebView-hosted web frontend with a native Flutter
screen living inside the unified launcher app.

Feature packages are created in Phase 3 of the consolidation plan.
```

**Acceptance gate**: `ls nmtk/packages/` shows `README.md`

---

### Step 0.6 — Tag Phase 0 and capture to OpenBrain

```bash
git tag consolidation-phase-0-done
git push origin consolidation-phase-0-done
```

Then capture the following thought to OpenBrain memory using the `mcp__open-brain__capture_thought` tool with this exact content:

> NMTK architecture consolidation started (Phase 0 complete). Target: migrate from module-as-app (7 FastAPI services + 6 Flutter web frontends + WebView launcher) to module-as-domain (suite_api on port 9000, one Flutter desktop app, optional hardware workers). Contract snapshots saved to docs/api/contracts/. Repo is a git submodule parent (Yavmarto/NeuroMorphicToolKit) with 7 sibling submodule repos under Completed-Spoon-6. Long-running integration branch: consolidation. Source analysis: docs/architecture-consolidation-analysis.md.

---

## Phase 1 — Unified backend shell

**Goal**: A working `suite_api` FastAPI application on port 9000 with shared infrastructure (middleware, config, health aggregation). All six existing services remain running and unchanged. No tests break.

---

### Step 1.1 — Create suite_api pyproject.toml and main.py

Create `suite_api/pyproject.toml`:

```toml
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.backends.legacy:build"

[project]
name = "suite-api"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.111",
    "uvicorn[standard]>=0.29",
    "httpx>=0.27",
    "pydantic>=2.7",
    "pydantic-settings>=2.2",
    "slowapi>=0.1.9",
    "python-json-logger>=2.0",
]

[tool.setuptools.packages.find]
where = ["."]
include = ["suite_api*"]
```

Create `suite_api/main.py`:

```python
"""suite_api — unified NeuroMorphicToolKit backend.

Start with: uvicorn suite_api.main:app --port 9000 --reload
"""
from fastapi import FastAPI
from suite_api.config import settings
from suite_api.middleware import attach_middleware
from suite_api.routers import health

app = FastAPI(
    title="NeuroMorphicToolKit Suite API",
    version="0.1.0",
    description="Unified backend for the NMTK suite.",
)

attach_middleware(app)

app.include_router(health.router, prefix="/api/suite", tags=["health"])
```

**Acceptance gate**:

```bash
cd /Users/yoshimartodihardjo/NeuroMorphicToolKit
pip install -e suite_api/ --quiet
python3 -c "from suite_api.main import app; print('import OK')"
```

---

### Step 1.2 — Create suite_api/config.py

Create `suite_api/config.py`:

```python
"""Centralised configuration for suite_api.
All values are read from environment variables with safe defaults.
"""
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Suite API
    suite_api_port: int = 9000

    # Module backend URLs (used by health aggregator and proxy fallback)
    neurocnl_url: str = "http://localhost:8000"
    neurosim_url: str = "http://localhost:8001"
    neurochip_url: str = "http://localhost:8002"
    neurobench_url: str = "http://localhost:8003"
    neurosense_url: str = "http://localhost:8004"
    neurohub_url: str = "http://localhost:8005"

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
```

**Acceptance gate**:

```bash
python3 -c "from suite_api.config import settings; print(settings.neurocnl_url)"
```

Prints `http://localhost:8000`.

---

### Step 1.3 — Create suite_api/middleware/__init__.py

Create `suite_api/middleware/__init__.py`:

```python
"""Shared middleware for suite_api.
Attach all middleware through the single attach_middleware() function.
"""
import uuid
import time
import logging

from fastapi import FastAPI, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("suite_api")


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response


class ResponseTimeMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        start = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = (time.perf_counter() - start) * 1000
        response.headers["X-Response-Time-Ms"] = f"{elapsed_ms:.2f}"
        return response


def attach_middleware(app: FastAPI) -> None:
    app.add_middleware(RequestIdMiddleware)
    app.add_middleware(ResponseTimeMiddleware)
```

**Acceptance gate**: `python3 -c "from suite_api.middleware import attach_middleware; print('OK')"` exits 0.

---

### Step 1.4 — Create suite_api/routers/health.py

Create `suite_api/routers/health.py`:

```python
"""Health aggregation endpoint.
GET /api/suite/health  — suite_api's own health.
GET /api/suite/health/modules — aggregated health of all module backends.
"""
import asyncio
import time
from typing import Any

import httpx
from fastapi import APIRouter

from suite_api.config import settings

router = APIRouter()

MODULE_URLS: dict[str, str] = {
    "neurocnl":   f"{settings.neurocnl_url}/health",
    "neurosim":   f"{settings.neurosim_url}/health",
    "neurochip":  f"{settings.neurochip_url}/health",
    "neurobench": f"{settings.neurobench_url}/health",
    "neurosense": f"{settings.neurosense_url}/health",
    "neurohub":   f"{settings.neurohub_url}/api/neurohub/health",
}


@router.get("/health")
async def suite_health() -> dict[str, str]:
    return {"status": "ok", "service": "suite_api"}


@router.get("/health/modules")
async def modules_health() -> dict[str, Any]:
    async def probe(name: str, url: str) -> tuple[str, dict[str, Any]]:
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(url)
            status = "online" if resp.status_code == 200 else "degraded"
            error = None if resp.status_code == 200 else resp.text
        except Exception as exc:
            status = "offline"
            error = str(exc)
        response_time_ms = (time.perf_counter() - start) * 1000
        return name, {
            "status": status,
            "response_time_ms": round(response_time_ms, 2),
            "error": error,
        }

    results = await asyncio.gather(
        *(probe(name, url) for name, url in MODULE_URLS.items())
    )
    return {"suite_api": "ok", "modules": dict(results)}
```

**Acceptance gate**: Start suite_api with `uvicorn suite_api.main:app --port 9000` and run:

```bash
curl -s http://localhost:9000/api/suite/health | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['status']=='ok', d"
echo "health OK"
```

---

### Step 1.5 — Add suite_api to docker-compose.yml

Add the following service block to `docker-compose.yml` immediately before the `prometheus:` service. The suite_api service depends on all six module services being healthy.

```yaml
  suite_api:
    build:
      context: ./suite_api
      dockerfile: Dockerfile
    ports:
      - "${SUITE_API_PORT:-9000}:9000"
    environment:
      - PYTHONUNBUFFERED=1
      - NEUROCNL_URL=http://neurocnl:8000
      - NEUROSIM_URL=http://neurosim:8000
      - NEUROCHIP_URL=http://neurochip:8000
      - NEUROBENCH_URL=http://neurobench:8000
      - NEUROSENSE_URL=http://neurosense:8000
      - NEUROHUB_URL=http://neurohub:8000
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:9000/api/suite/health')"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - backend-net
      - monitoring-net
    depends_on:
      neurocnl:
        condition: service_healthy
      neurosim:
        condition: service_healthy
      neurochip:
        condition: service_healthy
```

Create `suite_api/Dockerfile`:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .
COPY . .
CMD ["uvicorn", "suite_api.main:app", "--host", "0.0.0.0", "--port", "9000"]
```

Also add `SUITE_API_PORT=9000` to `.env` and `.env.example`.

**Acceptance gate**:

```bash
python3 scripts/validate_docker_compose.sh
```

Exits 0. Then:

```bash
docker compose config --quiet
```

Exits 0.

---

### Step 1.6 — Add suite_api entry to Makefile

In `Makefile`, add `suite_api` to relevant targets. In the `MODULES` line, do **not** add suite_api (it has no Flutter frontend). Instead add a new target:

```makefile
suite_api_dev:
	uvicorn suite_api.main:app --port 9000 --reload
```

Add `suite_api_dev` to the `help` target's usage section.

**Acceptance gate**: `make help` prints a line mentioning `suite_api_dev`.

---

### Step 1.7 — Add Phase 1 smoke test

Create `tests/integration/test_phase1_suite_api.py`:

```python
"""suite_api smoke tests — Phase 1.
Run with: python3 -m pytest tests/integration/test_phase1_suite_api.py -v
Requires suite_api running on port 9000.
"""
import httpx
import pytest

SUITE_BASE = "http://localhost:9000"


def test_suite_health() -> None:
    r = httpx.get(f"{SUITE_BASE}/api/suite/health", timeout=5)
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_modules_health_endpoint_exists() -> None:
    r = httpx.get(f"{SUITE_BASE}/api/suite/health/modules", timeout=10)
    assert r.status_code == 200
    body = r.json()
    assert "modules" in body
```

**Acceptance gate**:

```bash
python3 -m pytest tests/integration/test_phase1_suite_api.py -v
```

Both tests pass (requires suite_api running).

---

### Step 1.8 — Write ADR 0018 and capture to OpenBrain

#### ADR 0018

Create `docs/ADR-claude/0018-suite-api-unified-backend.md` with the following content:

```markdown
# ADR 0018: Suite API — Unified Backend

## Status
Accepted

## Context
ADRs 0009 and 0014 established fixed per-module ports (8000–8005) and
Docker Compose orchestration of six independent FastAPI services.
The architecture-consolidation-analysis.md (2026-04-27) concluded that
the suite behaves as one product with seven domains, not seven independent
services, and that the per-service split imposes duplicate middleware,
health checks, startup scripts, and cross-service HTTP hops without
providing true product independence.

## Decision
Consolidate all six FastAPI backends into a single `suite_api` application
served on port 9000. Each module's business logic is mounted as an internal
APIRouter under `/api/{module}/`. Optional workers (neurosense-hw, neurobench-
runner, neurochip-hw, neurocnl-physics) remain as isolated processes only
where justified by hardware requirements, long-running jobs, or heavy optional
dependencies (MuJoCo, BrainFlow, Akida, PYNQ).

## Consequences
- **Positive:** One API surface, one middleware stack, one startup command.
- **Positive:** Cross-module calls become in-process; no localhost HTTP hops for
  standard workflows.
- **Positive:** Neurohub's suite_client no longer needs to poll sibling services
  for routine orchestration.
- **Negative:** A bad change to suite_api has a larger blast radius than a
  change to one isolated service.
- **Negative:** Optional hardware dependencies still need careful isolation to
  prevent ImportError on machines without the hardware stack installed.
- **Supersedes:** ADR 0009 (Makefile Port Allocation) and ADR 0014
  (Docker Compose Orchestration) — those ADRs describe the old architecture;
  their port/service decisions are superseded by this ADR after Phase 5.
```

#### OpenBrain capture

Capture the following thought to OpenBrain using `mcp__open-brain__capture_thought`:

> NMTK consolidation Phase 1 complete: suite_api FastAPI backend is live on port 9000 alongside the existing six module services. ADR 0018 written — suite_api replaces the per-module backend architecture. Modules still running independently during migration phases 2–5.

Then tag:

```bash
git tag consolidation-phase-1-done
git push origin consolidation-phase-1-done
```

---

## Phase 2 — Domain migration (one sub-phase per module)

**Goal**: Move each module's API into suite_api as a mounted internal router. Replace cross-module HTTP calls inside Neurohub with direct in-process calls.

**Migration order** (dependency order, do not change):
1. neurocnl (no upstream dependencies within the suite)
2. Neurosim (consumes neurocnl exports)
3. Neurochip (consumes neurocnl exports)
4. Neurobench (consumes neurocnl exports)
5. Neurosense (most independent — hardware I/O, but depends on Neurohub project context)
6. Neurohub (orchestrates all others; migrated last)

**Pattern for every module** (steps A–F):

---

### Phase 2A — neurocnl ⚠ submodule

Read `neurocnl/AGENTS.md` and `CODING_STYLE_GUIDE.md` before touching any file in `neurocnl/`.

#### Step 2A.1 — Add neurocnl as an importable package ⚠ submodule

In `neurocnl/backend/pyproject.toml`, verify or add a `[project.name]` value of `neurocnl-backend`. Verify `[tool.setuptools.packages.find]` discovers the `app` package under `backend/`. If the `pyproject.toml` does not support direct import as `neurocnl_backend`, add:

```toml
[tool.setuptools.package-dir]
"neurocnl_backend" = "app"
```

This makes `import neurocnl_backend` available when the package is installed.

Install from parent repo:

```bash
pip install -e neurocnl/backend/ --quiet
python3 -c "import neurocnl_backend; print('neurocnl_backend importable')"
```

If the import fails, instead add `neurocnl/backend` to the Python path in `suite_api/domains/neurocnl/__init__.py` using:

```python
import sys
from pathlib import Path
_backend_path = Path(__file__).parents[3] / "neurocnl" / "backend"
if str(_backend_path) not in sys.path:
    sys.path.insert(0, str(_backend_path))
```

**Acceptance gate**: `python3 -c "import app.main"` succeeds when run from inside `neurocnl/backend/`, OR `python3 -c "import neurocnl_backend"` succeeds from `REPO_ROOT`.

#### Step 2A.2 — Mount neurocnl router in suite_api

Create `suite_api/domains/neurocnl/__init__.py` with the sys.path preamble from Step 2A.1 if needed.

Create `suite_api/domains/neurocnl/router.py`:

```python
"""Mount neurocnl domain routes in suite_api.
All routes are mounted under /api/neurocnl/.
"""
# Ensure neurocnl/backend is importable
from suite_api.domains.neurocnl import _ensure_path  # noqa: F401 (side-effect import)

from fastapi import APIRouter
from app.routers import (
    parse,
    validate,
    generate,
    simulate,
    export,
    deploy,
    jobs,
    neurosim_handoff,
    templates,
)

router = APIRouter(prefix="/api/neurocnl")

for module_router in [
    parse.router,
    validate.router,
    generate.router,
    simulate.router,
    export.router,
    deploy.router,
    jobs.router,
    neurosim_handoff.router,
    templates.router,
]:
    router.include_router(module_router)
```

In `suite_api/main.py`, add:

```python
from suite_api.domains.neurocnl.router import router as neurocnl_router
app.include_router(neurocnl_router)
```

**Acceptance gate**:

```bash
python3 -c "from suite_api.main import app; routes = [r.path for r in app.routes]; assert any('/api/neurocnl' in r for r in routes), routes; print('neurocnl routes mounted')"
```

#### Step 2A.3 — Route parity test for neurocnl

Create `tests/integration/test_phase2a_neurocnl_parity.py`:

```python
"""Verify that suite_api serves neurocnl routes with same schema as the original service.
Run with backends on ports 8000 and 9000.
"""
import httpx
import pytest

ORIGINAL = "http://localhost:8000"
SUITE    = "http://localhost:9000"


def test_health_parity() -> None:
    orig = httpx.get(f"{ORIGINAL}/health", timeout=5).json()
    suite = httpx.get(f"{SUITE}/api/neurocnl/health", timeout=5).json()
    assert orig.get("status") == suite.get("status")


def test_openapi_routes_present() -> None:
    import json, pathlib
    contract = json.loads(
        pathlib.Path("docs/api/contracts/neurocnl-openapi.json").read_text()
    )
    original_paths = set(contract.get("paths", {}).keys())
    suite_spec = httpx.get(f"{SUITE}/openapi.json", timeout=5).json()
    suite_paths = set(suite_spec.get("paths", {}).keys())
    # All contract paths must appear in suite_api, possibly prefixed
    for path in original_paths:
        prefixed = f"/api/neurocnl{path}"
        assert prefixed in suite_paths or path in suite_paths, (
            f"Missing route {path} (expected as {prefixed})"
        )
```

**Acceptance gate**: `python3 -m pytest tests/integration/test_phase2a_neurocnl_parity.py -v` — all tests pass.

#### Step 2A.4 — Update Neurohub suite_client for neurocnl ⚠ submodule

Read `Neurohub/AGENTS.md` before editing.

In `Neurohub/neurohub/app/services/suite_client.py`, change the `neurocnl` URL from:

```python
"neurocnl": os.getenv("NEUROCNL_URL", "http://localhost:8000")
```

to:

```python
"neurocnl": os.getenv("SUITE_API_URL", "http://localhost:9000") + "/api/neurocnl"
```

Add `SUITE_API_URL` to Neurohub's `.env` defaults and to the `neurohub` service in `docker-compose.yml` environment block.

**Acceptance gate**: `python3 -m pytest Neurohub/tests/ -v -k "suite_client"` passes. If no such tests exist, verify manually that `suite_client.check_all_services()` returns status for `neurocnl` pointing to the suite_api address.

#### Step 2A.5 — Verify Phase 2A complete

```bash
python3 -m pytest tests/integration/test_phase0_health_baseline.py tests/integration/test_phase1_suite_api.py tests/integration/test_phase2a_neurocnl_parity.py -v
```

All tests pass before proceeding to Phase 2B.

---

### Phase 2B — Neurosim ⚠ submodule

Read `Neurosim/AGENTS.md` before touching any file in `Neurosim/`.

Follow the same pattern as Phase 2A with these specifics:

| Item | Value |
|---|---|
| Module dir | `Neurosim/` |
| Backend entry point | `Neurosim/neurosim/app/main.py` |
| Router files | `components, export, generation, preview, projects, simulation_ws, spinnaker2, sweep, templates, validation` |
| Original port | `8001` |
| suite_api prefix | `/api/neurosim` |
| Domain dir | `suite_api/domains/neurosim/` |
| sys.path insert | `Neurosim/neurosim` (so `from app.routers import ...` resolves) |
| Neurohub suite_client key | `"neurosim"` |
| Contract file | `docs/api/contracts/neurosim-openapi.json` |
| Parity test file | `tests/integration/test_phase2b_neurosim_parity.py` |

Note: `simulation_ws` is a WebSocket router. Include it in the mount; WebSocket routes are forwarded correctly by FastAPI's include_router.

**Acceptance gate**: All Phase 0, 1, 2A, and 2B integration tests pass.

---

### Phase 2C — Neurochip ⚠ submodule

Read `Neurochip/AGENTS.md` before touching any file in `Neurochip/`.

| Item | Value |
|---|---|
| Module dir | `Neurochip/` |
| Backend entry point | `Neurochip/neurochip/app/main.py` |
| Router files | `akida, analysis, deployments, estimation, export, faults, lava, pynq, quantization, serial, spinnaker2, targets` |
| Original port | `8002` |
| suite_api prefix | `/api/neurochip` |
| Domain dir | `suite_api/domains/neurochip/` |
| sys.path insert | `Neurochip/neurochip` |
| Neurohub suite_client key | `"neurochip"` |
| Contract file | `docs/api/contracts/neurochip-openapi.json` |
| Parity test file | `tests/integration/test_phase2c_neurochip_parity.py` |

**Important**: Neurochip has optional hardware imports (Akida, Lava, PYNQ). The existing `app/main.py` already guards these with try/except. Verify that the suite_api import of Neurochip's routers does not raise ImportError on machines without those packages. If it does, wrap the router include in a try/except that skips optional routers with a logged warning.

**Acceptance gate**: All Phase 0–2C integration tests pass. `python3 -c "from suite_api.main import app"` completes without ImportError on a machine without Akida installed.

---

### Phase 2D — Neurobench ⚠ submodule

Read `Neurobench/AGENTS.md` before touching any file in `Neurobench/`.

| Item | Value |
|---|---|
| Module dir | `Neurobench/` |
| Backend entry point | `Neurobench/neurobench/app/main.py` |
| Router files | `baselines, benchmarks, comparison, faults, perturbation, pynq, regression, reports, results, runner, spinnaker2, synsense` |
| Original port | `8003` |
| suite_api prefix | `/api/neurobench` |
| Domain dir | `suite_api/domains/neurobench/` |
| sys.path insert | `Neurobench/neurobench` |
| Neurohub suite_client key | `"neurobench"` |
| Contract file | `docs/api/contracts/neurobench-openapi.json` |
| Parity test file | `tests/integration/test_phase2d_neurobench_parity.py` |

**Important**: Neurobench's `runner` router triggers long-running jobs. Do not change the runner's job-dispatch logic. The runner continues to enqueue jobs the same way; only the HTTP surface moves. Phase 4B will formalize the runner as a worker process.

**Acceptance gate**: All Phase 0–2D integration tests pass.

---

### Phase 2E — Neurosense ⚠ submodule

Read `Neurosense/AGENTS.md` before touching any file in `Neurosense/`.

| Item | Value |
|---|---|
| Module dir | `Neurosense/` |
| Backend entry point | `Neurosense/neurosense/app/main.py` |
| Router files | `devices, presets, stream, encoding, recording, sessions, export, nir, quality, prophesee, pynq` |
| Original port | `8004` |
| suite_api prefix | `/api/neurosense` |
| Domain dir | `suite_api/domains/neurosense/` |
| sys.path insert | `Neurosense/neurosense` |
| Neurohub suite_client key | `"neurosense"` |
| Contract file | `docs/api/contracts/neurosense-openapi.json` |
| Parity test file | `tests/integration/test_phase2e_neurosense_parity.py` |

**Important**: Neurosense has a streaming WebSocket route and real-time hardware I/O via BrainFlow. Mount the router as-is. Hardware routes that require physical devices will return 503 when hardware is absent; this is the existing behaviour and must not change.

**Acceptance gate**: All Phase 0–2E integration tests pass.

---

### Phase 2F — Neurohub ⚠ submodule

Read `Neurohub/AGENTS.md` before touching any file in `Neurohub/`.

Neurohub is last because it orchestrates the others. By Phase 2F, the suite_client routes for all other modules already point to suite_api. Neurohub's own API is now absorbed.

| Item | Value |
|---|---|
| Module dir | `Neurohub/` |
| Backend entry point | `Neurohub/neurohub/app/main.py` |
| Router files | `activity, assets, auth, config, dashboard, health, members, milestones, notes, projects, workflows` |
| Original port | `8005` |
| suite_api prefix | `/api/neurohub` |
| Domain dir | `suite_api/domains/neurohub/` |
| sys.path insert | `Neurohub/neurohub` |
| Contract file | `docs/api/contracts/neurohub-openapi.json` |
| Parity test file | `tests/integration/test_phase2f_neurohub_parity.py` |

**Neurohub-specific steps**:

1. **Database lifespan**: Neurohub's `app/main.py` runs Alembic migrations and a workflow worker loop in its lifespan. Move these to suite_api's lifespan:

   In `suite_api/main.py`, add a lifespan context manager:
   ```python
   from contextlib import asynccontextmanager
   from suite_api.domains.neurohub.lifespan import neurohub_startup, neurohub_shutdown

   @asynccontextmanager
   async def lifespan(app: FastAPI):
       await neurohub_startup()
       yield
       await neurohub_shutdown()

   app = FastAPI(..., lifespan=lifespan)
   ```

   Create `suite_api/domains/neurohub/lifespan.py` that imports and calls the Alembic migration runner and workflow worker from `Neurohub/neurohub/app/main.py`'s lifespan.

2. **suite_client self-reference**: After mounting Neurohub in suite_api, Neurohub's suite_client no longer needs to call localhost:8005 for its own health. Update `suite_client.py` to remove the self-reference and use in-process health from suite_api's health module.

3. **Health endpoint path**: Neurohub uses `/api/neurohub/health` (not `/health`). When mounting under prefix `/api/neurohub`, the effective path becomes `/api/neurohub/api/neurohub/health` which is wrong. Fix by adding an explicit route alias in the domain router:
   ```python
   @router.get("/health")
   async def neurohub_health(): ...
   ```
   This overrides the prefix collision.

**Acceptance gate**:

```bash
python3 -m pytest tests/integration/ -v -k "phase0 or phase1 or phase2"
```

All Phase 0–2F tests pass. Then:

```bash
python3 -m pytest tests/integration/test_cross_module.py -v
```

Passes without changes to the test file (all cross-module calls now go via suite_api).

---

### Phase 2 completion — Update ADRs and capture to OpenBrain

#### Update ADR 0009

Open `docs/ADR-claude/0009-makefile-port-allocation.md` and prepend the following block immediately after the `## Status` heading, changing `Accepted` to `Superseded`:

```markdown
## Status
Superseded by ADR 0018 (suite_api unified backend)

## Supersession note
Ports 8000–8005 were the per-module port assignments under the old
module-as-app architecture. After Phase 2 of the consolidation plan,
all modules are served by suite_api on port 9000. The legacy ports are
retained only for optional hardware/compute workers (Phase 4). This ADR
remains for historical reference.
```

#### Update ADR 0014

Open `docs/ADR-claude/0014-docker-compose-orchestration.md` and append the following after the `## Consequences` section:

```markdown
## Amendment — Consolidation Phase 2 (2026)
The six-service Docker Compose layout described above is superseded after
Phase 5 of the consolidation plan. The new layout has one `suite_api`
service plus optional worker profiles (`hardware`, `jobs`, `physics`).
See ADR 0018 and the implementation plan at
`docs/implementation-plan-consolidation.md`.
```

#### OpenBrain capture

Capture the following thought to OpenBrain using `mcp__open-brain__capture_thought`:

> NMTK consolidation Phase 2 complete: all six module domains (neurocnl, Neurosim, Neurochip, Neurobench, Neurosense, Neurohub) are mounted as internal APIRouters in suite_api under /api/{module}/. Neurohub's suite_client no longer makes HTTP calls to sibling modules — all cross-module calls are in-process. ADRs 0009 and 0014 marked as superseded by ADR 0018.

Then tag:

```bash
git tag consolidation-phase-2-done
git push origin consolidation-phase-2-done
```

---

## Phase 3 — Flutter frontend unification

**Goal**: Replace WebView-hosted per-module web frontends with native Flutter feature packages inside the `nmtk` launcher. The launcher becomes a unified Flutter app.

**Read before any work**: `nmtk/AGENTS.md` and `nmtk_ui_core/AGENTS.md`.

**Migration order**: neurocnl → Neurosim → Neurochip → Neurobench → Neurosense → Neurohub

**Feature flag convention**: Add a Dart constant `kUseNativeScreen` per module package. Set to `false` by default during migration; set to `true` when Step 3X.6 (parity check) passes.

---

### Phase 3A — neurocnl feature package

#### Step 3A.1 — Create the feature package scaffold

```bash
cd nmtk/packages
flutter create --template=package neurocnl_feature
```

Edit `nmtk/packages/neurocnl_feature/pubspec.yaml`:
- Add `flutter_riverpod`, `go_router`, `http` to dependencies.
- Add `nmtk_ui_core: { path: ../../.. /nmtk_ui_core }` to dependencies (three levels up to `nmtk_ui_core/`).
- Remove `flutter_test` from dev_dependencies if not needed.

#### Step 3A.2 — Migrate screens

Copy the following files from `neurocnl/frontend/lib/` to `nmtk/packages/neurocnl_feature/lib/`:

- `screens/` — copy entire directory
- `models/` — copy entire directory
- `providers/` — copy entire directory
- `services/` — copy entire directory
- `widgets/` — copy entire directory

Update all `package:neurocnl_frontend/` import prefixes to `package:neurocnl_feature/`.

Update all `String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000')` occurrences to use `String.fromEnvironment('SUITE_API_URL', defaultValue: 'http://localhost:9000')` with path prefix `/api/neurocnl`.

Specifically: any `ApiService` or equivalent that constructs URLs must prepend `/api/neurocnl` to all route paths.

#### Step 3A.3 — Add feature package to nmtk

In `nmtk/neuro_toolkit/pubspec.yaml`, add:

```yaml
  neurocnl_feature:
    path: ../packages/neurocnl_feature
```

Run `flutter pub get` in `nmtk/neuro_toolkit/`.

**Acceptance gate**: `flutter analyze nmtk/packages/neurocnl_feature/` exits 0 with no errors.

#### Step 3A.4 — Add GoRouter route in nmtk

Read `nmtk/AGENTS.md` before editing any routing file.

In `nmtk/neuro_toolkit/lib/routing/` (whichever file defines the GoRouter), add a route:

```dart
GoRoute(
  path: '/module/neurocnl',
  builder: (context, state) => const NeurocnlShell(),
)
```

where `NeurocnlShell` is the top-level screen exported from `neurocnl_feature`.

Add the import:
```dart
import 'package:neurocnl_feature/neurocnl_feature.dart';
```

**Acceptance gate**: `flutter analyze nmtk/neuro_toolkit/` exits 0.

#### Step 3A.5 — Conditional navigation in the launcher

In the launcher's module navigation code (wherever a module tile is tapped), add a conditional:

```dart
const kNeurocnlNativeScreen = bool.fromEnvironment('NATIVE_NEUROCNL', defaultValue: false);

// When tapping neurocnl module tile:
if (kNeurocnlNativeScreen) {
  context.go('/module/neurocnl');
} else {
  // existing WebView launch
}
```

#### Step 3A.6 — Build and smoke-test the native screen

Build the launcher with the native screen enabled:

```bash
flutter build macos \
  --dart-define=SUITE_API_URL=http://localhost:9000 \
  --dart-define=NATIVE_NEUROCNL=true \
  -C nmtk/neuro_toolkit
```

Run the launcher and manually navigate to the neurocnl module. Verify:
1. The screen renders without blank content or overflow errors.
2. The API calls reach `http://localhost:9000/api/neurocnl/` (check network tab or backend logs).
3. Core workflow (parse CNL → validate → view result) completes without error.

If any check fails, fix before proceeding to Step 3A.7.

#### Step 3A.7 — Enable native screen and remove WebView fallback

Change the dart-define default for `NATIVE_NEUROCNL` to `true` in `scripts/build_module.sh` or in the `Makefile` build targets for the launcher.

Remove the `kNeurocnlNativeScreen` conditional and keep only the GoRouter navigation path.

Do **not** delete `neurocnl/frontend/` yet — that happens in Phase 5.

**Acceptance gate**: `make dev` starts the launcher with neurocnl showing as a native Flutter screen. `flutter test nmtk/packages/neurocnl_feature/` passes.

---

### Phase 3B — Neurosim feature package

Read `Neurosim/AGENTS.md` before referencing any Neurosim frontend code.

Follow the same pattern as Phase 3A with:

| Item | Value |
|---|---|
| Source screens | `Neurosim/frontend/lib/screens/` |
| Source models | `Neurosim/frontend/lib/models/` |
| Feature package dir | `nmtk/packages/neurosim_feature/` |
| Package name | `neurosim_feature` |
| GoRouter path | `/module/neurosim` |
| Top-level screen export | `NeurosimShell` |
| API base path prefix | `/api/neurosim` |
| Dart-define flag | `NATIVE_NEUROSIM` |
| Original port default | `8001` |

**Note for canvas**: Neurosim has an interactive canvas (`screens/` likely includes a canvas screen using custom painters or a graph rendering library). If the canvas uses a JavaScript interop (js_util, dart:html) because it was built as a Flutter web app, those imports must be replaced with Flutter desktop-compatible equivalents. Check `Neurosim/frontend/lib/` for any `import 'dart:html'` or `import 'dart:js'` and replace with conditional imports or platform-aware packages before migrating.

**Acceptance gate**: All Phase 3A acceptance gates pass for Neurosim equivalents. `flutter analyze nmtk/packages/neurosim_feature/` exits 0.

---

### Phase 3C — Neurochip feature package

Read `Neurochip/AGENTS.md` before referencing any Neurochip frontend code.

| Item | Value |
|---|---|
| Source screens | `Neurochip/frontend/lib/screens/` |
| Feature package dir | `nmtk/packages/neurochip_feature/` |
| Package name | `neurochip_feature` |
| GoRouter path | `/module/neurochip` |
| Top-level screen export | `NeurochipShell` |
| API base path prefix | `/api/neurochip` |
| Dart-define flag | `NATIVE_NEUROCHIP` |
| Shell mode | `NmtkShellMode.instrument` (cyan) |

**Acceptance gate**: `flutter analyze nmtk/packages/neurochip_feature/` exits 0. The live deployment log screen renders and polls `/api/neurochip/deployments` via suite_api.

---

### Phase 3D — Neurobench feature package

Read `Neurobench/AGENTS.md` before referencing any Neurobench frontend code.

| Item | Value |
|---|---|
| Source screens | `Neurobench/frontend/lib/screens/` |
| Feature package dir | `nmtk/packages/neurobench_feature/` |
| Package name | `neurobench_feature` |
| GoRouter path | `/module/neurobench` |
| Top-level screen export | `NeurobenchShell` |
| API base path prefix | `/api/neurobench` |
| Dart-define flag | `NATIVE_NEUROBENCH` |
| Router pattern | GoRouter Pattern B (from AGENTS.md) — preserve this pattern |

**Acceptance gate**: `flutter analyze nmtk/packages/neurobench_feature/` exits 0.

---

### Phase 3E — Neurosense feature package

Read `Neurosense/AGENTS.md` before referencing any Neurosense frontend code.

| Item | Value |
|---|---|
| Source screens | `Neurosense/frontend/lib/screens/` |
| Feature package dir | `nmtk/packages/neurosense_feature/` |
| Package name | `neurosense_feature` |
| GoRouter path | `/module/neurosense` |
| Top-level screen export | `NeurosenseShell` |
| API base path prefix | `/api/neurosense` |
| Dart-define flag | `NATIVE_NEUROSENSE` |
| Shell mode | `NmtkShellMode.instrument` (cyan) |

**WebSocket note**: Neurosense uses `web_socket_channel` for live signal streaming. The `web_socket_channel` package works on both Flutter web and Flutter desktop. No changes needed to WebSocket usage.

**Acceptance gate**: `flutter analyze nmtk/packages/neurosense_feature/` exits 0. Live signal screen connects to `ws://localhost:9000/api/neurosense/stream`.

---

### Phase 3F — Neurohub feature package

Read `Neurohub/AGENTS.md` before referencing any Neurohub frontend code.

| Item | Value |
|---|---|
| Source screens | `Neurohub/frontend/lib/screens/` |
| Source view_models | `Neurohub/frontend/lib/view_models/` |
| Feature package dir | `nmtk/packages/neurohub_feature/` |
| Package name | `neurohub_feature` |
| GoRouter path | `/module/neurohub` |
| Top-level screen export | `NeurohubShell` |
| API base path prefix | `/api/neurohub` |
| Dart-define flag | `NATIVE_NEUROHUB` |

**Neurohub-specific**: Neurohub is also the likely new home for the unified dashboard (suite health, project overview). After completing Phase 3F, update the nmtk launcher's root route (`/`) to render the Neurohub dashboard screen from `neurohub_feature` instead of (or in addition to) the existing launcher dashboard.

**Acceptance gate**: `flutter analyze nmtk/packages/neurohub_feature/` exits 0. Project list screen loads data from `/api/neurohub/projects`.

---

### Phase 3 final gate

After Phase 3F:

```bash
flutter analyze nmtk/neuro_toolkit/
flutter test nmtk/neuro_toolkit/
flutter test nmtk/packages/neurocnl_feature/
flutter test nmtk/packages/neurosim_feature/
flutter test nmtk/packages/neurochip_feature/
flutter test nmtk/packages/neurobench_feature/
flutter test nmtk/packages/neurosense_feature/
flutter test nmtk/packages/neurohub_feature/
```

All exit 0. Then run the launcher doctor:

```bash
python3 scripts/launcher_control_service.py --doctor --json
```

`fatalCount` must be 0.

---

### Phase 3 completion — Write ADR 0019, update existing ADRs, capture to OpenBrain

#### Write ADR 0019

Create `docs/ADR-claude/0019-flutter-feature-packages.md`:

```markdown
# ADR 0019: Flutter Feature Packages Replace WebView Embedding

## Status
Accepted

## Context
ADR 0004 (nmtk/docs/ADR-claude/) chose WebView embedding via
`desktop_webview_window` because each module had its own Flutter web frontend
served by its own FastAPI backend. That decision made sense when modules were
independently deployed web apps. After ADR 0018 consolidated the backends into
suite_api, the web frontend model no longer has a structural justification —
the frontends are part of one product, not independently hosted apps.
Additionally, WebView rendering has lower performance than native Flutter,
WKWebView caching causes stale-asset problems, and per-module web builds add
significant build pipeline overhead (6 separate `flutter build web` runs).

ADR 0017 (desktop-shell-adapter-contract) already defined the correct target:
`ShellModuleAdapter` package-based native module integration with
`ModuleDeepLink`, `ShellRestorationSnapshot`, and `CapabilityReport`.

## Decision
Replace each module's WebView-hosted web frontend with a native Flutter feature
package under `nmtk/packages/{module}_feature/`. Each feature package:
- implements the `ShellModuleAdapter` contract from ADR 0017
- depends on `nmtk_ui_core` for design tokens and shared widgets
- is added as a path dependency to `nmtk/neuro_toolkit/pubspec.yaml`
- is routed via GoRouter at `/module/{module}`
- uses `String.fromEnvironment('SUITE_API_URL')` to reach suite_api

The launcher's WebView embedding (`ToolViewScreen` + `desktop_webview_window`)
is removed for all six core modules. Launcher `modules.json` `startStrategy`
is changed from `uvicorn` to `none` for all modules.

## Consequences
- **Positive:** One `flutter build macos` replaces six `flutter build web` runs.
- **Positive:** Native Flutter performance; no WKWebView cache issues.
- **Positive:** One navigation shell, one state model, one release artifact.
- **Positive:** Implements ADR 0017's shell adapter contract.
- **Negative:** Migration effort per module; canvas and streaming UIs needed
  platform-compatibility checks (dart:html → desktop-safe equivalents).
- **Supersedes:** nmtk ADR 0004 (WebView Module Embedding)
- **Implements:** ADR 0017 (Desktop Shell Adapter Contract)
```

#### Update nmtk ADR 0004

Open `nmtk/docs/ADR-claude/0004-webview-module-embedding.md` and change `## Status` to:

```markdown
## Status
Superseded by ADR 0019 (Flutter Feature Packages)

## Supersession note
WebView embedding via desktop_webview_window is replaced by native Flutter
feature packages after Phase 3 of the consolidation plan. See
docs/ADR-claude/0019-flutter-feature-packages.md and
docs/implementation-plan-consolidation.md.
```

#### Update ADR 0010

Open `docs/ADR-claude/0010-multi-module-build-system.md` and append after `## Consequences`:

```markdown
## Amendment — Consolidation Phase 3 (2026)
The per-module `flutter build web` pipeline described above is superseded
after Phase 3 of the consolidation plan. The new build system is a single
`flutter build macos` of `nmtk/neuro_toolkit/` which includes all six domain
feature packages as path dependencies. See ADR 0019 and the implementation
plan at `docs/implementation-plan-consolidation.md`.
```

#### Update ADR 0017

Open `docs/ADR-claude/0017-desktop-shell-adapter-contract.md` and change `## Status` to:

```markdown
## Status
Accepted — Implemented by Phase 3 of consolidation plan

## Implementation note
The `ShellModuleAdapter` contract defined in this ADR is implemented by the
six Flutter feature packages created in Phase 3:
nmtk/packages/{neurocnl,neurosim,neurochip,neurobench,neurosense,neurohub}_feature/.
See ADR 0019 and docs/implementation-plan-consolidation.md.
```

#### OpenBrain capture

Capture the following thought to OpenBrain using `mcp__open-brain__capture_thought`:

> NMTK consolidation Phase 3 complete: all six module frontends migrated from Flutter web (WebView-embedded) to native Flutter feature packages under nmtk/packages/. The nmtk launcher is now a unified Flutter desktop app — one build, one navigation shell, no WebView embedding. ADR 0019 written. ADRs 0004 (WebView), 0010 (multi-module build), and 0017 (shell adapter) updated. Launcher doctor fatalCount is 0.

Then tag:

```bash
git tag consolidation-phase-3-done
git push origin consolidation-phase-3-done
```

---

## Phase 4 — Worker formalization

**Goal**: Extract the four categories of justified separate processes into dedicated worker packages. These workers are started on-demand, not as default services.

Criteria for remaining a worker (from the analysis):
- Hardware-facing drivers that require physical devices
- Long-running jobs (benchmark runs)
- Heavy optional compute (MuJoCo)
- Failure-prone optional integrations

---

### Phase 4A — Neurosense hardware worker

**Justification**: BrainFlow hardware I/O requires a physical EEG/biosignal device. The acquisition loop is real-time and isolated from the main API.

**What moves to worker**:
- Neurosense's `devices` router (hardware enumeration and connection management)
- Neurosense's `stream` router (real-time data acquisition)
- Neurosense's `prophesee` router (event-based camera I/O)
- Neurosense's `pynq` router (PYNQ hardware in neurosense context)

**What stays in suite_api**:
- `presets`, `encoding`, `recording`, `sessions`, `export`, `nir`, `quality` (data processing, not hardware I/O)

#### Step 4A.1 — Create worker package

Create `workers/neurosense_hw/`:

```
workers/neurosense_hw/
workers/neurosense_hw/pyproject.toml
workers/neurosense_hw/main.py
workers/neurosense_hw/Dockerfile
```

`workers/neurosense_hw/pyproject.toml`:

```toml
[project]
name = "neurosense-hw-worker"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.111",
    "uvicorn[standard]>=0.29",
]

[project.optional-dependencies]
brainflow = ["brainflow>=5.0"]
prophesee = ["metavision-sdk>=4.0"]
pynq = ["pynq>=2.7"]
```

`workers/neurosense_hw/main.py`:

```python
"""Neurosense hardware worker — real-time device I/O.
Started only when hardware is present.
Default port: 8004 (existing; kept for backward compat during transition).
"""
import sys
from pathlib import Path
from fastapi import FastAPI

# Import hardware routers from neurosense submodule
sys.path.insert(0, str(Path(__file__).parents[2] / "Neurosense" / "neurosense"))
from app.routers import devices, stream, prophesee  # noqa: E402

try:
    from app.routers import pynq  # optional
    _has_pynq = True
except ImportError:
    _has_pynq = False

app = FastAPI(title="Neurosense Hardware Worker", version="0.1.0")
app.include_router(devices.router, prefix="/api/neurosense")
app.include_router(stream.router, prefix="/api/neurosense")
app.include_router(prophesee.router, prefix="/api/neurosense")
if _has_pynq:
    app.include_router(pynq.router, prefix="/api/neurosense")
```

#### Step 4A.2 — Register worker URL in suite_api config

In `suite_api/config.py`, add:

```python
neurosense_hw_worker_url: str = "http://localhost:8004"
```

In `suite_api/domains/neurosense/router.py`, remove the `devices`, `stream`, `prophesee`, and `pynq` routers from the in-process mount and replace with proxy routes that forward to the hardware worker URL. Use `httpx.AsyncClient` to proxy requests.

#### Step 4A.3 — Add worker to docker-compose.yml profiles

In `docker-compose.yml`, add:

```yaml
  neurosense-hw-worker:
    build:
      context: ./workers/neurosense_hw
    ports:
      - "${NEUROSENSE_PORT:-8004}:8004"
    environment:
      - PYTHONUNBUFFERED=1
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8004/health')"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - backend-net
    profiles:
      - hardware
```

**Acceptance gate**: `docker compose --profile hardware up neurosense-hw-worker` starts without error. Suite API's `/api/neurosense/presets` responds from suite_api directly; `/api/neurosense/devices` proxies to the worker (returns 503 if worker is down, not 500).

---

### Phase 4B — Neurobench runner worker

**Justification**: Benchmark runs are long-running jobs (seconds to minutes). Isolating them prevents the main API from being blocked by compute.

**What moves to worker**: `runner` router (job dispatch and execution)

**What stays in suite_api**: `baselines`, `benchmarks`, `comparison`, `faults`, `perturbation`, `regression`, `reports`, `results`, `synsense` (result storage and querying, not execution)

Follow the same pattern as Phase 4A:

| Item | Value |
|---|---|
| Worker dir | `workers/neurobench_runner/` |
| Worker port | `8003` (existing) |
| Moved routers | `runner`, `pynq` (hardware execution), `spinnaker2` |
| Docker profile | `jobs` |
| Config key | `neurobench_runner_url` |

**Acceptance gate**: `docker compose --profile jobs up neurobench-runner-worker` starts. POST to `/api/neurobench/runner/start` proxies to the worker. GET to `/api/neurobench/results` resolves in suite_api without the worker running.

---

### Phase 4C — Neurochip hardware worker

**Justification**: PYNQ, Akida, and Lava require physical hardware and have hard Python version constraints (Akida: Python >=3.10,<3.13, TensorFlow 2.19.x).

**What moves to worker**: `akida`, `lava`, `pynq`, `serial` routers

**What stays in suite_api**: `analysis`, `deployments`, `estimation`, `export`, `faults`, `quantization`, `spinnaker2`, `targets`

| Item | Value |
|---|---|
| Worker dir | `workers/neurochip_hw/` |
| Worker port | `8002` (existing) |
| Moved routers | `akida, lava, pynq, serial` |
| Docker profile | `hardware` |
| Config key | `neurochip_hw_worker_url` |

**Acceptance gate**: Suite API returns the hardware routers' responses proxied from the worker. On machines without Akida installed, `workers/neurochip_hw/main.py` starts cleanly (hardware routers skipped with logged warning).

---

### Phase 4D — neurocnl physics worker

**Justification**: MuJoCo is a heavy optional dependency. The physics simulation variant has a separate Docker build (`backend/Dockerfile` with `INSTALL_PHYSICS: 1`).

**What moves to worker**: `prosthetic` router sub-paths that invoke MuJoCo directly

**What stays in suite_api**: Standard CNL parse/validate/generate/simulate (non-physics)

| Item | Value |
|---|---|
| Worker dir | `workers/neurocnl_physics/` |
| Worker port | `8006` (existing physics port) |
| Moved routers | prosthetic simulation sub-routes that call `mujoco.*` |
| Docker profile | `physics` |
| Config key | `neurocnl_physics_worker_url` |

**Acceptance gate**: Standard neurocnl routes work without MuJoCo installed. Physics routes return 503 when the worker is not running, not ImportError.

---

### Phase 4 completion — Capture to OpenBrain

Capture the following thought to OpenBrain using `mcp__open-brain__capture_thought`:

> NMTK consolidation Phase 4 complete: four optional worker processes formalized — neurosense-hw-worker (BrainFlow/Prophesee, port 8004, profile: hardware), neurobench-runner-worker (long-running jobs, port 8003, profile: jobs), neurochip-hw-worker (PYNQ/Akida/Lava, port 8002, profile: hardware), neurocnl-physics-worker (MuJoCo, port 8006, profile: physics). All workers are opt-in via Docker Compose profiles. suite_api serves all standard routes without hardware workers running.

Then tag:

```bash
git tag consolidation-phase-4-done
git push origin consolidation-phase-4-done
```

---

## Phase 5 — Decommission and cleanup

**Goal**: Remove all per-module standalone services, per-module frontend build pipelines, and stale launcher configurations. All prior phases must be fully complete before Phase 5 begins.

**Pre-condition gate** (must pass before any Phase 5 step):

```bash
python3 -m pytest tests/integration/ -v -k "phase0 or phase1 or phase2"
python3 scripts/launcher_control_service.py --doctor --json
bash scripts/run_launcher_guardrails.sh
```

All pass.

---

### Step 5.1 — Remove standalone module services from docker-compose.yml

From `docker-compose.yml`, remove the top-level service blocks for:
- `neurocnl`
- `neurosim`
- `neurochip`
- `neurobench`
- `neurosense`
- `neurohub`
- `neurocnl-physics`

Keep:
- `suite_api`
- `neurosense-hw-worker` (added Phase 4A, profile: hardware)
- `neurobench-runner-worker` (added Phase 4B, profile: jobs)
- `neurochip-hw-worker` (added Phase 4C, profile: hardware)
- `neurocnl-physics-worker` (added Phase 4D, profile: physics)
- All monitoring services (Prometheus, Loki, Promtail, Grafana, Alertmanager)

Update `docker-compose.prod.yml` and `docker-compose.dev.yml` to remove references to the removed services.

**Acceptance gate**:

```bash
python3 scripts/validate_docker_compose.sh
docker compose config --quiet
```

Both exit 0.

---

### Step 5.2 — Update modules.json

Read `nmtk/AGENTS.md` before editing `modules.json`.

In `nmtk/neuro_toolkit/assets/modules.json`, for each of the six modules:
- Remove `"startStrategy": "uvicorn"` and the corresponding `"uvicornTarget"` field.
- Change `"startStrategy"` to `"none"` (module is now served by suite_api).
- Keep all other fields unchanged (id, name, port for legacy references, installPath, hasFrontend, etc.).

After editing `modules.json`, update the corresponding Dart models in `nmtk/neuro_toolkit/lib/models/` and the launcher unit tests. This is a single coordinated change per the AGENTS.md rule.

**Acceptance gate**:

```bash
python3 scripts/launcher_control_service.py --doctor --json
```

`fatalCount` is 0. Then:

```bash
flutter test nmtk/neuro_toolkit/
```

Passes.

---

### Step 5.3 — Remove per-module frontend build from Makefile

In `Makefile`:

1. Remove `neurocnl Neurosim Neurochip Neurobench Neurosense Neurohub` from the `MODULES` variable.
2. Remove the `PORT_*` variables for each removed module.
3. Remove the `build-submodules`, `rebuild-submodules`, `build-interactive`, and per-module `build-$(1)` rules that build Flutter web frontends.
4. Replace the `dev` target to launch suite_api and the nmtk Flutter app only:
   ```makefile
   dev:
       @uvicorn suite_api.main:app --port 9000 --reload &
       @flutter run -d $(FLUTTER_DEVICE) -C nmtk/neuro_toolkit \
           --dart-define=SUITE_API_URL=http://localhost:9000
   ```

Keep `dev-native`, `clean-all`, `bump-version`, `ci`, and `release` targets.

**Acceptance gate**: `make help` shows updated target list. `make dev` starts suite_api and the Flutter launcher without attempting to build web frontends.

---

### Step 5.4 — Archive per-module web frontend build scripts

Move the following scripts to `scripts/archive/`:
- `scripts/build_module.sh`
- `scripts/build_all_frontends.sh`
- `scripts/select_modules.sh`

Do not delete them — archive preserves recovery options.

**Acceptance gate**: `ls scripts/archive/` contains all three files. `make ci` still passes (CI should not call archived scripts).

---

### Step 5.5 — Update SETUP_GUIDE.md

Replace Option B (Manual setup with per-module backends) with a new section:

```
Option B: Manual setup (suite_api)
1. pip install -e suite_api/
2. uvicorn suite_api.main:app --port 9000 --reload
3. flutter run -d macos -C nmtk/neuro_toolkit \
       --dart-define=SUITE_API_URL=http://localhost:9000
```

Remove all per-module `uvicorn` commands from the setup guide. Keep hardware worker start instructions under a new "Optional hardware workers" section.

Update the Port Reference Table to:

| Service | Port | Notes |
|---|---|---|
| suite_api | 9000 | Always running |
| neurosense-hw-worker | 8004 | Only with hardware |
| neurobench-runner-worker | 8003 | Only for benchmarks |
| neurochip-hw-worker | 8002 | Only with hardware |
| neurocnl-physics-worker | 8006 | Only with MuJoCo |

**Acceptance gate**: `grep -c 'uvicorn' SETUP_GUIDE.md` returns a count equal only to the suite_api and worker start commands (no per-module uvicorn calls remain in standard setup paths).

---

### Step 5.6 — Finalize ADR 0008 and write consolidation retrospective ADR

#### Update ADR 0008

Open `docs/ADR-claude/0008-git-submodule-strategy.md` and append after `## Consequences`:

```markdown
## Amendment — Consolidation Plan (2026)
The submodule repos (neurocnl, Neurosim, Neurochip, Neurobench, Neurosense,
Neurohub, Neuro-Dream-Hand) retain their independent git histories and repos
as established by this ADR. Their role has changed:

Before consolidation: each submodule ran as an independently started FastAPI
service + Flutter web frontend.

After consolidation: each submodule's Python backend is an internal package
mounted as an APIRouter inside suite_api. Each submodule's Flutter frontend
is a native feature package inside nmtk/packages/. The submodule repos are
now bounded-context packages, not standalone deployed applications.

The git submodule pinning strategy and sibling-repo layout from this ADR
remain unchanged and continue to be the correct approach.
```

#### OpenBrain capture — final state

Capture the following thought to OpenBrain using `mcp__open-brain__capture_thought`:

> NMTK architecture consolidation complete (all 5 phases done). Architecture shifted from module-as-app to module-as-domain. suite_api (port 9000) is the single FastAPI backend serving all 6 domain namespaces (/api/neurocnl, /api/neurosim, /api/neurochip, /api/neurobench, /api/neurosense, /api/neurohub). nmtk is the single Flutter desktop app with 6 native feature packages (no WebView). Four optional workers (neurosense-hw, neurobench-runner, neurochip-hw, neurocnl-physics) run only when hardware/compute is present. ADRs written: 0018 (suite_api), 0019 (Flutter feature packages). ADRs amended: 0008, 0009, 0010, 0014. ADRs superseded: nmtk/0004 (WebView). ADR 0017 marked implemented. New make dev = suite_api (port 9000) + flutter run nmtk/neuro_toolkit.

Then tag and open the final PR:

```bash
git tag consolidation-phase-5-done
git push origin consolidation-phase-5-done

# Merge consolidation into main:
git checkout main
git merge --no-ff consolidation -m "Architecture consolidation: module-as-app → module-as-domain"
git push origin main
```

**Do not merge to main without human review.** Open a PR from `consolidation` → `main` and request review. The auto-merge workflow will not auto-merge this (protected files changed).

---

### Step 5.7 — Final integration test pass

```bash
python3 -m pytest tests/integration/ -v
bash scripts/run_launcher_guardrails.sh --with-integration
python3 scripts/launcher_control_service.py --doctor --json
flutter test nmtk/neuro_toolkit/
flutter analyze nmtk/
```

All pass. `fatalCount` is 0.

---

## Summary table

| Phase | Parent repo branch | Submodule branches | What changes | ADR actions | OpenBrain capture | Rollback path |
|---|---|---|---|---|---|---|
| 0 | `consolidation/phase-0` | none | Test files, JSON snapshots, empty directories | none | Yes (Step 0.6) | Delete added files |
| 1 | `consolidation/phase-1` | none | New `suite_api/` service, docker-compose addition | Write ADR 0018 | Yes (Step 1.8) | Remove suite_api service block, delete `suite_api/` |
| 2A | `consolidation/phase-2a-neurocnl` | `neurocnl:consolidation` | Mount neurocnl router, update suite_client | none | — | Revert include_router + suite_client URL |
| 2B–2E | `consolidation/phase-2{b-e}-{module}` | one per module | Mount module router, update suite_client | none | — | Same pattern |
| 2F | `consolidation/phase-2f-neurohub` | `Neurohub:consolidation` | Mount Neurohub, lifespan migration | Amend ADR 0009, 0014 | Yes (Phase 2 completion) | Revert include_router + lifespan |
| 3A–3F | `consolidation/phase-3{a-f}-{module}` | none | Flutter feature packages, GoRouter routes | (see 3F) | — | Remove feature package, revert pubspec + routing |
| 3F done | — | none | Phase 3 final gate | Write ADR 0019; amend 0010, 0017; supersede nmtk/0004 | Yes (Phase 3 completion) | Revert ADR files |
| 4A–4D | `consolidation/phase-4-workers` | none | Four worker processes | none | Yes (Phase 4 completion) | Remove worker, restore in-process router |
| 5 | `consolidation/phase-5-decommission` | none | Remove old services, scripts, compose entries | Amend ADR 0008 | Yes (Step 5.6, final) | Git revert Phase 5 commits |
| Final | PR: `consolidation → main` | none | Merge to production | — | — | Revert merge |

Each phase boundary is a stable, deployable state. Never start a phase until all prior acceptance gates pass. Never merge `consolidation → main` without human review — the auto-merge CI workflow will block it correctly.
