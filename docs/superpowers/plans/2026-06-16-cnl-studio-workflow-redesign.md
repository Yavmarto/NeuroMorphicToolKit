# CNL Studio Workflow Redesign — Steps 1, 6, 7

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three broken or misaligned workflow steps: consolidate hardware target management into step 1 with reachability indicators, replace the empty step 6 stub with a live canvas animation driven by notebook execution, and replace step 7's deployment panel with a post-training replay scrubber and hub share.

**Architecture:** The backend gains two new routers — `kernel_runner.py` (executes a notebook via `jupyter_client`, publishing `__nmtk_progress__` stdout lines to the existing `progress_bus`) and `target_reachability.py` (per-target connectivity checks). Both reuse the existing `job_store` and SSE stream at `/api/training/jobs/{job_id}/events`. The Flutter side extends `TrainingEpochEvent` with `accuracy` and `layerSpikeRates`, adds a `trainingModeProvider` for canvas coloring, and replaces the step 6 and 7 widgets.

**Tech Stack:** Python 3.12, FastAPI, `jupyter_client` (AsyncKernelManager), `nbformat`, `sse_starlette`, Dart/Flutter, Riverpod v2, nmtk_ui_core design tokens.

---

## File Map

### Create
- `neurocnl/backend/app/routers/target_reachability.py` — per-target reachability endpoints
- `neurocnl/backend/app/routers/kernel_runner.py` — notebook execution + job lifecycle
- `neurocnl/backend/tests/test_target_reachability.py`
- `neurocnl/backend/tests/test_kernel_runner.py`
- `neurocnl/frontend/lib/providers/training_mode_provider.dart` — `nodeId → spikeRate` overlay state
- `neurocnl/frontend/lib/providers/training_history_provider.dart` — epoch snapshot list for scrubber
- `neurocnl/frontend/lib/providers/hardware_reachability_provider.dart` — polls `/api/targets/{id}/reachability`
- `neurocnl/frontend/lib/screens/studio/steps/run_step.dart` — step 6 widget
- `neurocnl/frontend/lib/screens/studio/steps/results_step.dart` — step 7 widget

### Modify
- `neurocnl/backend/app/routers/notebook.py` — inject `_nmtk_emit` helper into generated notebooks
- `neurocnl/backend/app/main.py` — register two new routers
- `neurocnl/frontend/lib/models/training.dart` — add `accuracy`, `layerSpikeRates` to `TrainingEpochEvent`
- `neurocnl/frontend/lib/providers/training_provider.dart` — add `runNotebook()` method, propagate new fields
- `neurocnl/frontend/lib/services/api_client.dart` — add `runNotebook()` call
- `neurocnl/frontend/lib/screens/studio/steps/setup_step.dart` — add reachability indicators + manage targets button
- `neurocnl/frontend/lib/screens/studio_screen.dart` — swap step 5 → `RunStep`, step 6 → `ResultsStep`, remove manage targets wiring
- `neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart` — remove manage targets button
- `neurocnl/frontend/lib/widgets/canvas/canvas_cnl_editor.dart` — add `trainingOverlay` parameter

---

## Task 1 — Backend: Target Reachability Endpoint

**Files:**
- Create: `neurocnl/backend/app/routers/target_reachability.py`
- Create: `neurocnl/backend/tests/test_target_reachability.py`
- Modify: `neurocnl/backend/app/main.py`

- [ ] **Step 1.1: Write the failing tests**

```python
# neurocnl/backend/tests/test_target_reachability.py
"""Tests for /api/targets/{target_id}/reachability endpoint."""
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


def test_simulator_reachable_when_sdk_installed():
    with patch("importlib.util.find_spec", return_value=MagicMock()):
        resp = client.get("/api/targets/snntorch_sim/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is True


def test_simulator_unreachable_when_sdk_missing():
    with patch("importlib.util.find_spec", return_value=None):
        resp = client.get("/api/targets/snntorch_sim/reachability")
    assert resp.status_code == 200
    data = resp.json()
    assert data["reachable"] is False
    assert "not installed" in data["detail"]


def test_akida_reachable_when_devices_present():
    with patch("importlib.util.find_spec", return_value=MagicMock()):
        with patch.dict("sys.modules", {"akida": MagicMock(devices=lambda: [MagicMock()])}):
            resp = client.get("/api/targets/akida/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is True


def test_akida_unreachable_when_no_devices():
    with patch("importlib.util.find_spec", return_value=MagicMock()):
        with patch.dict("sys.modules", {"akida": MagicMock(devices=lambda: [])}):
            resp = client.get("/api/targets/akida/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False


def test_unknown_target_returns_false():
    resp = client.get("/api/targets/unknown_target/reachability")
    assert resp.status_code == 200
    assert resp.json()["reachable"] is False
    assert "unknown target" in resp.json()["detail"]
```

- [ ] **Step 1.2: Run tests to confirm failure**

```bash
cd neurocnl/backend && pytest tests/test_target_reachability.py -v
```

Expected: `ImportError` or 404 (router not yet registered).

- [ ] **Step 1.3: Implement the router**

