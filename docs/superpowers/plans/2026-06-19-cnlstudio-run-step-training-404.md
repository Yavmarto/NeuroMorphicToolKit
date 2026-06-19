# CNL Studio Run Step — Training 404 & False Success Fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Run step so Notebook 2 (and all generated notebooks) can be executed after generation, with correct error/success UI and live progress events.

**Architecture:** Notebook generation writes via Jupyter Contents API when `JUPYTER_WORKER_URL` is set, but execution (`POST /notebook/run`) only looks on the backend's local `NOTEBOOK_DIR` — which is not shared with the Jupyter container in Docker. We unify notebook storage (shared volume + dual-write), add a path resolver with Contents API fallback, finish the kernel runner's progress bridge (`_maybe_publish` → `progress_bus`), and fix the Run step UI so errors never show a green "Training complete" banner.

**Tech Stack:** Python 3.11 / FastAPI / pytest; Flutter / Dart / flutter test; Docker Compose.

## Global Constraints

- End-user convenience is highest priority: auto-detect paths, actionable errors, no manual URL/port setup.
- Do not catch bare `Exception` — catch specific exceptions in new Python code.
- Read `neurocnl/AGENTS.md` and `CODING_STYLE_GUIDE.md` before editing `neurocnl/**`.
- Read `nmtk/AGENTS.md` before editing root `docker-compose.yml` if launcher-visible.
- Run `pytest neurocnl/backend/tests/test_kernel_runner.py neurocnl/backend/tests/test_training_router.py` and `cd neurocnl/frontend && flutter test test/screens/` after changes.
- Cross-file invariant: after adding `resolve_notebook_path`, run `gbrain write --title "notebook path: generate-v2 workspace_folder ↔ kernel_runner NOTEBOOK_DIR" --body "generate-v2 returns workspace_folder like {slug}/notebooks; run resolves via resolve_notebook_path against NOTEBOOK_DIR or Jupyter Contents API fallback when JUPYTER_WORKER_URL is set."`

---

## Root Cause Summary (for implementers)

| Symptom | Cause | File |
|---------|-------|------|
| `404` / `{"detail":"Notebook not found: ..."}` on Start | `generate-v2` publishes to Jupyter (`JUPYTER_WORKER_URL`); `kernel_runner` reads `NOTEBOOK_DIR` on `suite_api`, which has **no shared volume** with `jupyter-server` in `docker-compose.yml` | `notebook.py:2187`, `kernel_runner.py:74-79`, `docker-compose.yml:3-38` |
| Green "Training complete" despite 404 | `_isAllDone` treats `_TrainingStatus.error` the same as `complete` for the success banner | `run_step.dart:24-28`, `281-309` |
| No epoch metrics during run | `_maybe_publish` referenced by tests but **not implemented** in `kernel_runner.py`; nbconvert stdout is not wired to `progress_bus` | `test_kernel_runner.py:61-107`, `kernel_runner.py` |
| Notebook step vs Run step workspace drift | Notebook step slugifies workspace name; Run step passes raw `workspaceName` (backend re-slugifies, so low risk but inconsistent) | `notebook_step.dart:72`, `run_step.dart:88` |

---

## File Structure

| File | Responsibility |
|------|----------------|
| `neurocnl/backend/app/services/notebook_paths.py` | **Create** — canonical `resolve_notebook_path()`, optional Contents API fetch |
| `neurocnl/backend/app/routers/kernel_runner.py` | **Modify** — use resolver, restore `_maybe_publish`, stream progress to `progress_bus` |
| `neurocnl/backend/app/routers/notebook.py` | **Modify** — dual-write to `NOTEBOOK_DIR` when Jupyter worker is configured |
| `neurocnl/backend/tests/test_notebook_paths.py` | **Create** — path resolution tests |
| `neurocnl/backend/tests/test_kernel_runner.py` | **Modify** — integration test for resolved path + progress |
| `docker-compose.yml` | **Modify** — share `jupyter_notebooks` volume with `suite_api`, set `JUPYTER_NOTEBOOK_DIR` |
| `scripts/run_dev.sh` | **Modify** — export `JUPYTER_WORKER_URL` + `JUPYTER_NOTEBOOK_DIR` for native suite_api child |
| `neurocnl/frontend/lib/screens/studio/steps/run_step.dart` | **Modify** — fix success/error banners, slugify workspace, parse API detail |
| `neurocnl/frontend/test/screens/run_step_test.dart` | **Create** — widget tests for banner logic |

