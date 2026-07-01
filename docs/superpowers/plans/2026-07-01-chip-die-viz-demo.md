# Chip-Die Viz-Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `/viz-demo`'s raw-particle visualization with a per-core "chip-die" tile grid, fixing the 100k/1M stutter via server-side aggregation and giving the demo real meaning tied to actual neuromorphic hardware core counts.

**Architecture:** The backend aggregates synthetic Poisson spikes into a small per-tile `[activity, concentration]` payload (one tile per chip core, or a scale-derived virtual grid in "Software / Simulated" mode) instead of streaming raw per-spike data. The frontend gets a brand-new, self-contained `TileGridNeuronRenderer` + `TileActivityFrame` type — it does **not** reuse the existing `NeuronRenderer`/`VisualizationFrame`/`fragment_shader_renderer.dart`/`wgpu_native_renderer.dart`/`renderer_registry.dart` code, all of which are left completely untouched (still compiling, just no longer referenced by `viz_demo_screen.dart`). This avoids any risk of breaking those files or the shared `BulkSpikeFrame`/`PreviewPlayback` contract, which is also used by the real (non-demo) simulation-preview pipeline (`density_aggregator.py`, `canvas_simulation_surface.dart`) and must not change.

**Tech Stack:** FastAPI WebSocket + numpy (backend, `neurocnl/neurosim`), Flutter/Dart `CustomPainter` + `InteractiveViewer` (frontend, `nmtk_ui_core` + `neurocnl/frontend`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-01-chip-die-viz-demo-design.md` — read it first for the "why" behind every number below.
- Do not modify `neurocnl/neurosim/contracts/design_contracts.py`'s `BulkSpikeFrame`/`PreviewPlayback` — they are shared with the real simulation-preview pipeline. This feature uses its own new `TileActivityFrame` type (Python, in `poisson_demo_generator.py`) and its own WebSocket message envelope.
- Do not modify or delete `nmtk_ui_core/lib/visualization/renderer_interface.dart`, `fragment_shader_renderer.dart`, `wgpu_native_renderer.dart`, or `renderer_registry.dart`. They become unused by `viz_demo_screen.dart` after this plan but must keep compiling as-is (candidates for a separate future cleanup, not part of this plan).
- Chip core counts / neuron capacities always come from `Neurochip/neurochip/targets/*.json` at runtime (backend) — never hardcode a duplicate numeric table. The frontend only duplicates chip **id + display label** strings for the dropdown (no numbers).
- `Neurochip/neurochip/targets/spinnaker2.json`'s `neuron_capacity` (1000) is per-core, unlike every other target file in that directory (which store the chip's total capacity) — must be multiplied by `core_count` when loaded. `teensy41` (1 core) is excluded — a single-core "grid" has no regions to visualize.
- Color scale for tile activity: blue (`0xFF1e3a8f`, low) → red (`0xFFf0453c`, high).

---

## Task 1: Chip target loader (backend)

**Files:**
- Create: `neurocnl/neurosim/app/services/chip_targets.py`
- Test: `neurocnl/neurosim/tests/test_chip_targets.py`

**Interfaces:**
- Produces: `ChipTarget` (NamedTuple: `id: str`, `name: str`, `core_count: int`, `neuron_capacity: int`) and `load_chip_targets() -> dict[str, ChipTarget]`, keyed by `id`. Used by Task 4.

- [ ] **Step 1: Write the failing test**

```python
# neurocnl/neurosim/tests/test_chip_targets.py
from neurosim.app.services.chip_targets import load_chip_targets


def test_load_chip_targets_includes_akida_with_real_core_count():
    targets = load_chip_targets()
    assert targets["akida"].core_count == 80
    assert targets["akida"].neuron_capacity == 1_200_000


def test_load_chip_targets_corrects_spinnaker2_per_core_capacity():
    # spinnaker2.json stores neuron_capacity=1000 as a PER-CORE figure,
    # unlike every other target file (which store the chip's total
    # capacity) — loader must multiply by core_count.
    targets = load_chip_targets()
    assert targets["spinnaker2"].core_count == 152
    assert targets["spinnaker2"].neuron_capacity == 152_000


def test_load_chip_targets_excludes_single_core_targets():
    targets = load_chip_targets()
    assert "teensy41" not in targets


def test_load_chip_targets_returns_seven_usable_targets():
    targets = load_chip_targets()
    expected_ids = {
        "akida", "loihi2", "spinnaker2", "spinnaker",
        "speck2", "brainscales", "pynq_z2",
    }
    assert set(targets.keys()) == expected_ids
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl && python -m pytest neurosim/tests/test_chip_targets.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'neurosim.app.services.chip_targets'`

- [ ] **Step 3: Write minimal implementation**

```python
# neurocnl/neurosim/app/services/chip_targets.py
"""Loads physical core-count/capacity data for named neuromorphic chip
targets, from the same source (`Neurochip/neurochip/targets/*.json`) the
hardware deploy workflow uses — so the viz-demo's chip-die grid stays in
sync with that data instead of duplicating numbers here.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import NamedTuple

# spinnaker2.json's neuron_capacity field is a per-core figure (1000/core),
# unlike every other target file in this directory, which stores the
# chip's total capacity. Correct it here rather than trusting the raw field.
_PER_CORE_CAPACITY_IDS = frozenset({"spinnaker2"})

# Single-core targets have no spatial regions to visualize as a grid.
_EXCLUDED_IDS = frozenset({"teensy41"})

# neurocnl/neurosim/app/services/chip_targets.py -> parents[4] is the repo root.
_TARGETS_DIR = (
    Path(__file__).resolve().parents[4] / "Neurochip" / "neurochip" / "targets"
)


class ChipTarget(NamedTuple):
    """Physical core count and neuron capacity for one supported chip."""

    id: str
    name: str
    core_count: int
    neuron_capacity: int


def load_chip_targets() -> dict[str, ChipTarget]:
    """Load all usable chip targets, keyed by id.

    Skips targets missing core_count/neuron_capacity, single-core targets,
    and any id in _EXCLUDED_IDS. Returns an empty dict if the targets
    directory doesn't exist (e.g. Neurochip submodule not checked out).
    """
    targets: dict[str, ChipTarget] = {}
    if not _TARGETS_DIR.is_dir():
        return targets

    for path in sorted(_TARGETS_DIR.glob("*.json")):
        raw = json.loads(path.read_text())
        target_id = raw.get("id")
        core_count = raw.get("core_count")
        neuron_capacity = raw.get("neuron_capacity")
        if not target_id or not core_count or not neuron_capacity:
            continue
        if target_id in _EXCLUDED_IDS or core_count <= 1:
            continue

        if target_id in _PER_CORE_CAPACITY_IDS:
            neuron_capacity *= core_count

        targets[target_id] = ChipTarget(
            id=target_id,
            name=raw.get("name", target_id),
            core_count=core_count,
            neuron_capacity=neuron_capacity,
        )
    return targets
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd neurocnl && python -m pytest neurosim/tests/test_chip_targets.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git -C neurocnl add neurosim/app/services/chip_targets.py neurosim/tests/test_chip_targets.py
git -C neurocnl commit -m "feat: load neuromorphic chip core-count/capacity data for viz-demo"
```

---

## Task 2: Tile aggregation math (backend)

**Files:**
- Modify: `neurocnl/neurosim/app/services/poisson_demo_generator.py` (add functions; existing `generate_demo_frame` is replaced in Task 3, not this task)
- Test: `neurocnl/neurosim/tests/test_poisson_demo_generator.py` (add new tests; old tests for the current `generate_demo_frame` shape are replaced in Task 3)

**Interfaces:**
- Produces: `near_square_grid(tile_count: int) -> tuple[int, int]`, `resolve_rate_hz(neuron_count: int, tile_count: int, dt_ms: float) -> float`, `aggregate_tile_activity(fired_indices: np.ndarray, neuron_count: int, tile_rows: int, tile_cols: int) -> TileActivityFrame`, and the `TileActivityFrame` Pydantic model (`tile_activity: list[float]`, `tile_concentration: list[float]`, `tile_rows: int`, `tile_cols: int`). Used by Task 3 and Task 4.

- [ ] **Step 1: Write the failing tests**

Add to `neurocnl/neurosim/tests/test_poisson_demo_generator.py` (this file currently tests the old `generate_demo_frame` shape — leave those existing tests as-is for now, they'll be replaced in Task 3; just add these new tests alongside them):

```python
import numpy as np
import pytest

from neurosim.app.services.poisson_demo_generator import (
    aggregate_tile_activity,
    near_square_grid,
    resolve_rate_hz,
)


def test_near_square_grid_exact_square():
    assert near_square_grid(64) == (8, 8)


def test_near_square_grid_akida_80_cores():
    assert near_square_grid(80) == (8, 10)


def test_near_square_grid_tiny_chip():
    assert near_square_grid(2) == (1, 2)


def test_resolve_rate_hz_matches_1m_simulated_preset_closely():
    # Sanity check: the unified formula should land close to the old
    # hand-tuned 1M-scale preset (0.15 Hz -> ~5000 spikes/frame @ 1024 tiles).
    rate = resolve_rate_hz(neuron_count=1_000_000, tile_count=1024, dt_ms=1000.0 / 30.0)
    assert rate == pytest.approx(0.1536, abs=0.01)


def test_resolve_rate_hz_clips_runaway_rate_at_tiny_neuron_count():
    rate = resolve_rate_hz(neuron_count=10, tile_count=64, dt_ms=1000.0 / 30.0)
    assert rate == 50.0


def test_aggregate_tile_activity_edge_concentrated_single_tile():
    # 4 neurons, 1 tile. Only the two "extreme" neurons (index 0 and 3)
    # fire -> activity concentrates at the tile's index edges.
    frame = aggregate_tile_activity(
        fired_indices=np.array([0, 3]),
        neuron_count=4,
        tile_rows=1,
        tile_cols=1,
    )
    assert frame.tile_activity == pytest.approx([1.0])
    assert frame.tile_concentration == pytest.approx([1.0])


def test_aggregate_tile_activity_core_concentrated_single_tile():
    # Same 4 neurons, 1 tile, but only the two "middle" neurons (index 1
    # and 2) fire -> activity concentrates near the tile's index center.
    frame = aggregate_tile_activity(
        fired_indices=np.array([1, 2]),
        neuron_count=4,
        tile_rows=1,
        tile_cols=1,
    )
    assert frame.tile_activity == pytest.approx([1.0])
    assert frame.tile_concentration == pytest.approx([0.3333], abs=0.001)


def test_aggregate_tile_activity_bins_across_multiple_tiles():
    # 8 neurons, 2 tiles (4 neurons each). Only tile 0's neurons fire.
    frame = aggregate_tile_activity(
        fired_indices=np.array([0, 1]),
        neuron_count=8,
        tile_rows=1,
        tile_cols=2,
    )
    assert frame.tile_rows == 1
    assert frame.tile_cols == 2
    assert frame.tile_activity == pytest.approx([1.0, 0.0])
    assert frame.tile_concentration == pytest.approx([0.6667, 0.0], abs=0.001)


def test_aggregate_tile_activity_no_spikes_is_all_zero():
    frame = aggregate_tile_activity(
        fired_indices=np.array([], dtype=np.int64),
        neuron_count=8,
        tile_rows=1,
        tile_cols=2,
    )
    assert frame.tile_activity == [0.0, 0.0]
    assert frame.tile_concentration == [0.0, 0.0]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd neurocnl && python -m pytest neurosim/tests/test_poisson_demo_generator.py -k "near_square or resolve_rate or aggregate_tile" -v`
Expected: FAIL with `ImportError: cannot import name 'aggregate_tile_activity'` (and similar for the other two names)

- [ ] **Step 3: Write minimal implementation**

Add to the top of `neurocnl/neurosim/app/services/poisson_demo_generator.py`, right after the existing imports (`import numpy as np`):

```python
import math

from pydantic import BaseModel, Field


class TileActivityFrame(BaseModel):
    """Per-core-tile aggregated activity for the /viz-demo chip-die view.

    Deliberately NOT related to BulkSpikeFrame/PreviewPlayback (the shared
    contract used by the real, non-demo simulation-preview pipeline) — this
    type and viz_demo.py's WebSocket envelope are self-contained so this
    feature can't couple to or break that shared contract.
    """

    tile_activity: list[float] = Field(default_factory=list)
    tile_concentration: list[float] = Field(default_factory=list)
    tile_rows: int = 0
    tile_cols: int = 0


def near_square_grid(tile_count: int) -> tuple[int, int]:
    """Split `tile_count` tiles into a near-square (rows, cols) grid."""
    rows = max(1, math.isqrt(tile_count))
    cols = math.ceil(tile_count / rows)
    return rows, cols


def resolve_rate_hz(neuron_count: int, tile_count: int, dt_ms: float) -> float:
    """Per-neuron firing rate that keeps ~5 spikes/tile/frame on average.

    Clipped at 50.0 Hz to guard against a runaway probability-per-frame
    when neuron_count is very small relative to tile_count.
    """
    target_spikes_per_frame = tile_count * 5
    dt_s = dt_ms / 1000.0
    rate_hz = target_spikes_per_frame / (neuron_count * dt_s)
    return float(min(rate_hz, 50.0))


def aggregate_tile_activity(
    fired_indices: np.ndarray,
    neuron_count: int,
    tile_rows: int,
    tile_cols: int,
) -> TileActivityFrame:
    """Bins fired-neuron indices into a tile_rows x tile_cols grid.

    Each tile covers a contiguous slice of neuron indices. Per tile:
    - `tile_activity`: spike count this frame, normalised to [0, 1] by
      this frame's busiest tile.
    - `tile_concentration`: spike-weighted mean distance from that tile's
      neuron-index midpoint, normalised to [0, 1] — 0 means activity
      concentrated at the tile's index "core", 1 means it concentrated at
      the tile's index "edges". 0 for tiles with no spikes.
    """
    tile_count = tile_rows * tile_cols
    neurons_per_tile = neuron_count / tile_count

    activity = np.zeros(tile_count, dtype=np.float64)
    edge_weighted = np.zeros(tile_count, dtype=np.float64)

    if fired_indices.size > 0 and neurons_per_tile > 0:
        tile_idx = np.minimum(
            (fired_indices / neurons_per_tile).astype(np.int64),
            tile_count - 1,
        )
        local_idx = fired_indices - tile_idx * neurons_per_tile
        half = max(neurons_per_tile - 1, 1.0) / 2.0
        edge_distance = np.clip(np.abs(local_idx - half) / half, 0.0, 1.0)

        np.add.at(activity, tile_idx, 1.0)
        np.add.at(edge_weighted, tile_idx, edge_distance)

    concentration = np.divide(
        edge_weighted,
        activity,
        out=np.zeros_like(edge_weighted),
        where=activity > 0,
    )
    max_activity = activity.max() if activity.size > 0 else 0.0
    if max_activity > 0:
        activity = activity / max_activity

    return TileActivityFrame(
        tile_activity=activity.astype(np.float32).tolist(),
        tile_concentration=concentration.astype(np.float32).tolist(),
        tile_rows=tile_rows,
        tile_cols=tile_cols,
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd neurocnl && python -m pytest neurosim/tests/test_poisson_demo_generator.py -k "near_square or resolve_rate or aggregate_tile" -v`
Expected: 8 passed

- [ ] **Step 5: Commit**

```bash
git -C neurocnl add neurosim/app/services/poisson_demo_generator.py neurosim/tests/test_poisson_demo_generator.py
git -C neurocnl commit -m "feat: add per-tile activity/concentration aggregation math"
```

---

## Task 3: Rewire `generate_demo_frame` onto tile aggregation (backend)

**Files:**
- Modify: `neurocnl/neurosim/app/services/poisson_demo_generator.py`
- Modify: `neurocnl/neurosim/tests/test_poisson_demo_generator.py` (replace the 3 existing tests that assert the OLD `data`/`density_grid`/`scale_hint` shape — they will fail to even import once `generate_demo_frame`'s signature changes)

**Interfaces:**
- Consumes: `aggregate_tile_activity` (Task 2), `TileActivityFrame` (Task 2).
- Produces: `generate_demo_frame(neuron_count: int, rate_hz: float, dt_ms: float, tile_rows: int, tile_cols: int) -> TileActivityFrame`. Used by Task 4.

- [ ] **Step 1: Write the failing test**

Replace the entire contents of `neurocnl/neurosim/tests/test_poisson_demo_generator.py`'s three original tests (`test_generate_demo_frame_perf_and_shape`, `test_generate_demo_frame_scales`, `test_generate_demo_frame_regression_10k_spike_count` — these reference `frame.data`/`frame.density_grid`/`frame.scale_hint`, which no longer exist) with:

```python
def test_generate_demo_frame_perf_and_shape():
    start = time.monotonic()
    frame = generate_demo_frame(
        neuron_count=100000,
        rate_hz=10.0,
        dt_ms=33.0,
        tile_rows=16,
        tile_cols=16,
    )
    duration = time.monotonic() - start

    assert duration < 1.0
    assert len(frame.tile_activity) == 256
    assert len(frame.tile_concentration) == 256
    assert frame.tile_rows == 16
    assert frame.tile_cols == 16


def test_generate_demo_frame_activity_bounded_zero_to_one():
    frame = generate_demo_frame(
        neuron_count=10000,
        rate_hz=0.6,
        dt_ms=1000.0 / 30.0,
        tile_rows=8,
        tile_cols=8,
    )
    assert all(0.0 <= v <= 1.0 for v in frame.tile_activity)
    assert all(0.0 <= v <= 1.0 for v in frame.tile_concentration)


def test_generate_demo_frame_zero_rate_is_all_zero():
    frame = generate_demo_frame(
        neuron_count=1000,
        rate_hz=0.0,
        dt_ms=33.0,
        tile_rows=4,
        tile_cols=4,
    )
    assert frame.tile_activity == [0.0] * 16
    assert frame.tile_concentration == [0.0] * 16
```

`time` is already imported at the top of this file (used by the original perf test) — leave that import as-is.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl && python -m pytest neurosim/tests/test_poisson_demo_generator.py -k generate_demo_frame -v`
Expected: FAIL — `TypeError: generate_demo_frame() got an unexpected keyword argument 'tile_rows'` (current signature still takes `grid_w`/`grid_h`/`t_offset_ms`)

- [ ] **Step 3: Replace `generate_demo_frame`**

Replace the entire existing `generate_demo_frame` function body in `neurocnl/neurosim/app/services/poisson_demo_generator.py` (the whole function, from `def generate_demo_frame(` through its final `return BulkSpikeFrame(...)`) with:

```python
def generate_demo_frame(
    neuron_count: int,
    rate_hz: float,
    dt_ms: float,
    tile_rows: int,
    tile_cols: int,
) -> TileActivityFrame:
    """Generate one frame of synthetic Poisson spike data, pre-aggregated
    into a tile_rows x tile_cols chip-die grid.

    Uses vectorised numpy binomial draws for which neurons fired — O(spike
    count) aggregation afterward, not O(neuron_count) — suitable for
    real-time streaming at 30 fps for up to 1M neurons.

    Args:
        neuron_count: Number of simulated neurons.
        rate_hz: Mean firing rate in Hz, per neuron.
        dt_ms: Frame duration in milliseconds.
        tile_rows: Chip-die grid row count.
        tile_cols: Chip-die grid column count.

    Returns:
        A populated TileActivityFrame.
    """
    p_spike = float(np.clip(rate_hz * dt_ms / 1000.0, 0.0, 1.0))
    fired = _RNG.binomial(1, p_spike, neuron_count).astype(bool)
    fired_indices = np.where(fired)[0]
    return aggregate_tile_activity(fired_indices, neuron_count, tile_rows, tile_cols)
```

Also remove the now-unused `from neurosim.contracts.design_contracts import BulkSpikeFrame` import line at the top of the file — nothing in this file references `BulkSpikeFrame` anymore.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd neurocnl && python -m pytest neurosim/tests/test_poisson_demo_generator.py -v`
Expected: all tests in the file pass (the 3 rewritten ones plus the 8 from Task 2)

- [ ] **Step 5: Commit**

```bash
git -C neurocnl add neurosim/app/services/poisson_demo_generator.py neurosim/tests/test_poisson_demo_generator.py
git -C neurocnl commit -m "feat: generate_demo_frame returns per-tile aggregated activity"
```

---

## Task 4: Rewire the `/viz-demo` router onto tile targets (backend)

**Files:**
- Modify: `neurocnl/neurosim/app/routers/viz_demo.py`
- Create: `neurocnl/neurosim/tests/routers/test_viz_demo.py`

**Interfaces:**
- Consumes: `load_chip_targets` (Task 1), `near_square_grid`, `resolve_rate_hz`, `generate_demo_frame` (Tasks 2-3).
- Produces: the WebSocket wire format `{"type": "frame", "current_time_ms": <float>, "tile_activity_frame": {"tile_activity": [...], "tile_concentration": [...], "tile_rows": <int>, "tile_cols": <int>}}`, and `{"type": "status", "status": "streaming", "neuron_count": <int>}`. Consumed by Task 6.

- [ ] **Step 1: Write the failing test**

```python
# neurocnl/neurosim/tests/routers/test_viz_demo.py
import json

from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)


def test_viz_demo_simulated_target_streams_tile_frame():
    with client.websocket_connect("/api/neurosim/viz/demo") as ws:
        ws.send_text(json.dumps({"target": "simulated", "scale": "10k"}))

        status = ws.receive_json()
        assert status["type"] == "status"
        assert status["neuron_count"] == 10_000

        frame_msg = ws.receive_json()
        assert frame_msg["type"] == "frame"
        tile_frame = frame_msg["tile_activity_frame"]
        assert tile_frame["tile_rows"] == 8
        assert tile_frame["tile_cols"] == 8
        assert len(tile_frame["tile_activity"]) == 64
        assert len(tile_frame["tile_concentration"]) == 64


def test_viz_demo_chip_target_uses_core_count_grid():
    with client.websocket_connect("/api/neurosim/viz/demo") as ws:
        ws.send_text(json.dumps({"target": "akida"}))

        status = ws.receive_json()
        assert status["neuron_count"] == 1_200_000

        frame_msg = ws.receive_json()
        tile_frame = frame_msg["tile_activity_frame"]
        tile_count = tile_frame["tile_rows"] * tile_frame["tile_cols"]
        assert tile_count >= 80
        assert len(tile_frame["tile_activity"]) == tile_count


def test_viz_demo_unknown_target_falls_back_to_simulated_default():
    with client.websocket_connect("/api/neurosim/viz/demo") as ws:
        ws.send_text(json.dumps({"target": "not-a-real-chip"}))

        status = ws.receive_json()
        assert status["neuron_count"] == 10_000
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl && python -m pytest neurosim/tests/routers/test_viz_demo.py -v`
Expected: FAIL — `status["neuron_count"]` assertion fails, or `KeyError: 'tile_activity_frame'` (router still sends the old `playback`/`bulk_spike_frame` envelope)

- [ ] **Step 3: Rewrite the router**

Replace the entire contents of `neurocnl/neurosim/app/routers/viz_demo.py` with:

```python
"""WebSocket router for streaming synthetic demo spike data.
# isort: skip_file

This endpoint exercises the full WebSocket streaming pipeline without
running a Nengo simulation. It is intended for testing and demos only
and is gated behind NMTK_DEMO_ROUTES (default true in dev).
"""

from __future__ import annotations

import asyncio
import json
import time
from typing import Any

import anyio
import structlog
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ..services.chip_targets import load_chip_targets
from ..services.poisson_demo_generator import (
    generate_demo_frame,
    near_square_grid,
    resolve_rate_hz,
)

router = APIRouter(prefix="/api/neurosim/viz", tags=["visualization-demo"])
logger = structlog.get_logger(__name__)

_SIMULATED_NEURON_COUNTS: dict[str, int] = {
    "10k": 10_000,
    "100k": 100_000,
    "1m": 1_000_000,
}
_SIMULATED_TILE_COUNTS: dict[str, int] = {
    "10k": 64,
    "100k": 256,
    "1m": 1024,
}
_TARGET_FPS = 30
_FRAME_DT_MS = 1000.0 / _TARGET_FPS  # ~33.3 ms per frame


def _resolve_target(config: dict[str, Any]) -> tuple[int, int, int]:
    """Resolve (neuron_count, tile_rows, tile_cols) from handshake config.

    A named chip target's neuron count follows its rated capacity and its
    tile grid follows its real core count. "scale" is ignored for a chip
    target — it only applies in "simulated" mode (the default, and the
    fallback for an unrecognised target id).
    """
    target_key = str(config.get("target", "simulated")).lower()
    if target_key != "simulated":
        chip = load_chip_targets().get(target_key)
        if chip is not None:
            rows, cols = near_square_grid(chip.core_count)
            return chip.neuron_capacity, rows, cols

    scale_key = str(config.get("scale", "10k")).lower()
    neuron_count = int(
        config.get("neuron_count", _SIMULATED_NEURON_COUNTS.get(scale_key, 10_000)),
    )
    tile_count = int(_SIMULATED_TILE_COUNTS.get(scale_key, 64))
    rows, cols = near_square_grid(tile_count)
    return neuron_count, rows, cols


@router.websocket("/demo")
async def viz_demo_websocket(websocket: WebSocket) -> None:
    """Stream synthetic Poisson spike data, aggregated per chip-die tile.

    Handshake (JSON sent by client after connect)::

        {"target": "simulated" | <chip id>, "scale": "10k" | "100k" | "1m", "rate_hz": <float>}

    "scale" only applies when target is "simulated" (or omitted/unrecognised);
    it is ignored for a named chip target, whose neuron count follows that
    chip's rated capacity and whose tile grid follows its real core count.
    "rate_hz" always overrides the derived per-neuron firing rate. The
    server then streams one tile-aggregated frame at ~30 fps indefinitely
    until the client disconnects.
    """
    await websocket.accept()
    try:
        raw = await websocket.receive_text()
        config = json.loads(raw)

        neuron_count, tile_rows, tile_cols = _resolve_target(config)
        tile_count = tile_rows * tile_cols
        rate_hz: float = float(
            config.get(
                "rate_hz",
                resolve_rate_hz(neuron_count, tile_count, _FRAME_DT_MS),
            ),
        )

        logger.info(
            "viz_demo_started",
            target=str(config.get("target", "simulated")),
            neuron_count=neuron_count,
            tile_rows=tile_rows,
            tile_cols=tile_cols,
            rate_hz=rate_hz,
        )

        await websocket.send_text(
            json.dumps(
                {
                    "type": "status",
                    "status": "streaming",
                    "neuron_count": neuron_count,
                }  # noqa: COM812
            ),
        )

        t_ms = 0.0
        while True:
            frame_start = time.monotonic()

            tile_frame = await anyio.to_thread.run_sync(
                lambda: generate_demo_frame(
                    neuron_count=neuron_count,  # noqa: B023
                    rate_hz=rate_hz,  # noqa: B023
                    dt_ms=_FRAME_DT_MS,
                    tile_rows=tile_rows,  # noqa: B023
                    tile_cols=tile_cols,  # noqa: B023
                ),
            )

            frame_end_ms = t_ms + _FRAME_DT_MS
            await websocket.send_text(
                json.dumps(
                    {
                        "type": "frame",
                        "current_time_ms": frame_end_ms,
                        "tile_activity_frame": tile_frame.model_dump(),
                    },
                ),
            )
            t_ms = frame_end_ms

            elapsed = time.monotonic() - frame_start
            sleep_s = max(0.0, (1.0 / _TARGET_FPS) - elapsed)
            if sleep_s > 0:
                await asyncio.sleep(sleep_s)

    except WebSocketDisconnect:
        logger.info("viz_demo_client_disconnected")
    except Exception as exc:
        logger.warning("viz_demo_error", error=str(exc))
        try:  # noqa: SIM105
            await websocket.send_text(
                json.dumps({"type": "error", "message": str(exc)})  # noqa: COM812
            )
        except Exception:
            pass
```

Note: `jsonable_encoder` is no longer needed (dropped from imports) — `TileActivityFrame.model_dump()` already returns plain Python types (`list[float]`/`int`) that `json.dumps` handles directly.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd neurocnl && python -m pytest neurosim/tests/routers/test_viz_demo.py -v`
Expected: 3 passed

- [ ] **Step 5: Run the full backend test suite to check for regressions**

Run: `cd neurocnl && python -m pytest neurosim/tests -v`
Expected: all pass, including the untouched `test_density_aggregator.py` (confirms the shared `BulkSpikeFrame` contract was not affected)

- [ ] **Step 6: Commit**

```bash
git -C neurocnl add neurosim/app/routers/viz_demo.py neurosim/tests/routers/test_viz_demo.py
git -C neurocnl commit -m "feat: stream chip-die tile frames from the viz-demo websocket"
```

---

## Task 5: `TileGridNeuronRenderer` (frontend, `nmtk_ui_core`)

**Files:**
- Create: `nmtk_ui_core/lib/visualization/tile_grid_renderer.dart`
- Modify: `nmtk_ui_core/lib/nmtk_ui_core.dart:62` (add one export line after the existing `renderer_registry.dart` export)
- Test: `nmtk_ui_core/test/visualization/tile_grid_renderer_test.dart`

**Interfaces:**
- Produces: `TileActivityFrame` (Dart class: `totalNeuronCount`, `tileActivity: Float32List`, `tileConcentration: Float32List`, `tileRows`, `tileCols`, `simulationTimeMs`, plus `tileCount` and `neuronsForTile(int)` getters/methods) and `TileGridNeuronRenderer` (`attach(Size)`, `pushFrame(TileActivityFrame)`, `buildSurface(BuildContext) -> Widget`, `dispose()`). Used by Task 6 and Task 7.
- Does **not** implement the existing `NeuronRenderer` interface from `renderer_interface.dart` — deliberately separate (see Global Constraints).

- [ ] **Step 1: Write the failing test**

```dart
// nmtk_ui_core/test/visualization/tile_grid_renderer_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/visualization/tile_grid_renderer.dart';

void main() {
  group('TileActivityFrame', () {
    test('tileCount is rows * cols', () {
      final frame = TileActivityFrame(
        totalNeuronCount: 1000,
        tileActivity: Float32List(6),
        tileConcentration: Float32List(6),
        tileRows: 2,
        tileCols: 3,
        simulationTimeMs: 0,
      );
      expect(frame.tileCount, 6);
    });

    test('neuronsForTile divides total neuron count evenly across tiles', () {
      final frame = TileActivityFrame(
        totalNeuronCount: 800,
        tileActivity: Float32List(8),
        tileConcentration: Float32List(8),
        tileRows: 2,
        tileCols: 4,
        simulationTimeMs: 0,
      );
      expect(frame.neuronsForTile(0), 100);
    });
  });

  testWidgets(
    'TileGridNeuronRenderer shows a loading indicator before the first frame',
    (tester) async {
      final renderer = TileGridNeuronRenderer();
      addTearDown(renderer.dispose);
      renderer.attach(const Size(200, 200));

      await tester.pumpWidget(MaterialApp(home: Builder(builder: renderer.buildSurface)));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'TileGridNeuronRenderer paints a grid after pushFrame',
    (tester) async {
      final renderer = TileGridNeuronRenderer();
      addTearDown(renderer.dispose);
      renderer.attach(const Size(200, 200));

      await tester.pumpWidget(MaterialApp(home: Builder(builder: renderer.buildSurface)));

      renderer.pushFrame(TileActivityFrame(
        totalNeuronCount: 100,
        tileActivity: Float32List.fromList([0.5, 0.8, 0.1, 0.9]),
        tileConcentration: Float32List.fromList([0.2, 0.7, 0.0, 1.0]),
        tileRows: 2,
        tileCols: 2,
        simulationTimeMs: 33.0,
      ));
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd nmtk_ui_core && flutter test test/visualization/tile_grid_renderer_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'nmtk_ui_core' in 'package:nmtk_ui_core/visualization/tile_grid_renderer.dart'` (file doesn't exist yet)

- [ ] **Step 3: Write the implementation**

```dart
// nmtk_ui_core/lib/visualization/tile_grid_renderer.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// One frame of per-core-tile aggregated activity for the /viz-demo
/// chip-die view. `tileActivity[i]`/`tileConcentration[i]` describe tile
/// `i`, row-major: `i == row * tileCols + col`.
class TileActivityFrame {
  final int totalNeuronCount;
  final Float32List tileActivity;
  final Float32List tileConcentration;
  final int tileRows;
  final int tileCols;
  final double simulationTimeMs;

  TileActivityFrame({
    required this.totalNeuronCount,
    required this.tileActivity,
    required this.tileConcentration,
    required this.tileRows,
    required this.tileCols,
    required this.simulationTimeMs,
  });

  int get tileCount => tileRows * tileCols;

  /// Neurons mapped to tile [index] — an even split; the toolkit's chip
  /// targets don't expose per-core neuron counts finer than this average.
  int neuronsForTile(int index) => (totalNeuronCount / tileCount).round();
}

/// Renders [TileActivityFrame]s as a chip-die grid: one square tile per
/// core, colored blue (low activity) to red (high activity), with a soft
/// square glow inside each tile showing whether that core's activation
/// concentrates near its "core" (small, centered glow) or "edge" (glow
/// pushed toward the tile boundary) neuron indices. Supports hover/click
/// for a per-tile detail popup and pinch/drag zoom-pan.
class TileGridNeuronRenderer {
  final ValueNotifier<TileActivityFrame?> _frameNotifier = ValueNotifier(null);
  final ValueNotifier<int?> _hoveredTile = ValueNotifier(null);
  Size _size = Size.zero;

  void attach(Size size) {
    _size = size;
  }

  void pushFrame(TileActivityFrame frame) {
    _frameNotifier.value = frame;
  }

  int? _tileAtLocalPosition(Offset local, TileActivityFrame frame) {
    if (_size.width <= 0 || _size.height <= 0) return null;
    final tileW = _size.width / frame.tileCols;
    final tileH = _size.height / frame.tileRows;
    final col = (local.dx / tileW).floor();
    final row = (local.dy / tileH).floor();
    if (col < 0 || col >= frame.tileCols || row < 0 || row >= frame.tileRows) {
      return null;
    }
    final index = row * frame.tileCols + col;
    return index < frame.tileCount ? index : null;
  }

  Widget buildSurface(BuildContext context) {
    return ValueListenableBuilder<TileActivityFrame?>(
      valueListenable: _frameNotifier,
      builder: (context, frame, _) {
        if (frame == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ValueListenableBuilder<int?>(
          valueListenable: _hoveredTile,
          builder: (context, hovered, _) {
            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 8.0,
              child: MouseRegion(
                onHover: (event) =>
                    _hoveredTile.value = _tileAtLocalPosition(event.localPosition, frame),
                onExit: (_) => _hoveredTile.value = null,
                child: GestureDetector(
                  onTapUp: (details) =>
                      _hoveredTile.value = _tileAtLocalPosition(details.localPosition, frame),
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: _size,
                        painter: _TileGridPainter(frame: frame),
                      ),
                      if (hovered != null) _buildTilePopup(frame, hovered),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTilePopup(TileActivityFrame frame, int tileIndex) {
    final row = tileIndex ~/ frame.tileCols;
    final col = tileIndex % frame.tileCols;
    return Positioned(
      left: 12,
      top: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC111827),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Core $tileIndex (row $row, col $col)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Text(
                'Neurons: ~${frame.neuronsForTile(tileIndex)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Activity: ${frame.tileActivity[tileIndex].toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Concentration: ${frame.tileConcentration[tileIndex].toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void dispose() {
    _frameNotifier.dispose();
    _hoveredTile.dispose();
  }
}

class _TileGridPainter extends CustomPainter {
  final TileActivityFrame frame;

  _TileGridPainter({required this.frame});

  static const _lo = Color(0xFF1e3a8f); // blue: low activity
  static const _hi = Color(0xFFf0453c); // red: high activity
  static const _hot = Color(0xFFffe9a8); // pale glow for the hotspot

  @override
  void paint(Canvas canvas, Size size) {
    final tileW = size.width / frame.tileCols;
    final tileH = size.height / frame.tileRows;
    const gap = 2.0;

    for (var row = 0; row < frame.tileRows; row++) {
      for (var col = 0; col < frame.tileCols; col++) {
        final index = row * frame.tileCols + col;
        if (index >= frame.tileCount) continue;

        final activity = frame.tileActivity[index].clamp(0.0, 1.0);
        final concentration = frame.tileConcentration[index].clamp(0.0, 1.0);
        final rect = Rect.fromLTWH(
          col * tileW + gap / 2,
          row * tileH + gap / 2,
          tileW - gap,
          tileH - gap,
        );

        final tilePaint = Paint()..color = Color.lerp(_lo, _hi, activity)!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          tilePaint,
        );

        if (activity > 0.05) {
          // Soft square hotspot: shrinks toward the tile's center as
          // concentration -> 0 (core-heavy), grows toward the tile's
          // edges as concentration -> 1 (edge-heavy).
          final inset = rect.deflate(rect.shortestSide * (0.4 - concentration * 0.3));
          final hotspotPaint = Paint()
            ..color = _hot.withValues(alpha: 0.15 + activity * 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
          canvas.drawRRect(
            RRect.fromRectAndRadius(inset, const Radius.circular(3)),
            hotspotPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TileGridPainter oldDelegate) => true;
}
```

Add one line to `nmtk_ui_core/lib/nmtk_ui_core.dart`, directly after the existing `export 'visualization/renderer_registry.dart';` line (leave the other three visualization export lines untouched):

```dart
export 'visualization/tile_grid_renderer.dart';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd nmtk_ui_core && flutter test test/visualization/tile_grid_renderer_test.dart`
Expected: 4 passed

- [ ] **Step 5: Run `flutter analyze` on the changed files**

Run: `cd nmtk_ui_core && flutter analyze lib/visualization/tile_grid_renderer.dart lib/nmtk_ui_core.dart`
Expected: No issues found!

- [ ] **Step 6: Commit**

```bash
git add nmtk_ui_core/lib/visualization/tile_grid_renderer.dart nmtk_ui_core/lib/nmtk_ui_core.dart nmtk_ui_core/test/visualization/tile_grid_renderer_test.dart
git commit -m "feat: add TileGridNeuronRenderer chip-die visualization"
```

---

## Task 6: Rewire `viz_demo_provider.dart` onto the tile wire format (frontend)

**Files:**
- Modify: `neurocnl/frontend/lib/widgets/canvas/viz_demo_provider.dart`
- Modify: `neurocnl/frontend/test/models/viz_demo_provider_test.dart`

**Interfaces:**
- Consumes: `TileActivityFrame`, `TileGridNeuronRenderer` (Task 5, both exported via `package:nmtk_ui_core/nmtk_ui_core.dart`, already imported in this file).
- Produces: `VizDemoTarget` (`apiId`, `label`, `isSimulated`, plus static `simulated` const), `vizDemoChipTargets` (`List<VizDemoTarget>`), `DemoScale` (`apiKey`, `label` — unchanged enum values, `rateHz`/`visualizationScale` getters removed), `VizDemoSelection` (`target`, `scale`), and `vizDemoStreamProvider` (now `StreamProvider.family<TileActivityFrame, VizDemoSelection>`). Used by Task 7.

- [ ] **Step 1: Write the failing test**

Replace the entire contents of `neurocnl/frontend/test/models/viz_demo_provider_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:neurocnl_studio/widgets/canvas/viz_demo_provider.dart';

void main() {
  test('DemoScale api keys match backend scale identifiers', () {
    expect(DemoScale.k10.apiKey, '10k');
    expect(DemoScale.k100.apiKey, '100k');
    expect(DemoScale.m1.apiKey, '1m');
  });

  test('VizDemoTarget.simulated is the software/simulated default', () {
    expect(VizDemoTarget.simulated.apiId, 'simulated');
    expect(VizDemoTarget.simulated.isSimulated, isTrue);
  });

  test('vizDemoChipTargets lists only real hardware targets with unique ids', () {
    expect(vizDemoChipTargets, isNotEmpty);
    expect(vizDemoChipTargets.every((t) => !t.isSimulated), isTrue);
    final ids = vizDemoChipTargets.map((t) => t.apiId).toSet();
    expect(ids.length, vizDemoChipTargets.length);
  });

  test('VizDemoSelection defaults to the 10k scale', () {
    const selection = VizDemoSelection(target: VizDemoTarget.simulated);
    expect(selection.scale, DemoScale.k10);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd neurocnl/frontend && flutter test test/models/viz_demo_provider_test.dart`
Expected: FAIL — compile error, `VizDemoTarget` isn't defined yet.

- [ ] **Step 3: Rewrite the provider**

Replace the entire contents of `neurocnl/frontend/lib/widgets/canvas/viz_demo_provider.dart` with:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../providers/server_config_provider.dart';
import '../../services/server_config_service.dart';

/// A selectable target for the viz-demo chip-die view: either the
/// "Software / Simulated" tier (uses the [DemoScale] picker) or a named
/// neuromorphic chip (uses that chip's real core count / neuron capacity,
/// resolved server-side from `Neurochip/neurochip/targets/`).
class VizDemoTarget {
  final String apiId;
  final String label;
  final bool isSimulated;

  const VizDemoTarget({
    required this.apiId,
    required this.label,
    required this.isSimulated,
  });

  static const simulated = VizDemoTarget(
    apiId: 'simulated',
    label: 'Software / Simulated',
    isSimulated: true,
  );
}

/// Named chip targets, matching the ids in `Neurochip/neurochip/targets/*.json`.
/// Only the id + display label are duplicated here — core counts and
/// neuron capacities are resolved server-side and never hardcoded here.
const vizDemoChipTargets = <VizDemoTarget>[
  VizDemoTarget(apiId: 'akida', label: 'BrainChip Akida', isSimulated: false),
  VizDemoTarget(apiId: 'loihi2', label: 'Intel Loihi 2', isSimulated: false),
  VizDemoTarget(apiId: 'spinnaker2', label: 'SpiNNaker 2', isSimulated: false),
  VizDemoTarget(apiId: 'spinnaker', label: 'SpiNNaker', isSimulated: false),
  VizDemoTarget(apiId: 'speck2', label: 'SynSense Speck 2', isSimulated: false),
  VizDemoTarget(apiId: 'brainscales', label: 'BrainScaleS', isSimulated: false),
  VizDemoTarget(apiId: 'pynq_z2', label: 'PYNQ-Z2', isSimulated: false),
];

/// Scale tiers available in "Software / Simulated" mode.
enum DemoScale { k10, k100, m1 }

extension DemoScaleX on DemoScale {
  String get apiKey => switch (this) {
    DemoScale.k10 => '10k',
    DemoScale.k100 => '100k',
    DemoScale.m1 => '1m',
  };

  String get label => switch (this) {
    DemoScale.k10 => '10 k',
    DemoScale.k100 => '100 k',
    DemoScale.m1 => '1 M',
  };
}

/// The full user selection driving [vizDemoStreamProvider]. [scale] is only
/// meaningful when `target.isSimulated` — a named chip target ignores it.
class VizDemoSelection {
  final VizDemoTarget target;
  final DemoScale scale;

  const VizDemoSelection({required this.target, this.scale = DemoScale.k10});
}

TileActivityFrame _frameFromSocketJson(
  Map<String, dynamic> json,
  int totalNeuronCount,
) {
  final tileJson =
      json['tile_activity_frame'] as Map<String, dynamic>? ?? const <String, dynamic>{};
  final activity =
      (tileJson['tile_activity'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => (value as num).toDouble())
          .toList();
  final concentration =
      (tileJson['tile_concentration'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => (value as num).toDouble())
          .toList();

  return TileActivityFrame(
    totalNeuronCount: totalNeuronCount,
    tileActivity: Float32List.fromList(activity),
    tileConcentration: Float32List.fromList(concentration),
    tileRows: (tileJson['tile_rows'] as num?)?.toInt() ?? 0,
    tileCols: (tileJson['tile_cols'] as num?)?.toInt() ?? 0,
    simulationTimeMs: (json['current_time_ms'] as num?)?.toDouble() ?? 0.0,
  );
}

final vizDemoStreamProvider =
    StreamProvider.family<TileActivityFrame, VizDemoSelection>((ref, selection) {
  // ponytail: use same URL source as api_provider — serverConfigProvider reflects
  // runtime state (auto-discovery, UI config); SharedPrefs may lag behind.
  final stored = ref.watch(serverConfigProvider).serverUrl
      ?? ServerConfigService.serverUrl;
  final rawUrl = stored != null && stored.isNotEmpty ? stored : 'http://localhost:9000';
  final parsedUri = Uri.parse(rawUrl);
  final wsScheme = parsedUri.scheme == 'https' ? 'wss' : 'ws';
  final cleanBase = '$wsScheme://${parsedUri.host}${parsedUri.hasPort ? ':${parsedUri.port}' : ''}';

  final channel = WebSocketChannel.connect(Uri.parse('$cleanBase/api/neurosim/viz/demo'));
  ref.onDispose(channel.sink.close);

  var totalNeuronCount = 0;

  // ponytail: send config AFTER channel.ready — backend does receive_text() before
  // sending any frames; if sent before the WS handshake the message may be dropped
  // and the server hangs forever → no frames → spinner
  return Stream.fromFuture(channel.ready).asyncExpand((_) {
    channel.sink.add(jsonEncode({
      'target': selection.target.apiId,
      'scale': selection.scale.apiKey,
    }));
    return channel.stream
        .map((raw) => jsonDecode(raw as String) as Map<String, dynamic>)
        .where((decoded) {
          if (decoded['type'] == 'status') {
            totalNeuronCount = (decoded['neuron_count'] as num?)?.toInt() ?? 0;
            return false;
          }
          return decoded['type'] == 'frame';
        })
        .map((decoded) => _frameFromSocketJson(decoded, totalNeuronCount));
  // ponytail: timeout converts silent close into visible error instead of spinner
  }).timeout(
    const Duration(seconds: 8),
    onTimeout: (sink) => sink.addError(
      TimeoutException('No frames in 8s — check suite_api logs on remote'),
    ),
  );
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd neurocnl/frontend && flutter test test/models/viz_demo_provider_test.dart`
Expected: 4 passed

- [ ] **Step 5: Run `flutter analyze`**

Run: `cd neurocnl/frontend && flutter analyze lib/widgets/canvas/viz_demo_provider.dart`
Expected: No issues found! (Task 7 still needs to update `viz_demo_screen.dart`, which currently references the old provider shape and will fail to compile until then — that's expected and fixed in Task 7, not this one.)

- [ ] **Step 6: Commit**

```bash
git -C neurocnl add frontend/lib/widgets/canvas/viz_demo_provider.dart frontend/test/models/viz_demo_provider_test.dart
git -C neurocnl commit -m "feat: stream chip-die tile targets from viz_demo_provider"
```

---

## Task 7: Rewire `viz_demo_screen.dart` — target dropdown, timeline, tile renderer (frontend)

**Files:**
- Modify: `neurocnl/frontend/lib/screens/viz_demo_screen.dart`

**Interfaces:**
- Consumes: everything from Task 5 (`TileActivityFrame`, `TileGridNeuronRenderer`) and Task 6 (`VizDemoTarget`, `vizDemoChipTargets`, `DemoScale`, `VizDemoSelection`, `vizDemoStreamProvider`).

- [ ] **Step 1: Replace the screen**

Replace the entire contents of `neurocnl/frontend/lib/screens/viz_demo_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import '../widgets/canvas/viz_demo_provider.dart';

const _historyCap = 1800; // 60s @ 30fps rolling window

class VizDemoScreen extends ConsumerStatefulWidget {
  const VizDemoScreen({super.key});

  @override
  ConsumerState<VizDemoScreen> createState() => _VizDemoScreenState();
}

class _VizDemoScreenState extends ConsumerState<VizDemoScreen> {
  VizDemoTarget _target = VizDemoTarget.simulated;
  DemoScale _scale = DemoScale.k10;
  TileGridNeuronRenderer _renderer = TileGridNeuronRenderer();

  final List<TileActivityFrame> _history = [];
  bool _isLive = true;
  int _scrubIndex = 0;

  VizDemoSelection get _selection =>
      VizDemoSelection(target: _target, scale: _scale);

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  void _selectTarget(VizDemoTarget target) {
    if (target.apiId == _target.apiId) return;
    setState(() {
      _target = target;
      _resetStream();
    });
  }

  void _selectScale(DemoScale scale) {
    if (scale == _scale) return;
    setState(() {
      _scale = scale;
      _resetStream();
    });
  }

  void _resetStream() {
    _renderer.dispose();
    _renderer = TileGridNeuronRenderer();
    _history.clear();
    _isLive = true;
    _scrubIndex = 0;
  }

  void _onFrame(TileActivityFrame frame) {
    _history.add(frame);
    if (_history.length > _historyCap) {
      _history.removeAt(0);
    }
    if (_isLive) {
      _scrubIndex = _history.length - 1;
      _renderer.pushFrame(frame);
    }
  }

  void _scrubTo(int index) {
    if (index < 0 || index >= _history.length) return;
    setState(() {
      _isLive = false;
      _scrubIndex = index;
    });
    _renderer.pushFrame(_history[index]);
  }

  void _goLive() {
    setState(() => _isLive = true);
    if (_history.isNotEmpty) {
      _scrubIndex = _history.length - 1;
      _renderer.pushFrame(_history[_scrubIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frameAsync = ref.watch(vizDemoStreamProvider(_selection));
    ref.listen<AsyncValue<TileActivityFrame>>(
      vizDemoStreamProvider(_selection),
      (previous, next) {
        next.whenData(_onFrame);
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Visualization Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<String>(
              value: _target.apiId,
              items: [
                DropdownMenuItem(
                  value: VizDemoTarget.simulated.apiId,
                  child: Text(VizDemoTarget.simulated.label),
                ),
                ...vizDemoChipTargets.map(
                  (t) => DropdownMenuItem(value: t.apiId, child: Text(t.label)),
                ),
              ],
              onChanged: (apiId) {
                if (apiId == null) return;
                final target = apiId == VizDemoTarget.simulated.apiId
                    ? VizDemoTarget.simulated
                    : vizDemoChipTargets.firstWhere((t) => t.apiId == apiId);
                _selectTarget(target);
              },
            ),
            if (_target.isSimulated) ...[
              const SizedBox(height: 12),
              SegmentedButton<DemoScale>(
                segments: [
                  for (final scale in DemoScale.values)
                    ButtonSegment<DemoScale>(value: scale, label: Text(scale.label)),
                ],
                selected: {_scale},
                onSelectionChanged: (selection) => _selectScale(selection.first),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1020),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = Size(constraints.maxWidth, constraints.maxHeight);
                          _renderer.attach(size);
                          return _renderer.buildSurface(context);
                        },
                      ),
                    ),
                    if (frameAsync.isLoading && _history.isEmpty)
                      const Positioned.fill(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (frameAsync.hasError)
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Demo stream failed: ${frameAsync.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isLive ? Icons.pause : Icons.play_arrow),
                  tooltip: _isLive ? 'Pause (scrub the timeline)' : 'Resume live',
                  onPressed: () {
                    if (_isLive) {
                      setState(() => _isLive = false);
                    } else {
                      _goLive();
                    }
                  },
                ),
                Expanded(
                  child: Slider(
                    value: _history.isEmpty ? 0 : _scrubIndex.toDouble(),
                    min: 0,
                    max: _history.isEmpty ? 0 : (_history.length - 1).toDouble(),
                    onChanged: _history.isEmpty ? null : (value) => _scrubTo(value.round()),
                  ),
                ),
                Text(
                  _isLive
                      ? 'Live'
                      : '${((_history.length - 1 - _scrubIndex) / 30).toStringAsFixed(1)}s ago',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run `flutter analyze` across the whole frontend package**

Run: `cd neurocnl/frontend && flutter analyze`
Expected: No issues found! (this is the first point where the whole package — screen, provider, and their test — must compile together)

- [ ] **Step 3: Run the full frontend test suite**

Run: `cd neurocnl/frontend && flutter test`
Expected: all tests pass, including `test/models/viz_demo_provider_test.dart` from Task 6

- [ ] **Step 4: Manual smoke test**

Run: `make dev FLUTTER_DEVICE=macos` from the repo root, open the Studio window, click the scatter-plot icon in the top bar to reach `/viz-demo`. Confirm:
- The target dropdown defaults to "Software / Simulated" with the 10k/100k/1M segmented button visible.
- Selecting a chip (e.g. "BrainChip Akida") hides the segmented button and the grid re-renders with a different tile count.
- Tiles glow blue→red and repaint continuously.
- Hovering/clicking a tile shows the detail popup; pinch/drag zooms and pans.
- Pausing and dragging the timeline slider freezes on a past frame; "Resume live" jumps back to the current frame.

- [ ] **Step 5: Commit**

```bash
git -C neurocnl add frontend/lib/screens/viz_demo_screen.dart
git -C neurocnl commit -m "feat: chip-die target picker, timeline scrubber, and tile renderer in viz-demo"
```