```python
# neurocnl/backend/app/routers/target_reachability.py
"""Per-target hardware reachability checks."""
from __future__ import annotations

import asyncio
import importlib.util

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()

SIMULATOR_SDK: dict[str, str] = {
    "snntorch_sim": "snntorch",
    "lava_sim": "lava",
    "sc_neurocore_sim": "scnn",
    "brian2_sim": "brian2",
    "rockpool_sim": "rockpool",
    "sinabs_sim": "sinabs",
    "nengo_sim": "nengo",
}


class ReachabilityResponse(BaseModel):
    reachable: bool
    detail: str


@router.get("/targets/{target_id}/reachability", response_model=ReachabilityResponse)
async def check_reachability(target_id: str) -> ReachabilityResponse:
    if target_id in SIMULATOR_SDK:
        pkg = SIMULATOR_SDK[target_id]
        if importlib.util.find_spec(pkg):
            return ReachabilityResponse(reachable=True, detail="simulator ready")
        return ReachabilityResponse(reachable=False, detail=f"{pkg} not installed")

    match target_id:
        case "akida":
            return await _check_akida()
        case "neurochip":
            return await _check_neurochip()
        case "sc_neurocore_fpga":
            return await _check_sc_neurocore_fpga()
        case "lava" | "lava_loihi2":
            return await _check_lava_hw()
        case _:
            return ReachabilityResponse(reachable=False, detail=f"unknown target: {target_id}")


async def _check_akida() -> ReachabilityResponse:
    if not importlib.util.find_spec("akida"):
        return ReachabilityResponse(reachable=False, detail="akida SDK not installed")
    try:
        import akida  # noqa: PLC0415
        devices = akida.devices()
        if devices:
            return ReachabilityResponse(reachable=True, detail=f"{len(devices)} device(s) found")
        return ReachabilityResponse(reachable=False, detail="no Akida devices connected")
    except Exception as exc:  # noqa: BLE001
        return ReachabilityResponse(reachable=False, detail=str(exc))


async def _check_neurochip() -> ReachabilityResponse:
    if not importlib.util.find_spec("serial"):
        return ReachabilityResponse(reachable=False, detail="pyserial not installed")
    try:
        import serial.tools.list_ports  # noqa: PLC0415
        ports = [
            p for p in serial.tools.list_ports.comports()
            if any(kw in p.description.lower() for kw in ("neurochip", "teensy"))
        ]
        if ports:
            return ReachabilityResponse(reachable=True, detail=f"found: {ports[0].device}")
        return ReachabilityResponse(reachable=False, detail="no Neurochip/Teensy on serial ports")
    except Exception as exc:  # noqa: BLE001
        return ReachabilityResponse(reachable=False, detail=str(exc))


async def _check_sc_neurocore_fpga() -> ReachabilityResponse:
    # SC-NeuroCore target IP is stored by the ScNeurocoreService.
    # If no targets are configured, report unreachable.
    try:
        from backend.app.services.sc_neurocore_service import ScNeurocoreService  # noqa: PLC0415
        svc = ScNeurocoreService()
        targets = await svc.list_targets()
        if not targets:
            return ReachabilityResponse(reachable=False, detail="no targets configured")
        host, port = targets[0].host, targets[0].port
        try:
            _, writer = await asyncio.wait_for(
                asyncio.open_connection(host, port), timeout=2.0
            )
            writer.close()
            return ReachabilityResponse(reachable=True, detail=f"reachable at {host}:{port}")
        except (TimeoutError, OSError):
            return ReachabilityResponse(reachable=False, detail=f"cannot reach {host}:{port}")
    except ImportError:
        return ReachabilityResponse(reachable=False, detail="SC-NeuroCore service not available")
    except Exception as exc:  # noqa: BLE001
        return ReachabilityResponse(reachable=False, detail=str(exc))


async def _check_lava_hw() -> ReachabilityResponse:
    if not importlib.util.find_spec("lava"):
        return ReachabilityResponse(reachable=False, detail="lava SDK not installed")
    return ReachabilityResponse(reachable=True, detail="lava installed (Loihi 2 sim mode)")
```

- [ ] **Step 1.4: Register the router in main.py**

In `neurocnl/backend/app/main.py`, add alongside the existing imports and `include_router` calls:

```python
# With the other router imports (alphabetical):
from backend.app.routers import target_reachability

# With the other app.include_router calls:
app.include_router(target_reachability.router, prefix="/api", tags=["targets"])
```

- [ ] **Step 1.5: Run tests to confirm passing**

```bash
cd neurocnl/backend && pytest tests/test_target_reachability.py -v
```

Expected: all 5 tests PASS.

- [ ] **Step 1.6: Commit**

```bash
git add neurocnl/backend/app/routers/target_reachability.py \
        neurocnl/backend/app/main.py \
        neurocnl/backend/tests/test_target_reachability.py
git commit -m "feat(neurocnl): add /api/targets/{id}/reachability endpoint"
```

---

## Task 2 — Backend: Notebook Kernel Runner

**Files:**
- Create: `neurocnl/backend/app/routers/kernel_runner.py`
- Create: `neurocnl/backend/tests/test_kernel_runner.py`
- Modify: `neurocnl/backend/app/main.py`

- [ ] **Step 2.1: Write the failing tests**

```python
# neurocnl/backend/tests/test_kernel_runner.py
"""Tests for POST /api/notebook/run."""
import json
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)


def test_run_notebook_returns_job_id(tmp_path):
    nb_path = tmp_path / "test.ipynb"
    nb_path.write_text(json.dumps({"nbformat": 4, "nbformat_minor": 5, "cells": [], "metadata": {}}))

    with patch("backend.app.routers.kernel_runner._execute_notebook", new=AsyncMock()):
        resp = client.post("/api/notebook/run", json={
            "notebook_path": str(nb_path),
            "platform": "snntorch_sim",
        })

    assert resp.status_code == 202
    data = resp.json()
    assert "job_id" in data
    assert len(data["job_id"]) == 36  # UUID


def test_run_notebook_404_for_missing_path():
    resp = client.post("/api/notebook/run", json={
        "notebook_path": "/nonexistent/path/nb.ipynb",
        "platform": "snntorch_sim",
    })
    assert resp.status_code == 404


def test_maybe_publish_ignores_non_progress_lines():
    from backend.app.routers.kernel_runner import _maybe_publish

    published = []
    _maybe_publish('{"some": "data"}', "snntorch_sim", published.append)
    assert published == []


def test_maybe_publish_emits_progress_events():
    from backend.app.routers.kernel_runner import _maybe_publish

    published = []
    line = json.dumps({
        "__nmtk_progress__": True,
        "epoch": 3,
        "total_epochs": 10,
        "loss": 0.5,
        "accuracy": 0.8,
        "layer_spike_rates": {"layer_0": 0.12},
    })
    _maybe_publish(line, "snntorch_sim", published.append)

    assert len(published) == 1
    event = published[0]
    assert event["type"] == "epoch"
    assert event["epoch"] == 3
    assert event["platform"] == "snntorch_sim"
    assert event["accuracy"] == 0.8
    assert event["layer_spike_rates"] == {"layer_0": 0.12}
    assert "__nmtk_progress__" not in event
```

- [ ] **Step 2.2: Run tests to confirm failure**

```bash
cd neurocnl/backend && pytest tests/test_kernel_runner.py -v
```

Expected: `ImportError` or 404.

- [ ] **Step 2.3: Implement the router**