---

### Task 1: Notebook path resolver

**Files:**
- Create: `neurocnl/backend/app/services/notebook_paths.py`
- Test: `neurocnl/backend/tests/test_notebook_paths.py`

**Interfaces:**
- Consumes: `NOTEBOOK_DIR`, `JUPYTER_WORKER_URL` from `backend.app.routers.notebook`
- Produces: `resolve_notebook_path(notebook_path: str) -> Path` — raises `FileNotFoundError` with actionable message if unresolvable

- [ ] **Step 1: Write the failing test**

```python
# neurocnl/backend/tests/test_notebook_paths.py
from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from backend.app.services.notebook_paths import resolve_notebook_path


def test_resolve_relative_path_under_notebook_dir(tmp_path: Path) -> None:
  nb = tmp_path / "my-ws" / "notebooks" / "pipeline_snntorch_sim.ipynb"
  nb.parent.mkdir(parents=True)
  nb.write_text("{}", encoding="utf-8")

  with patch("backend.app.services.notebook_paths.NOTEBOOK_DIR", tmp_path):
    resolved = resolve_notebook_path("my-ws/notebooks/pipeline_snntorch_sim.ipynb")

  assert resolved == nb


def test_resolve_raises_when_missing(tmp_path: Path) -> None:
  with patch("backend.app.services.notebook_paths.NOTEBOOK_DIR", tmp_path):
    with pytest.raises(FileNotFoundError, match="pipeline_snntorch_sim.ipynb"):
      resolve_notebook_path("missing/notebooks/pipeline_snntorch_sim.ipynb")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl && PYTHONPATH=. pytest backend/tests/test_notebook_paths.py -v`
Expected: FAIL with `ModuleNotFoundError: backend.app.services.notebook_paths`

- [ ] **Step 3: Write minimal implementation**

```python
# neurocnl/backend/app/services/notebook_paths.py
from __future__ import annotations

import json
from pathlib import Path

import httpx

from backend.app.routers.notebook import JUPYTER_WORKER_URL, NOTEBOOK_DIR


def resolve_notebook_path(notebook_path: str) -> Path:
  """Resolve a notebook path returned by generate-v2 to a local filesystem path.

  Order:
  1. Absolute path that exists.
  2. NOTEBOOK_DIR / relative path.
  3. When JUPYTER_WORKER_URL is set, fetch via Contents API into NOTEBOOK_DIR mirror.
  """
  raw = notebook_path.strip()
  if not raw:
    raise FileNotFoundError("No notebook path was provided.")

  candidate = Path(raw)
  if candidate.is_absolute() and candidate.exists():
    return candidate

  local = NOTEBOOK_DIR / raw
  if local.exists():
    return local

  if JUPYTER_WORKER_URL:
    fetched = _fetch_from_jupyter_contents(raw)
    if fetched is not None:
      return fetched

  raise FileNotFoundError(
    f"Notebook not found at '{local}'. "
    "Regenerate the notebook in the Notebook step, then retry. "
    "If this persists, ensure the Jupyter server and backend share the same notebook directory."
  )


def _fetch_from_jupyter_contents(relative_path: str) -> Path | None:
  """Download notebook JSON from Jupyter Contents API and mirror under NOTEBOOK_DIR."""
  url = f"{JUPYTER_WORKER_URL}/api/contents/{relative_path}"
  try:
    with httpx.Client(timeout=30.0) as client:
      resp = client.get(url)
  except httpx.HTTPError:
    return None
  if resp.status_code != 200:
    return None

  payload = resp.json()
  content = payload.get("content")
  if not isinstance(content, dict):
    return None

  dest = NOTEBOOK_DIR / relative_path
  dest.parent.mkdir(parents=True, exist_ok=True)
  dest.write_text(json.dumps(content, indent=2), encoding="utf-8")
  return dest
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd neurocnl && PYTHONPATH=. pytest backend/tests/test_notebook_paths.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add neurocnl/backend/app/services/notebook_paths.py neurocnl/backend/tests/test_notebook_paths.py
git commit -m "fix: add notebook path resolver for run step"
```