```python
# neurocnl/backend/app/routers/kernel_runner.py
"""Execute a generated Jupyter notebook as a tracked background job.

Emits ``__nmtk_progress__``-tagged stdout lines as SSE ``epoch`` events
on the existing ``/api/training/jobs/{job_id}/events`` stream.
"""
from __future__ import annotations

import asyncio
import json
from collections.abc import Callable
from pathlib import Path
from typing import Any

import nbformat
import structlog
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from backend.app.schemas.jobs import JobQueued
from backend.app.services.job_store import job_store
from backend.app.services.progress_bus import progress_bus

logger = structlog.get_logger(__name__)
router = APIRouter()

ProgressCallback = Callable[[dict[str, Any]], None]


class NotebookRunRequest(BaseModel):
    notebook_path: str
    platform: str
    kernel_name: str = "python3"


@router.post("/notebook/run", response_model=JobQueued, status_code=202)
async def run_notebook(body: NotebookRunRequest) -> JobQueued:
    path = Path(body.notebook_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"Notebook not found: {body.notebook_path}")

    job_id = await job_store.create()
    asyncio.create_task(
        _execute_notebook(job_id, path, body.platform, body.kernel_name),
        name=f"notebook-{job_id[:8]}",
    )
    return JobQueued(job_id=job_id, request_id=None)


async def _execute_notebook(
    job_id: str, path: Path, platform: str, kernel_name: str
) -> None:
    await job_store.set_running(job_id)
    publish = progress_bus.publisher_for(job_id)
    try:
        nb = nbformat.read(path, as_version=4)
        import jupyter_client  # noqa: PLC0415

        km = jupyter_client.AsyncKernelManager(kernel_name=kernel_name)
        await km.start_kernel()
        kc = km.client()
        kc.start_channels()
        try:
            for cell in nb.cells:
                if cell.cell_type != "code":
                    continue
                msg_id = kc.execute(cell.source)
                await _drain_cell(kc, msg_id, platform, publish)
        finally:
            kc.stop_channels()
            await km.shutdown_kernel()

        publish({"type": "done", "status": "complete", "result": None, "error": None})
        await job_store.set_complete(job_id, result={"platform": platform})
    except Exception as exc:  # noqa: BLE001
        logger.exception("notebook execution failed", job_id=job_id)
        error = str(exc)
        publish({"type": "failed", "status": "failed", "result": None, "error": error})
        await job_store.set_failed(job_id, error=error)
    finally:
        progress_bus.close(job_id)


async def _drain_cell(kc: Any, msg_id: str, platform: str, publish: ProgressCallback) -> None:
    """Read iopub messages until the kernel goes idle for this cell."""
    while True:
        try:
            msg = await asyncio.wait_for(kc.get_iopub_msg(), timeout=7200)
        except TimeoutError as exc:
            raise RuntimeError("kernel timed out") from exc

        msg_type: str = msg.get("msg_type", "")
        content: dict = msg.get("content", {})
        parent_id: str = msg.get("parent_header", {}).get("msg_id", "")

        if msg_type == "stream" and content.get("name") == "stdout":
            for line in content.get("text", "").splitlines():
                _maybe_publish(line.strip(), platform, publish)

        if msg_type == "status" and content.get("execution_state") == "idle":
            if parent_id == msg_id:
                return

        if msg_type in ("error", "execute_reply") and parent_id == msg_id:
            if msg_type == "error" or content.get("status") == "error":
                ename = content.get("ename", "Error")
                evalue = content.get("evalue", "")
                raise RuntimeError(f"{ename}: {evalue}")


def _maybe_publish(line: str, platform: str, publish: ProgressCallback) -> None:
    if not line:
        return
    try:
        data = json.loads(line)
    except json.JSONDecodeError:
        return
    if not data.get("__nmtk_progress__"):
        return
    event = {k: v for k, v in data.items() if k != "__nmtk_progress__"}
    event["type"] = "epoch"
    event["platform"] = platform
    publish(event)
```

- [ ] **Step 2.4: Register the router in main.py**

```python
# Add with other imports:
from backend.app.routers import kernel_runner

# Add with other include_router calls:
app.include_router(kernel_runner.router, prefix="/api")
```

- [ ] **Step 2.5: Run tests to confirm passing**

```bash
cd neurocnl/backend && pytest tests/test_kernel_runner.py -v
```

Expected: all 4 tests PASS.

- [ ] **Step 2.6: Commit**

```bash
git add neurocnl/backend/app/routers/kernel_runner.py \
        neurocnl/backend/app/main.py \
        neurocnl/backend/tests/test_kernel_runner.py
git commit -m "feat(neurocnl): add /api/notebook/run kernel execution endpoint"
```

---

## Task 3 — Backend: Inject Progress Markers into Generated Notebooks

**Files:**
- Modify: `neurocnl/backend/app/routers/notebook.py`
- Modify: `neurocnl/backend/tests/test_notebook_progress.py` (add to existing test file, or create new)

The `generate-v2` handler in `notebook.py` generates cell lists for each platform. Two changes are needed: (a) add a helper cell that defines `_nmtk_emit`, and (b) insert a `_nmtk_emit(...)` call at the end of each epoch loop inside the framework-specific training cell.

- [ ] **Step 3.1: Write failing test for helper cell injection**

```python
# neurocnl/backend/tests/test_notebook_progress.py
"""Tests verifying __nmtk_progress__ markers are injected into generated notebooks."""
import json
from fastapi.testclient import TestClient
from backend.app.main import app

client = TestClient(app)

MINIMAL_PAYLOAD = {
    "spec": "network N:\n  input: 784\n  output: 10\n",
    "pipeline_config": {
        "framework": "snntorch_sim",
        "learning_rate": 0.001,
        "epochs": 3,
        "batch_size": 64,
    },
    "pipeline_phases": {
        "train": {"nodes": [], "edges": []},
        "eval": {"nodes": [], "edges": []},
        "infer": {"nodes": [], "edges": []},
    },
}


def test_generated_notebook_contains_nmtk_emit_helper(tmp_path):
    resp = client.post("/api/notebook/generate-v2", json=MINIMAL_PAYLOAD)
    assert resp.status_code == 200
    data = resp.json()
    # Find the generated notebook file and read it
    import nbformat, pathlib
    nb_paths = list(pathlib.Path(data["workspace_folder"]).rglob("*.ipynb"))
    assert nb_paths, "no notebook generated"
    nb = nbformat.read(nb_paths[0], as_version=4)
    sources = [c.source for c in nb.cells if c.cell_type == "code"]
    assert any("_nmtk_emit" in s for s in sources), "_nmtk_emit helper not found"
    assert any("__nmtk_progress__" in s for s in sources), "progress marker not found"
```

- [ ] **Step 3.2: Run test to confirm failure**

```bash
cd neurocnl/backend && pytest tests/test_notebook_progress.py::test_generated_notebook_contains_nmtk_emit_helper -v
```

Expected: FAIL — `_nmtk_emit` not yet in any notebook cell.

- [ ] **Step 3.3: Add the helper cell into notebook.py**

In `neurocnl/backend/app/routers/notebook.py`, find the `generate-v2` endpoint's cell-building logic. Immediately after the config cell (cell index 2), insert a new hidden code cell:

```python
NMTK_EMIT_CELL_SOURCE = '''\
import json as _json
def _nmtk_emit(epoch: int, total: int, loss: float, accuracy: float, layer_rates: dict) -> None:
    print(_json.dumps({
        "__nmtk_progress__": True,
        "epoch": epoch,
        "total_epochs": total,
        "loss": loss,
        "accuracy": accuracy,
        "layer_spike_rates": layer_rates,
    }), flush=True)
'''

# Insert after config cell in the cell list:
cells.insert(3, nbformat.v4.new_code_cell(source=NMTK_EMIT_CELL_SOURCE))
```

- [ ] **Step 3.4: Add _nmtk_emit call into snnTorch training loop**

Inside `_generate_snntorch_code()` (in `notebook.py`), find the epoch loop and append the emit call at the end:

```python
# At the end of the epoch for-loop, after computing loss and accuracy:
training_code += f"""
    layer_rates = {{name: spk.float().mean().item() for name, spk in spike_outputs.items()}}
    _nmtk_emit(epoch + 1, {epochs}, float(train_loss / len(train_loader)), float(correct / total), layer_rates)
"""
```

Apply the same pattern to `_generate_akida_code()`, `_generate_sc_neurocore_code()`, and any other framework that has an epoch training loop (check for `for epoch in range` in each generator function and add the call after loss computation).

For frameworks without an epoch loop (Brian2, Nengo, PyNN), skip this step — they run in simulation mode, not iterative training.

- [ ] **Step 3.5: Run test to confirm passing**

```bash
cd neurocnl/backend && pytest tests/test_notebook_progress.py -v
```

Expected: PASS.

- [ ] **Step 3.6: Commit**

```bash
git add neurocnl/backend/app/routers/notebook.py \
        neurocnl/backend/tests/test_notebook_progress.py
git commit -m "feat(neurocnl): inject _nmtk_emit progress markers into generated notebooks"
```

---

## Task 4 — Flutter: Extend Training Models + New Providers

**Files:**
- Modify: `neurocnl/frontend/lib/models/training.dart`
- Create: `neurocnl/frontend/lib/providers/training_mode_provider.dart`
- Create: `neurocnl/frontend/lib/providers/training_history_provider.dart`
- Create: `neurocnl/frontend/lib/providers/hardware_reachability_provider.dart`

- [ ] **Step 4.1: Write failing Dart unit test for extended TrainingEpochEvent**

```dart
// neurocnl/frontend/test/models/training_epoch_event_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/training.dart';

void main() {
  group('TrainingEpochEvent.fromJson', () {
    test('parses accuracy and layerSpikeRates fields', () {
      final event = TrainingEpochEvent.fromJson({
        'epoch': 5,
        'total_epochs': 100,
        'loss': 0.42,
        'accuracy': 0.87,
        'layer_spike_rates': {'layer_0': 0.12, 'layer_1': 0.08},
        'platform': 'snntorch_sim',
      });
      expect(event.epoch, equals(5));
      expect(event.accuracy, closeTo(0.87, 0.001));
      expect(event.layerSpikeRates, equals({'layer_0': 0.12, 'layer_1': 0.08}));
      expect(event.platform, equals('snntorch_sim'));
    });

    test('handles missing optional fields gracefully', () {
      final event = TrainingEpochEvent.fromJson({'epoch': 1, 'loss': 0.9});
      expect(event.accuracy, isNull);
      expect(event.layerSpikeRates, isEmpty);
      expect(event.platform, isNull);
    });
  });
}
```

- [ ] **Step 4.2: Run test to confirm failure**

```bash
cd neurocnl/frontend && flutter test test/models/training_epoch_event_test.dart
```

Expected: FAIL — `accuracy`, `layerSpikeRates`, `platform` fields not yet in `TrainingEpochEvent`.

- [ ] **Step 4.3: Extend TrainingEpochEvent in models/training.dart**

Find `TrainingEpochEvent` (around line 24 in `lib/models/training.dart`) and add the three new fields:

```dart
class TrainingEpochEvent {
  final int epoch;
  final int? totalEpochs;
  final double loss;
  final double? accuracy;                        // ← add
  final double? elapsedSeconds;
  final Map<String, double> layerSpikeRates;     // ← add
  final String? platform;                        // ← add
  final bool replayed;

  const TrainingEpochEvent({
    required this.epoch,
    required this.loss,
    this.totalEpochs,
    this.accuracy,                               // ← add
    this.elapsedSeconds,
    this.layerSpikeRates = const {},             // ← add
    this.platform,                               // ← add
    this.replayed = false,
  });

  factory TrainingEpochEvent.fromJson(Map<String, dynamic> json) {
    final rawRates = json['layer_spike_rates'] as Map<String, dynamic>? ?? {};
    return TrainingEpochEvent(
      epoch: (json['epoch'] as num).toInt(),
      loss: (json['loss'] as num).toDouble(),
      totalEpochs: (json['total_epochs'] as num?)?.toInt(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),           // ← add
      elapsedSeconds: (json['elapsed_seconds'] as num?)?.toDouble(),
      layerSpikeRates: rawRates.map((k, v) => MapEntry(k, (v as num).toDouble())),  // ← add
      platform: json['platform'] as String?,                       // ← add
      replayed: json['replayed'] == true,
    );
  }
}
```

- [ ] **Step 4.4: Run test to confirm passing**

```bash
cd neurocnl/frontend && flutter test test/models/training_epoch_event_test.dart
```

Expected: PASS.

- [ ] **Step 4.5: Create trainingModeProvider**