---

### Task 2: Wire kernel_runner to resolver + progress bus

**Files:**
- Modify: `neurocnl/backend/app/routers/kernel_runner.py`
- Test: `neurocnl/backend/tests/test_kernel_runner.py`

**Interfaces:**
- Consumes: `resolve_notebook_path()` from Task 1; `progress_bus` from `backend.app.services.progress_bus`
- Produces: `_maybe_publish(line, platform, publisher)` — strips `__nmtk_progress__` JSON lines into SSE events

- [ ] **Step 1: Write the failing integration test**

Add to `neurocnl/backend/tests/test_kernel_runner.py`:

```python
def test_run_notebook_resolves_relative_workspace_path(tmp_path):
  ws = tmp_path / "cnn-eval" / "notebooks"
  ws.mkdir(parents=True)
  nb = ws / "pipeline_snntorch_sim.ipynb"
  nb.write_text(
      json.dumps({"nbformat": 4, "nbformat_minor": 5, "cells": [], "metadata": {}}),
      encoding="utf-8",
  )

  with (
      patch("backend.app.routers.kernel_runner.NOTEBOOK_DIR", tmp_path),
      patch("backend.app.routers.kernel_runner.job_store.create", new=AsyncMock(return_value=_FAKE_JOB_ID)),
      patch("backend.app.routers.kernel_runner._execute_notebook", new=AsyncMock()),
  ):
      resp = client.post(
          "/api/notebook/run",
          json={
              "notebook_path": "cnn-eval/notebooks/pipeline_snntorch_sim.ipynb",
              "platform": "snntorch_sim",
          },
      )

  assert resp.status_code == 202
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl && PYTHONPATH=. pytest backend/tests/test_kernel_runner.py::test_run_notebook_resolves_relative_workspace_path -v`
Expected: FAIL with `404` (path not found under default `/root`)

- [ ] **Step 3: Implement kernel_runner changes**

Replace `kernel_runner.py` body with resolver + progress bridge:

```python
"""POST /api/notebook/run — queue a Jupyter notebook for execution."""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Callable
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from backend.app.schemas.jobs import JobQueued
from backend.app.services.job_store import job_store
from backend.app.services.notebook_paths import resolve_notebook_path
from backend.app.services.progress_bus import progress_bus

router = APIRouter()
_logger = logging.getLogger(__name__)


class NotebookRunRequest(BaseModel):
    notebook_path: str
    platform: str = "snntorch_sim"
    kernel_name: str = "python3"


def _maybe_publish(
    line: str,
    platform: str,
    publish: Callable[[dict], None],
) -> None:
    """Parse a stdout/stderr line for __nmtk_progress__ JSON and publish an epoch event."""
    stripped = line.strip()
    if not stripped:
        return
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return
    if not isinstance(payload, dict) or not payload.get("__nmtk_progress__"):
        return
    event = {
        "type": "epoch",
        "epoch": int(payload["epoch"]),
        "total_epochs": int(payload.get("total_epochs", 0)) or None,
        "loss": float(payload.get("loss", 0.0)),
        "accuracy": float(payload["accuracy"]) if payload.get("accuracy") is not None else None,
        "layer_spike_rates": payload.get("layer_spike_rates") or {},
        "platform": platform,
    }
    publish(event)


async def _execute_notebook(
    job_id: str,
    path: Path,
    platform: str,
    kernel_name: str,
) -> None:
    publisher = progress_bus.publisher_for(job_id)
    try:
        await job_store.set_running(job_id)
        _logger.info(
            "notebook_execution_start",
            job_id=job_id,
            path=str(path),
            platform=platform,
            kernel_name=kernel_name,
        )
        proc = await asyncio.create_subprocess_exec(
            "jupyter",
            "nbconvert",
            "--to",
            "notebook",
            "--execute",
            "--inplace",
            "--ExecutePreprocessor.kernel_name",
            kernel_name,
            str(path),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )

        assert proc.stdout is not None
        while True:
            line_bytes = await proc.stdout.readline()
            if not line_bytes:
                break
            line = line_bytes.decode(errors="replace")
            if publisher is not None:
                _maybe_publish(line, platform, publisher)

        returncode = await proc.wait()
        if returncode != 0:
            err = f"Notebook execution failed (exit {returncode})"
            _logger.error("notebook_execution_failed", job_id=job_id, error=err)
            if publisher is not None:
                publisher({"type": "failed", "status": "failed", "error": err})
            await job_store.set_failed(job_id, error=err)
        else:
            _logger.info("notebook_execution_complete", job_id=job_id)
            if publisher is not None:
                publisher({"type": "done", "status": "completed"})
            await job_store.set_complete(job_id, result={"notebook_path": str(path)})
    except OSError as exc:
        _logger.exception("notebook_execution_error", job_id=job_id, exc=str(exc))
        if publisher is not None:
            publisher({"type": "failed", "status": "failed", "error": str(exc)})
        await job_store.set_failed(job_id, error=str(exc))
    finally:
        progress_bus.close(job_id)


@router.post("/notebook/run", response_model=JobQueued, status_code=202)
async def run_notebook(body: NotebookRunRequest) -> JobQueued:
    try:
        path = resolve_notebook_path(body.notebook_path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    job_id = await job_store.create()
    asyncio.create_task(
        _execute_notebook(job_id, path, body.platform, body.kernel_name)
    )
    return JobQueued(job_id=job_id, request_id=None)
```