```dart
// neurocnl/frontend/lib/providers/training_mode_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Maps canvas node IDs to their current spike rate (0.0–1.0).
/// Null when training is not active (canvas renders normally).
final trainingModeProvider = StateProvider<Map<String, double>?>((ref) => null);
```

- [ ] **Step 4.6: Create trainingHistoryProvider**

```dart
// neurocnl/frontend/lib/providers/training_history_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/training.dart';

/// Accumulated epoch snapshots per platform, keyed by platform ID.
/// Populated during step 6 (RunStep) and read by step 7 (ResultsStep).
/// Persists for the lifetime of the workspace session.
final trainingHistoryProvider =
    StateProvider<Map<String, List<TrainingEpochEvent>>>((ref) => {});
```

- [ ] **Step 4.7: Create hardwareReachabilityProvider**

```dart
// neurocnl/frontend/lib/providers/hardware_reachability_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import 'api_provider.dart';

/// Checks whether a hardware target is reachable on the server.
/// Returns null while loading, true/false once resolved.
final hardwareReachabilityProvider =
    FutureProvider.family<bool, String>((ref, targetId) async {
  final api = ref.read(apiClientProvider);
  final response = await api.getJson('/targets/$targetId/reachability');
  return (response['reachable'] as bool?) ?? false;
});
```

Note: `api.getJson(path)` should be an existing helper on `ApiClient` that returns `Map<String, dynamic>`. If it's named differently (e.g., `_get`), use that.

- [ ] **Step 4.8: Commit**

```bash
git add neurocnl/frontend/lib/models/training.dart \
        neurocnl/frontend/lib/providers/training_mode_provider.dart \
        neurocnl/frontend/lib/providers/training_history_provider.dart \
        neurocnl/frontend/lib/providers/hardware_reachability_provider.dart \
        neurocnl/frontend/test/models/training_epoch_event_test.dart
git commit -m "feat(neurocnl-frontend): extend TrainingEpochEvent, add trainingMode/history/reachability providers"
```

---

## Task 5 — Flutter: Step 1 UI — Reachability + Move Manage Targets

**Files:**
- Modify: `neurocnl/frontend/lib/screens/studio/steps/setup_step.dart`
- Modify: `neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart`
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart` (remove `onManageHardwareTarget` wiring)

- [ ] **Step 5.1: Add reachability dot to each target in setup_step.dart**

In `setup_step.dart`, within the platform list widget (around lines 207–229), wrap each platform tile with a `Consumer` that reads `hardwareReachabilityProvider(targetId)`:

```dart
// Add import at top:
import '../../../providers/hardware_reachability_provider.dart';

// Inside the platform chip/tile builder, add a reachability indicator:
Consumer(
  builder: (context, ref, _) {
    final reachability = ref.watch(hardwareReachabilityProvider(targetId));
    final dot = reachability.when(
      data: (ok) => _ReachabilityDot(reachable: ok),
      loading: () => const _ReachabilityDot(reachable: null),
      error: (_, __) => const _ReachabilityDot(reachable: false),
    );
    return Row(children: [dot, const SizedBox(width: 6), existingTileWidget]);
  },
)
```

Add the dot widget (keep it self-contained):

```dart
class _ReachabilityDot extends StatelessWidget {
  final bool? reachable; // null = loading

  const _ReachabilityDot({this.reachable});

  @override
  Widget build(BuildContext context) {
    final color = switch (reachable) {
      true  => NmtkShellTokens.colorSuccess,
      false => NmtkShellTokens.colorError,
      null  => NmtkShellTokens.colorMuted,
    };
    return Tooltip(
      message: switch (reachable) {
        true  => 'Reachable',
        false => 'Not reachable',
        null  => 'Checking…',
      },
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
```

- [ ] **Step 5.2: Move "Manage Targets" button to setup_step.dart**

Directly above (or below) the existing multi-select targets button in `setup_step.dart`, add:

```dart
ZetaButton.text(
  label: 'Manage Targets',
  leadingIcon: ZetaIcons.settings_round,
  onPressed: () => showDialog(
    context: context,
    builder: (_) => HardwareTargetDialog(
      targetId: workspace.selectedDeployTarget,
      // Pass same callbacks used in the existing dialog invocation from deploy panel
    ),
  ),
),
```

Copy the exact import and callback pattern from `deploy_workspace_panel.dart` (lines 44–48) since that's the existing dialog invocation.

- [ ] **Step 5.3: Remove "Manage Targets" from deploy_workspace_panel.dart**

In `neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart`, delete lines 44–48 (the `ZetaButton` that opens the hardware target dialog) and any dangling imports that are now unused.

- [ ] **Step 5.4: Remove onManageHardwareTarget wiring from studio_screen.dart**

Search `studio_screen.dart` for `onManageHardwareTarget` and delete the callback assignment and the handler method body. (The dialog is now invoked directly from `setup_step.dart`.)

- [ ] **Step 5.5: Hot-restart and verify step 1 shows dots**

```bash
# In the running flutter dev session, press R (hot-restart)
# Navigate to step 1 — each platform should show a small dot
# The "Manage Targets" button should appear in step 1, not step 7
```

- [ ] **Step 5.6: Commit**

```bash
git add neurocnl/frontend/lib/screens/studio/steps/setup_step.dart \
        neurocnl/frontend/lib/screens/studio/deploy/deploy_workspace_panel.dart \
        neurocnl/frontend/lib/screens/studio_screen.dart
git commit -m "feat(neurocnl-frontend): move target management to step 1 with reachability indicators"
```

---

## Task 6 — Flutter: Canvas Training Overlay + API Client + RunStep

**Files:**
- Modify: `neurocnl/frontend/lib/widgets/canvas/canvas_cnl_editor.dart`
- Modify: `neurocnl/frontend/lib/services/api_client.dart`
- Modify: `neurocnl/frontend/lib/providers/training_provider.dart`
- Create: `neurocnl/frontend/lib/screens/studio/steps/run_step.dart`

- [ ] **Step 6.1: Write failing widget test for RunStep**

```dart
// neurocnl/frontend/test/screens/studio/steps/run_step_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/screens/studio/steps/run_step.dart';

void main() {
  testWidgets('RunStep shows Start Training button when idle', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: Scaffold(body: RunStep()))),
    );
    await tester.pump();
    expect(find.text('Start Training'), findsOneWidget);
  });
}
```

- [ ] **Step 6.2: Run test to confirm failure**

```bash
cd neurocnl/frontend && flutter test test/screens/studio/steps/run_step_test.dart
```

Expected: FAIL — `run_step.dart` does not exist.

- [ ] **Step 6.3: Add runNotebook to ApiClient**

In `neurocnl/frontend/lib/services/api_client.dart`, add after `submitTraining`:

```dart
/// POST /api/notebook/run — starts notebook execution, returns job_id.
Future<String> runNotebook({
  required String notebookPath,
  required String platform,
  String kernelName = 'python3',
}) async {
  final response = await _postJson('/notebook/run', {
    'notebook_path': notebookPath,
    'platform': platform,
    'kernel_name': kernelName,
  });
  return response['job_id'] as String;
}
```

`_postJson` is the existing helper used by other methods. If the naming differs, follow the pattern from `submitTraining`.

- [ ] **Step 6.4: Add runNotebook to TrainingController in training_provider.dart**

```dart
/// Run a generated notebook and stream its progress.
Future<void> runNotebook({
  required String notebookPath,
  required String platform,
}) async {
  state = state.copyWith(
    status: TrainingProviderStatus.submitting,
    clearResult: true,
    clearJob: true,
    clearError: true,
    clearEpochs: true,
    epochTick: 0,
  );
  try {
    final api = ref.read(apiClientProvider);
    final jobId = await api.runNotebook(
      notebookPath: notebookPath,
      platform: platform,
    );
    if (!ref.mounted) return;
    state = state.copyWith(status: TrainingProviderStatus.polling, jobId: jobId);
    _startPolling(jobId);
    _startEventStream(jobId);
  } catch (e) {
    if (!ref.mounted) return;
    state = state.copyWith(
      status: TrainingProviderStatus.failure,
      errorMessage: 'Failed to start notebook: $e',
    );
  }
}
```

- [ ] **Step 6.5: Thread trainingOverlay through CanvasScreen and CanvasCnlEditor**

**In `CanvasCnlEditor`** (`lib/widgets/canvas/canvas_cnl_editor.dart`), add:

```dart
final Map<String, double>? trainingOverlay;
```

Inside the node rendering (where each `CanvasNode` is drawn), when `trainingOverlay` is non-null and contains the node's ID, apply a color overlay:

```dart
// Inside the node painter / build method:
if (trainingOverlay != null) {
  final rate = trainingOverlay![node.id];
  if (rate != null) {
    final overlayColor = Color.lerp(
      const Color(0xFF1565C0), // cool blue — silent
      const Color(0xFFE65100), // warm orange — saturated
      rate.clamp(0.0, 1.0),
    )!.withValues(alpha: 0.55);
    // Paint the overlay on top of the existing node background
    canvas.drawRRect(nodeRRect, Paint()..color = overlayColor);
  }
}
```

Find where `CanvasNode` background color is set (grep for `nodeBackground` or `canvasNodeColor` in the file) and add the overlay immediately after.

**In `CanvasScreen`** (`lib/screens/canvas/canvas_screen.dart`), add the same `trainingOverlay` parameter and pass it down to `CanvasCnlEditor`:

```dart
// Add to CanvasScreen constructor:
final Map<String, double>? trainingOverlay;

// Pass to CanvasCnlEditor where it is instantiated inside CanvasScreen:
CanvasCnlEditor(
  ..., // existing params
  trainingOverlay: trainingOverlay,
)
```

- [ ] **Step 6.6: Create run_step.dart**

```dart
// neurocnl/frontend/lib/screens/studio/steps/run_step.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import '../../../models/training.dart';
import '../../../providers/training_history_provider.dart';
import '../../../providers/training_mode_provider.dart';
import '../../../providers/training_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../canvas/canvas_screen.dart';

class RunStep extends ConsumerWidget {
  const RunStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final trainingState = ref.watch(trainingControllerProvider);
    final platforms = workspace.selectedPlatforms;
    final selectedPlatform = platforms.isNotEmpty ? platforms.first : null;

    return Column(
      children: [
        // Platform tabs
        if (platforms.length > 1)
          _PlatformTabs(platforms: platforms),
        Expanded(
          child: Row(
            children: [
              // Architecture canvas — read-only during training
              Expanded(
                flex: 2,
                child: _AnimatedCanvas(
                  trainingState: trainingState,
                  platform: selectedPlatform,
                ),
              ),
              // Live metrics sidebar
              SizedBox(
                width: 240,
                child: _MetricsSidebar(trainingState: trainingState),
              ),
            ],
          ),
        ),
        // Controls bar
        _ControlsBar(
          trainingState: trainingState,
          platform: selectedPlatform,
          workspace: workspace,
        ),
      ],
    );
  }
}

class _AnimatedCanvas extends ConsumerWidget {
  final TrainingProviderState trainingState;
  final String? platform;
  const _AnimatedCanvas({required this.trainingState, required this.platform});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build overlay map from the latest epoch event for this platform
    Map<String, double>? overlay;
    if (trainingState.epochs.isNotEmpty && platform != null) {
      final latest = trainingState.epochs.lastWhere(
        (e) => e.platform == platform || e.platform == null,
        orElse: () => trainingState.epochs.last,
      );
      if (latest.layerSpikeRates.isNotEmpty) {
        overlay = latest.layerSpikeRates;
      }
    }
    // Reuse the existing architecture canvas in read-only mode with overlay
    return CanvasScreen(
      mode: CanvasMode.architecture,
      readOnly: true,
      trainingOverlay: overlay,
    );
  }
}

class _MetricsSidebar extends StatelessWidget {
  final TrainingProviderState trainingState;
  const _MetricsSidebar({required this.trainingState});