- [ ] **Step 4: Run tests**

Run: `cd neurocnl && PYTHONPATH=. pytest backend/tests/test_kernel_runner.py -v`
Expected: PASS (including existing `_maybe_publish` tests)

- [ ] **Step 5: Commit**

```bash
git add neurocnl/backend/app/routers/kernel_runner.py neurocnl/backend/tests/test_kernel_runner.py
git commit -m "fix: resolve notebook paths and stream run progress to SSE"
```

---

### Task 3: Dual-write notebooks to NOTEBOOK_DIR when Jupyter worker is active

**Files:**
- Modify: `neurocnl/backend/app/routers/notebook.py` (`_publish_via_contents_api`, ~796-841)

**Interfaces:**
- Consumes: existing `_publish_via_contents_api(workspace_folder, files)`
- Produces: side effect — each notebook also written to `NOTEBOOK_DIR / workspace_folder / notebooks / {filename}`

- [ ] **Step 1: Write the failing test**

Add to `neurocnl/backend/tests/test_notebook_generate_v2.py`:

```python
def test_generate_v2_dual_writes_when_jupyter_worker_configured(tmp_path: Path) -> None:
    with (
        patch("backend.app.routers.notebook.NOTEBOOK_DIR", tmp_path),
        patch("backend.app.routers.notebook.JUPYTER_WORKER_URL", "http://jupyter:8008"),
        patch("backend.app.routers.notebook._publish_via_contents_api") as mock_publish,
    ):
        resp = client.post(
            "/api/notebook/generate-v2",
            json={"spec": VALID_SPEC, "pipeline_config": {"framework": "snntorch_sim"}},
        )
    assert resp.status_code == 200
    mock_publish.assert_called_once()
    filename = resp.json()["notebooks"][0]["filename"]
    workspace_folder = resp.json()["workspace_folder"]
    # workspace_folder is "{slug}/notebooks" — file lives at NOTEBOOK_DIR / workspace_folder / filename
    on_disk = tmp_path / workspace_folder / filename
    assert on_disk.exists(), f"expected mirror at {on_disk}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl && PYTHONPATH=. pytest backend/tests/test_notebook_generate_v2.py::test_generate_v2_dual_writes_when_jupyter_worker_configured -v`
Expected: FAIL — file not on disk

- [ ] **Step 3: Add mirror write inside generate-v2 path**

In `generate_notebook_v2`, after `_publish_via_contents_api(workspace_folder, built)`, add:

```python
    if JUPYTER_WORKER_URL:
        _publish_via_contents_api(workspace_folder, built)
        # Mirror to NOTEBOOK_DIR so kernel_runner can execute without a Contents round-trip.
        mirror_dir = NOTEBOOK_DIR / workspace_folder
        mirror_dir.mkdir(parents=True, exist_ok=True)
        for filename, nb in built:
            (mirror_dir / filename).write_text(
                json.dumps(nb, indent=2), encoding="utf-8"
            )
    else:
        output_dir = NOTEBOOK_DIR / workspace_folder
        ...
```