  @override
  Widget build(BuildContext context) {
    final epochs = trainingState.epochs;
    final latest = epochs.isNotEmpty ? epochs.last : null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Metrics', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _MetricRow('Epoch', latest != null
              ? '${latest.epoch} / ${latest.totalEpochs ?? '?'}'
              : '—'),
          _MetricRow('Loss', latest != null ? latest.loss.toStringAsFixed(4) : '—'),
          _MetricRow('Accuracy', latest?.accuracy != null
              ? '${(latest!.accuracy! * 100).toStringAsFixed(1)}%'
              : '—'),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetricRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ControlsBar extends ConsumerWidget {
  final TrainingProviderState trainingState;
  final String? platform;
  final dynamic workspace; // WorkspaceState

  const _ControlsBar({
    required this.trainingState,
    required this.platform,
    required this.workspace,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = trainingState.status == TrainingProviderStatus.polling ||
        trainingState.status == TrainingProviderStatus.submitting;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ZetaButton(
            label: 'Start Training',
            leadingIcon: ZetaIcons.play_round,
            onPressed: isRunning || platform == null
                ? null
                : () => _startTraining(ref, platform!),
          ),
          const SizedBox(width: 8),
          if (isRunning)
            ZetaButton.outlined(
              label: 'Stop',
              leadingIcon: ZetaIcons.stop_round,
              onPressed: () => ref.read(trainingControllerProvider.notifier).reset(),
            ),
          if (trainingState.status == TrainingProviderStatus.success) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 4),
            const Text('Training complete'),
          ],
        ],
      ),
    );
  }

  void _startTraining(WidgetRef ref, String platform) {
    // Notebook path: convention from notebook.py — workspace_folder/notebooks/{platform}.ipynb
    final workspaceName = workspace.workspaceName;
    final notebookPath = '/workspace/notebooks/$workspaceName/${platform}.ipynb';
    ref.read(trainingControllerProvider.notifier).runNotebook(
      notebookPath: notebookPath,
      platform: platform,
    );
  }
}

class _PlatformTabs extends StatelessWidget {
  final List<String> platforms;
  const _PlatformTabs({required this.platforms});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: platforms
            .map((p) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(label: Text(p)),
                ))
            .toList(),
      ),
    );
  }
}
```

Note on `notebookPath`: The `generate-v2` endpoint returns `workspace_folder` in its response. The `notebook_step.dart` already holds this path. Add a `generatedNotebookPaths` provider (a `Map<String, String>` of platform → path) to the workspace state, populated when notebooks are generated in step 5. Then use that in `_startTraining`. Alternatively, derive the path from the `generate-v2` response already stored in `PipelineState.generateResult`.

- [ ] **Step 6.7: Persist epoch data to trainingHistoryProvider**

In `training_provider.dart`, in `_handleEvent`, after updating `state.epochs`, also write to `trainingHistoryProvider`:

```dart
void _handleEvent(Map<String, dynamic> event) {
  if (!ref.mounted) return;
  final type = event['type'] as String?;
  if (type == 'epoch') {
    final epoch = TrainingEpochEvent.fromJson(event);
    state = state.copyWith(
      epochs: [...state.epochs, epoch],
      epochTick: state.epochTick + 1,
    );
    // Persist to history for step 7 scrubber
    final platform = epoch.platform ?? 'default';
    final history = Map<String, List<TrainingEpochEvent>>.from(
      ref.read(trainingHistoryProvider),
    );
    history[platform] = [...(history[platform] ?? []), epoch];
    ref.read(trainingHistoryProvider.notifier).state = history;
  }
}
```

- [ ] **Step 6.8: Run the widget test**

```bash
cd neurocnl/frontend && flutter test test/screens/studio/steps/run_step_test.dart
```

Expected: PASS.

- [ ] **Step 6.9: Commit**

```bash
git add neurocnl/frontend/lib/screens/studio/steps/run_step.dart \
        neurocnl/frontend/lib/services/api_client.dart \
        neurocnl/frontend/lib/providers/training_provider.dart \
        neurocnl/frontend/lib/widgets/canvas/canvas_cnl_editor.dart \
        neurocnl/frontend/test/screens/studio/steps/run_step_test.dart
git commit -m "feat(neurocnl-frontend): add RunStep with live canvas animation and epoch metrics"
```

---

## Task 7 — Flutter: ResultsStep + Studio Screen Wiring

**Files:**
- Create: `neurocnl/frontend/lib/screens/studio/steps/results_step.dart`
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`

- [ ] **Step 7.1: Write failing widget test for ResultsStep**

```dart
// neurocnl/frontend/test/screens/studio/steps/results_step_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/providers/training_history_provider.dart';
import 'package:neuro_toolkit/models/training.dart';
import 'package:neuro_toolkit/screens/studio/steps/results_step.dart';

void main() {
  testWidgets('ResultsStep shows Share to Hub button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingHistoryProvider.overrideWith((ref) => {
            'snntorch_sim': [
              const TrainingEpochEvent(epoch: 1, loss: 0.9, accuracy: 0.5, layerSpikeRates: {}),
              const TrainingEpochEvent(epoch: 2, loss: 0.5, accuracy: 0.8, layerSpikeRates: {}),
            ],
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: ResultsStep())),
      ),
    );
    await tester.pump();
    expect(find.text('Share to Hub'), findsOneWidget);
  });

  testWidgets('ResultsStep shows epoch scrubber when history is present', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingHistoryProvider.overrideWith((ref) => {
            'snntorch_sim': [
              const TrainingEpochEvent(epoch: 1, loss: 0.9, layerSpikeRates: {}),
            ],
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: ResultsStep())),
      ),
    );
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
  });
}
```

- [ ] **Step 7.2: Run test to confirm failure**

```bash
cd neurocnl/frontend && flutter test test/screens/studio/steps/results_step_test.dart
```

Expected: FAIL — `results_step.dart` does not exist.

- [ ] **Step 7.3: Create results_step.dart**

```dart
// neurocnl/frontend/lib/screens/studio/steps/results_step.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import '../../../models/training.dart';
import '../../../providers/training_history_provider.dart';
import '../../../providers/training_mode_provider.dart';
import '../../../providers/workspace_provider.dart';
import '../../canvas/canvas_screen.dart';
import '../deploy/deploy_workspace_panel.dart';

class ResultsStep extends ConsumerStatefulWidget {
  const ResultsStep({super.key});

  @override
  ConsumerState<ResultsStep> createState() => _ResultsStepState();
}

class _ResultsStepState extends ConsumerState<ResultsStep> {
  String? _selectedPlatform;
  int _scrubberEpochIndex = 0;

  @override
  void initState() {
    super.initState();
    final history = ref.read(trainingHistoryProvider);
    if (history.isNotEmpty) {
      _selectedPlatform = history.keys.first;
      final epochs = history[_selectedPlatform!]!;
      _scrubberEpochIndex = epochs.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(trainingHistoryProvider);
    final platforms = history.keys.toList();
    final platform = _selectedPlatform ?? (platforms.isNotEmpty ? platforms.first : null);
    final epochs = platform != null ? (history[platform] ?? []) : <TrainingEpochEvent>[];
    final selectedEpoch = epochs.isNotEmpty ? epochs[_scrubberEpochIndex.clamp(0, epochs.length - 1)] : null;
    final overlay = selectedEpoch?.layerSpikeRates.isNotEmpty == true
        ? selectedEpoch!.layerSpikeRates
        : null;

    return Column(
      children: [
        if (platforms.length > 1)
          _PlatformBar(
            platforms: platforms,
            selected: platform,
            onSelect: (p) => setState(() => _selectedPlatform = p),
          ),
        Expanded(
          child: Row(
            children: [
              // Replay canvas
              Expanded(
                flex: 2,
                child: CanvasScreen(
                  mode: CanvasMode.architecture,
                  readOnly: true,
                  trainingOverlay: overlay,
                ),
              ),
              // Metrics + scrubber + actions
              SizedBox(
                width: 260,
                child: _ResultsSidebar(
                  epochs: epochs,
                  selectedIndex: _scrubberEpochIndex,
                  onScrub: (i) => setState(() => _scrubberEpochIndex = i),
                ),
              ),
            ],
          ),
        ),
        // Deploy section (existing widgets, no manage targets)
        ExpansionTile(
          title: const Text('Deploy to hardware'),
          children: [DeployWorkspacePanel()],
        ),
      ],
    );
  }
}

class _ResultsSidebar extends StatelessWidget {
  final List<TrainingEpochEvent> epochs;
  final int selectedIndex;
  final ValueChanged<int> onScrub;

  const _ResultsSidebar({
    required this.epochs,
    required this.selectedIndex,
    required this.onScrub,
  });

  @override
  Widget build(BuildContext context) {
    final selected = epochs.isNotEmpty
        ? epochs[selectedIndex.clamp(0, epochs.length - 1)]
        : null;
    final best = epochs.isNotEmpty
        ? epochs.reduce((a, b) => (a.accuracy ?? 0) > (b.accuracy ?? 0) ? a : b)
        : null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Results', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (epochs.isNotEmpty) ...[
            Text('Epoch ${selected?.epoch ?? '—'} / ${epochs.last.totalEpochs ?? epochs.length}'),
            Slider(
              value: selectedIndex.toDouble(),
              min: 0,
              max: (epochs.length - 1).toDouble().clamp(0, double.infinity),
              divisions: epochs.length > 1 ? epochs.length - 1 : 1,
              onChanged: (v) => onScrub(v.round()),
            ),
          ],
          const Divider(),
          Text('Best accuracy: ${best?.accuracy != null ? '${(best!.accuracy! * 100).toStringAsFixed(1)}%' : '—'}'),
          Text('Final loss: ${selected?.loss.toStringAsFixed(4) ?? '—'}'),
          const Spacer(),
          ZetaButton(
            label: 'Share to Hub',
            leadingIcon: ZetaIcons.upload_round,
            isFullWidth: true,
            onPressed: () => _shareToHub(context),
          ),
        ],
      ),
    );
  }

  void _shareToHub(BuildContext context) {
    // Replicate the hub publish invocation from deploy_workspace_panel.dart lines ~164–172.
    // That card calls the same provider/service for hub sharing. Copy the exact call here
    // (it will be a ref.read(hubPublishProvider.notifier).publish(...) or similar).
    // Do not reimplement — find and reuse the existing hub publish logic.
  }
}

class _PlatformBar extends StatelessWidget {
  final List<String> platforms;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _PlatformBar({required this.platforms, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: platforms
          .map((p) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: ChoiceChip(
                  label: Text(p),
                  selected: p == selected,
                  onSelected: (_) => onSelect(p),
                ),
              ))
          .toList(),
    );
  }
}
```

Note on `_shareToHub`: Find the existing hub publish logic in the old `deploy_workspace_panel.dart` (lines ~164–172) and call the same provider/service from here instead of the SnackBar placeholder.

- [ ] **Step 7.4: Swap step widgets in studio_screen.dart**

In `studio_screen.dart`, in the `_buildStepContent(int index)` switch:

```dart
// Before:
5 => const TrainingInspectorPanel(),
// (step 6 was `_ => _buildDeployPanel()`)

// After:
5 => const RunStep(),
6 => const ResultsStep(),
```

Add the new imports at the top:
```dart
import 'screens/studio/steps/run_step.dart';
import 'screens/studio/steps/results_step.dart';
```

Remove the import for `TrainingInspectorPanel` if nothing else uses it. The `featureFlags.trainingPanelEnabled` guard (if present around `TrainingInspectorPanel`) should be removed.

- [ ] **Step 7.5: Run all Flutter tests**

```bash
cd neurocnl/frontend && flutter test
```

Expected: all existing tests pass, new tests pass.

- [ ] **Step 7.6: Commit**

```bash
git add neurocnl/frontend/lib/screens/studio/steps/results_step.dart \
        neurocnl/frontend/lib/screens/studio_screen.dart \
        neurocnl/frontend/test/screens/studio/steps/results_step_test.dart
git commit -m "feat(neurocnl-frontend): add ResultsStep with epoch scrubber and share to hub"
```

---

## Verification

1. **Step 1 reachability**: Go to step 1, select a platform. Each platform chip shows a colored dot. The "Manage Targets" button is present in step 1. Go to step 7 — no "Manage Targets" button.

2. **Step 6 live training**: Select `snntorch_sim`, complete steps 1–5. In step 6, click "Start Training". Canvas node colors animate warm as training progresses. Epoch counter and loss update in the sidebar. When training completes, a "Training complete" indicator appears.

3. **Step 7 replay**: Navigate to step 7 after training. Scrubber is present and spans all epochs. Drag it — canvas node colors update. "Share to Hub" button is visible.

4. **Backend SSE integration**: While step 6 is running, open browser DevTools → Network → filter by `events`. Confirm `text/event-stream` is receiving `{"type":"epoch",...}` events.

5. **Multi-platform**: Select two platforms. Step 6 shows platform tabs; each has its own canvas state. Step 7 shows platform tabs for scrubbing each separately.

6. **All tests**: `cd neurocnl/backend && pytest tests/ -v` and `cd neurocnl/frontend && flutter test` both pass with no regressions.