Apply the same mirror pattern to `generate_notebook_from_spec` (the `if JUPYTER_WORKER_URL:` branch ~925-927).

- [ ] **Step 4: Run tests**

Run: `cd neurocnl && PYTHONPATH=. pytest backend/tests/test_notebook_generate_v2.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add neurocnl/backend/app/routers/notebook.py neurocnl/backend/tests/test_notebook_generate_v2.py
git commit -m "fix: mirror generated notebooks to NOTEBOOK_DIR for execution"
```

---

### Task 4: Docker — share notebook volume with suite_api

**Files:**
- Modify: `docker-compose.yml` (`suite_api` service, lines 3-38)

- [ ] **Step 1: Add volume mount and env to suite_api**

```yaml
  suite_api:
    environment:
      # ... existing ...
      - JUPYTER_NOTEBOOK_DIR=/root
    volumes:
      - jupyter_notebooks:/root
```

- [ ] **Step 2: Verify compose config**

Run: `docker compose config --quiet`
Expected: exit 0, no YAML errors

- [ ] **Step 3: Manual smoke (after stack restart)**

Run: `docker compose up -d suite_api jupyter-server`
Then generate + run via `scripts/backend_endpoint_smoke.py` or Studio UI.
Expected: `POST /api/neurocnl/notebook/run` returns 202, not 404.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml
git commit -m "fix: share jupyter notebook volume with suite_api"
```

---

### Task 5: Native dev — align JUPYTER env for suite_api child

**Files:**
- Modify: `scripts/run_dev.sh` (`start_jupyter_server` and suite_api spawn section)

- [ ] **Step 1: Export env when launcher starts suite_api**

After `start_jupyter_server`, ensure the control API / suite_api child inherits:

```bash
export JUPYTER_WORKER_URL="${JUPYTER_WORKER_URL:-http://127.0.0.1:${JUPYTER_PORT:-8008}}"
export JUPYTER_NOTEBOOK_DIR="${JUPYTER_NOTEBOOK_DIR:-$HOME/nmtk_notebooks}"
```

Document in a one-line comment that both Jupyter and neurocnl backend must share this directory.

- [ ] **Step 2: Smoke native path**

Run: `bash scripts/run_dev.sh --flutter-device macos` (or existing device), complete Notebook 2 workflow through Run step.
Expected: no 404 on Start.

- [ ] **Step 3: Commit**

```bash
git add scripts/run_dev.sh
git commit -m "fix: align JUPYTER paths for native dev notebook execution"
```

---

### Task 6: Fix Run step false success UI

**Files:**
- Modify: `neurocnl/frontend/lib/screens/studio/steps/run_step.dart`
- Create: `neurocnl/frontend/test/screens/run_step_test.dart`

**Interfaces:**
- Consumes: existing `_TrainingStatus` enum
- Produces: `_isAllSucceeded` getter (all platforms `complete`), `_hasAnyError` getter; `_formatApiError(Object e)` helper

- [ ] **Step 1: Write the failing widget test**

```dart
// neurocnl/frontend/test/screens/run_step_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:neurocnl_studio/screens/studio/steps/run_step_logic.dart';

void main() {
  test('allSucceeded is false when any platform errored', () {
    final flags = <String, TrainingRunOutcome>{
      'snntorch_sim': TrainingRunOutcome.complete,
      'nengo': TrainingRunOutcome.error,
    };
    expect(RunStepLogic.allSucceeded(flags), isFalse);
    expect(RunStepLogic.hasAnyError(flags), isTrue);
  });

  test('allSucceeded is true only when every platform completed', () {
    final flags = <String, TrainingRunOutcome>{
      'snntorch_sim': TrainingRunOutcome.complete,
    };
    expect(RunStepLogic.allSucceeded(flags), isTrue);
    expect(RunStepLogic.hasAnyError(flags), isFalse);
  });
}
```

Extract minimal pure logic to `run_step_logic.dart` (new file under `lib/screens/studio/steps/`) to keep tests fast without mounting the full Studio stack.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl/frontend && flutter test test/screens/run_step_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Implement logic + UI fix**

`run_step_logic.dart`:

```dart
enum TrainingRunOutcome { idle, running, complete, error }

class RunStepLogic {
  static bool allSucceeded(Map<String, TrainingRunOutcome> status) =>
      status.isNotEmpty &&
      status.values.every((s) => s == TrainingRunOutcome.complete);

  static bool hasAnyError(Map<String, TrainingRunOutcome> status) =>
      status.values.any((s) => s == TrainingRunOutcome.error);
}
```

In `run_step.dart`:
1. Replace green banner condition: `if (RunStepLogic.allSucceeded(_outcomeMap))` instead of `_isAllDone`.
2. Add red error banner when `RunStepLogic.hasAnyError(_outcomeMap)`:

```dart
if (_hasRunErrors)
  Material(
    color: colors.surfaceNegativeSubtle,
    child: Text('Run failed — see error above and retry.'),
  ),
```

3. Parse API errors in catch block:

```dart
String _formatApiError(Object e) {
  if (e is ApiException) {
    try {
      final decoded = jsonDecode(e.body) as Map<String, dynamic>;
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
    } catch (_) {}
    return 'Request failed (${e.statusCode}).';
  }
  return e.toString();
}
```

4. Slugify workspace path to match Notebook step:

```dart
workspacePath: _slugifyWorkspace(workspace.workspaceName),

String _slugifyWorkspace(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
```

5. Fix `onDone` — only mark complete when at least one epoch event OR terminal `done` event received; never promote `running → complete` on empty SSE close:

```dart
onDone: () {
  if (!mounted) return;
  if (_status[platform] == _TrainingStatus.running) {
    setState(() => _status[platform] = _TrainingStatus.error);
    _globalError ??= 'Run ended without progress events.';
  }
},
```

- [ ] **Step 4: Run tests**

Run: `cd neurocnl/frontend && flutter test test/screens/run_step_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add neurocnl/frontend/lib/screens/studio/steps/run_step.dart \
        neurocnl/frontend/lib/screens/studio/steps/run_step_logic.dart \
        neurocnl/frontend/test/screens/run_step_test.dart
git commit -m "fix: run step shows errors instead of false training complete"
```

---

### Task 7: Notebook 2 manual verification checklist

**Files:** none (verification only)

- [ ] **Step 1: Notebook 2 eval workflow**

1. Import `cnn_sinabs.nir` on Model canvas.
2. Build Eval pipeline per `docs/current tasks/16 june/cnlstudio_notebook_analysis.md` Notebook 2 guide (Data Loader `tonic_nmnist`, Forward Pass eval, Accuracy).
3. Notebook step → confirm `pipeline_snntorch_sim.ipynb` appears in Jupyter.
4. Run step → Start → expect 202 (not 404), progress or completion after nbconvert finishes.
5. Results step → Dynamics / accuracy visible.

- [ ] **Step 2: Negative test**

Delete the notebook file from disk, click Start without regenerating.
Expected: red error banner with "Notebook not found… Regenerate…", **no** green success banner.

- [ ] **Step 3: Record in Open Brain**

```bash
gbrain write --title "CNL Studio Run step notebook path fix" --body "generate-v2 dual-writes to NOTEBOOK_DIR; kernel_runner uses resolve_notebook_path; docker shares jupyter_notebooks volume with suite_api; Run step UI no longer shows success on error."
```

---

## Self-Review Checklist

| Spec requirement | Task |
|------------------|------|
| Notebook 2 generates successfully | Already works — Task 7 verifies |
| Run step executes without 404 | Tasks 1–5 |
| No false "Training complete" on error | Task 6 |
| Live metrics during run | Task 2 |
| Docker + native dev both work | Tasks 4–5 |
| Actionable error messages | Tasks 1, 6 |

**Placeholder scan:** none — all steps include concrete code and commands.

**Type consistency:** `resolve_notebook_path` used by `kernel_runner.run_notebook`; `workspace_folder` from generate-v2 remains `{slug}/notebooks/{filename}` relative path.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-19-cnlstudio-run-step-training-404.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
