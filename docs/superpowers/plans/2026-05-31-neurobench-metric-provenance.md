# Neurobench Metric Provenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit `metric_provenance` field to every `BenchmarkResult` so users can never mistake CPU-simulated metrics for physical on-chip measurements — closing P0 #6 from the release gap analysis.

**Architecture:** Four-layer change: (1) `benchmark_contracts.py` gains a `MetricProvenance` StrEnum and the new required field; (2) `result_store.py` gets an `ALTER TABLE` migration and updated save/load; (3) `benchmark_runner.py` and hardware runner files populate the field at each `BenchmarkResult(...)` creation site using a shared helper; (4) The Flutter model and `ResultsSummaryCard` replace the raw `targetId` chip with a tone-coded "CPU Estimated" / "On-Device" badge. AGENTS.md requires contracts to be updated before services, which the task ordering respects.

**Tech Stack:** Python/Pydantic v2 (`StrEnum`), SQLite (`ALTER TABLE` migration), pytest, Dart/Flutter (`NmtkStatusBadge`, `NmtkTone`)

---

## Scope Note

This plan covers **P0 #6 (Neurobench)** only. Two related P1 items are deferred to Plan C2:
- **P1 #11** — neurocnl validation panel deploy-readiness alignment
- **P1 #12** — neurocnl pre-export topology capability check

**P0 #5** (one validated hardware path end-to-end) requires hardware access and is out of scope for a software-only plan.

---

## File Map

| File | Action | Why |
|------|--------|-----|
| `Neurobench/neurobench/contracts/benchmark_contracts.py` | Modify | Add `MetricProvenance` enum, `_provenance_from_target_id()` helper, `metric_provenance` field |
| `Neurobench/neurobench/tests/test_contracts.py` | Modify | Tests for new field validation and helper |
| `Neurobench/neurobench/tests/conftest.py` | Modify | Update `benchmark_result_dict` fixture to include `metric_provenance` |
| `Neurobench/neurobench/app/services/result_store.py` | Modify | Schema migration, updated `save_result()`, updated `_row_to_benchmark_result()` |
| `Neurobench/neurobench/app/services/benchmark_runner.py` | Modify | Populate `metric_provenance` at all 3 `BenchmarkResult(...)` sites |
| `Neurobench/neurobench/app/runners/` (`spinnaker2_runner.py`, `synsense_runner.py`, `pynq_runner.py`) | Modify | Populate `metric_provenance=MetricProvenance.ON_DEVICE` at hardware result sites |
| `Neurobench/frontend/lib/models/result.dart` | Modify | Add `metricProvenance` field + `fromJson` parsing |
| `Neurobench/frontend/lib/widgets/results_summary_card.dart:66–69` | Modify | Replace raw `targetId` chip with provenance-coded badge |

**Read before editing:**
```bash
cat $HOME/NeuroMorphicToolKit/CODING_STYLE_GUIDE.md
cat $HOME/NeuroMorphicToolKit/Neurobench/AGENTS.md
```

**Verification after every Python change:**
```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest -v --tb=short tests/ 2>&1 | tail -20
```

**Verification after Flutter changes:**
```bash
cd $HOME/NeuroMorphicToolKit/Neurobench/frontend && \
  flutter test --no-pub 2>&1 | tail -8
```

---

## Task 1: Add `MetricProvenance` enum + `metric_provenance` field to contracts

**Files:**
- Modify: `Neurobench/neurobench/contracts/benchmark_contracts.py`
- Modify: `Neurobench/neurobench/tests/test_contracts.py`
- Modify: `Neurobench/neurobench/tests/conftest.py`

- [ ] **Step 1: Read CODING_STYLE_GUIDE.md and Neurobench/AGENTS.md**

```bash
cat $HOME/NeuroMorphicToolKit/CODING_STYLE_GUIDE.md
cat $HOME/NeuroMorphicToolKit/Neurobench/AGENTS.md
```

- [ ] **Step 2: Write two failing tests in `test_contracts.py`**

Add at the end of `Neurobench/neurobench/tests/test_contracts.py`:

```python
from neurobench.contracts.benchmark_contracts import MetricProvenance, _provenance_from_target_id


def test_benchmark_result_requires_metric_provenance() -> None:
    """BenchmarkResult must include metric_provenance."""
    result = BenchmarkResult(
        id="res_001",
        benchmark_id="bench_001",
        network_spec_hash="abc123",
        timestamp="2026-01-01T00:00:00Z",
        params={"p": 1},
        metrics={"accuracy": 0.9},
        wall_time_seconds=1.0,
        seed=42,
        metric_provenance=MetricProvenance.CPU_ESTIMATED,
    )
    assert result.metric_provenance == MetricProvenance.CPU_ESTIMATED


def test_provenance_from_target_id_classifies_correctly() -> None:
    """_provenance_from_target_id maps hardware targets to on_device, others to cpu_estimated."""
    assert _provenance_from_target_id(None) == MetricProvenance.CPU_ESTIMATED
    assert _provenance_from_target_id("neurobench") == MetricProvenance.CPU_ESTIMATED
    assert _provenance_from_target_id("neurosense_recording") == MetricProvenance.CPU_ESTIMATED
    # akida runs in simulator_only mode (localModeFallback per modules.json) — NOT on_device
    assert _provenance_from_target_id("akida") == MetricProvenance.CPU_ESTIMATED
    # Physical neuromorphic hardware
    assert _provenance_from_target_id("spinnaker2") == MetricProvenance.ON_DEVICE
    assert _provenance_from_target_id("synsense") == MetricProvenance.ON_DEVICE
    assert _provenance_from_target_id("pynq") == MetricProvenance.ON_DEVICE
```

- [ ] **Step 3: Run the failing tests**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest tests/test_contracts.py::test_benchmark_result_requires_metric_provenance \
    tests/test_contracts.py::test_provenance_from_target_id_classifies_correctly -v 2>&1 | tail -15
```

Expected: FAIL (`ImportError: cannot import name 'MetricProvenance'`)

- [ ] **Step 4: Add `MetricProvenance`, `_provenance_from_target_id`, and the field to `benchmark_contracts.py`**

At the top of `benchmark_contracts.py`, add `StrEnum` to the `enum` import (it's already imported via `from enum import StrEnum` — check and add if missing). Then add the following block immediately before the `BenchmarkResult` class:

```python
class MetricProvenance(StrEnum):
    """Provenance of metrics in a BenchmarkResult.

    CPU_ESTIMATED — metrics computed via CPU-based simulation; NOT measured on target hardware.
    ON_DEVICE     — metrics measured on real neuromorphic hardware (SpiNNaker2, PYNQ, SynSense, etc.).
    """

    CPU_ESTIMATED = "cpu_estimated"
    ON_DEVICE = "on_device"


# Hardware target IDs whose metrics are measured on physical neuromorphic chips.
# NOTE: "akida" is intentionally excluded — modules.json sets localModeFallback: simulator_only,
# meaning Akida benchmarks run on CPU simulation in all standard configurations.
_HARDWARE_TARGET_IDS: frozenset[str] = frozenset({"spinnaker2", "synsense", "pynq"})


def _provenance_from_target_id(target_id: str | None) -> MetricProvenance:
    """Classify a result's provenance from its target_id string.

    Any target in _HARDWARE_TARGET_IDS produced metrics on physical hardware.
    Everything else (simulation, library, recording input) ran on CPU.
    """
    if target_id in _HARDWARE_TARGET_IDS:
        return MetricProvenance.ON_DEVICE
    return MetricProvenance.CPU_ESTIMATED
```

Then add `metric_provenance` to the `BenchmarkResult` model after the `seed` field:

```python
class BenchmarkResult(BaseModel):
    """Represents the result of a single benchmark run."""

    model_config = ConfigDict(ser_json_inf_nan="null")

    id: str
    benchmark_id: str
    network_spec_hash: str
    timestamp: str
    target_id: str | None = None
    quantization_bits: int | None = None
    encoding_method: str | None = None
    params: dict[str, Any]
    metrics: dict[str, float | None]
    spike_data: dict[str, Any] | None = None
    wall_time_seconds: float
    seed: int
    metric_provenance: MetricProvenance = MetricProvenance.CPU_ESTIMATED
```

The default `CPU_ESTIMATED` keeps existing callers that don't pass the field valid during the migration window.

- [ ] **Step 5: Run the failing tests — expect PASS**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest tests/test_contracts.py::test_benchmark_result_requires_metric_provenance \
    tests/test_contracts.py::test_provenance_from_target_id_classifies_correctly -v 2>&1 | tail -10
```

Expected: both PASS.

- [ ] **Step 6: Update the `benchmark_result_dict` fixture in `conftest.py`**

In `Neurobench/neurobench/tests/conftest.py`, find the `benchmark_result_dict` fixture (lines ~55–66) and add `metric_provenance`:

```python
@pytest.fixture
def benchmark_result_dict() -> dict[str, Any]:
    return {
        "id": "res_123",
        "benchmark_id": "test_bench",
        "network_spec_hash": "hash_123",
        "timestamp": "2024-01-01T00:00:00Z",
        "params": {"p1": 1},
        "metrics": {"accuracy": 0.9, "latency_ms": 10.0},
        "wall_time_seconds": 1.5,
        "seed": 42,
        "metric_provenance": "cpu_estimated",   # ← add this line
    }
```

- [ ] **Step 7: Run full contract tests — no regressions**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest tests/test_contracts.py -v 2>&1 | tail -15
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add \
  Neurobench/neurobench/contracts/benchmark_contracts.py \
  Neurobench/neurobench/tests/test_contracts.py \
  Neurobench/neurobench/tests/conftest.py
git commit -m "feat(neurobench): add MetricProvenance enum and metric_provenance field to BenchmarkResult (P0 #6)

Adds MetricProvenance.CPU_ESTIMATED / ON_DEVICE and a _provenance_from_target_id()
helper. BenchmarkResult gains metric_provenance with a safe CPU_ESTIMATED default
so existing callers compile without changes. Tests added for both."
```

---

## Task 2: SQLite migration + updated save/load in `result_store.py`

**Files:**
- Modify: `Neurobench/neurobench/app/services/result_store.py`

- [ ] **Step 1: Write a failing test for the round-trip**

Find the result store tests in `Neurobench/neurobench/tests/`. Check:
```bash
grep -rn "result_store\|ResultStore\|save_result" \
  $HOME/NeuroMorphicToolKit/Neurobench/neurobench/tests/ | head -10
```

Then add to the appropriate test file (or create `tests/test_result_store.py` if none exists):

```python
import pytest
from neurobench.app.services.result_store import ResultStore
from neurobench.contracts.benchmark_contracts import BenchmarkResult, MetricProvenance


def test_result_store_roundtrips_metric_provenance(tmp_path) -> None:
    """metric_provenance persists through save and reload."""
    store = ResultStore(db_path=str(tmp_path / "test.sqlite"))

    result = BenchmarkResult(
        id="res_rt_001",
        benchmark_id="bench_001",
        network_spec_hash="hash_001",
        timestamp="2026-01-01T00:00:00Z",
        params={"p": 1},
        metrics={"accuracy": 0.95},
        wall_time_seconds=2.5,
        seed=42,
        metric_provenance=MetricProvenance.ON_DEVICE,
    )
    store.save_result(result)

    loaded = store.get_result("res_rt_001")
    assert loaded is not None
    assert loaded.metric_provenance == MetricProvenance.ON_DEVICE


def test_result_store_defaults_cpu_estimated_for_legacy_rows(tmp_path) -> None:
    """Rows inserted before the migration (no metric_provenance) load as cpu_estimated."""
    import sqlite3

    db_path = str(tmp_path / "legacy.sqlite")
    # Manually create old-style table without metric_provenance
    with sqlite3.connect(db_path) as conn:
        conn.execute("""
            CREATE TABLE results (
                id TEXT PRIMARY KEY,
                benchmark_id TEXT NOT NULL,
                network_spec_hash TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                target_id TEXT,
                quantization_bits INTEGER,
                encoding_method TEXT,
                params TEXT NOT NULL,
                metrics TEXT NOT NULL,
                spike_data TEXT,
                wall_time_seconds REAL NOT NULL,
                seed INTEGER NOT NULL
            )
        """)
        conn.execute("""
            INSERT INTO results VALUES
            ('res_legacy', 'bench', 'hash', '2025-01-01T00:00:00Z',
             NULL, NULL, NULL, '{"p":1}', '{"acc":0.8}', NULL, 1.0, 1)
        """)

    store = ResultStore(db_path=db_path)
    loaded = store.get_result("res_legacy")
    assert loaded is not None
    assert loaded.metric_provenance == MetricProvenance.CPU_ESTIMATED
```

- [ ] **Step 2: Run the failing tests**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest tests/ -k "roundtrips_metric_provenance or legacy_rows" -v 2>&1 | tail -15
```

Expected: FAIL (column missing from schema)

- [ ] **Step 3: Add `metric_provenance` to the `CREATE TABLE` statement in `result_store.py`**

Find the `CREATE TABLE results` DDL (lines ~32–48). Add `metric_provenance TEXT NOT NULL DEFAULT 'cpu_estimated'` as the last column:

```sql
CREATE TABLE IF NOT EXISTS results (
    id TEXT PRIMARY KEY,
    benchmark_id TEXT NOT NULL,
    network_spec_hash TEXT NOT NULL,
    timestamp TEXT NOT NULL,
    target_id TEXT,
    quantization_bits INTEGER,
    encoding_method TEXT,
    params TEXT NOT NULL,
    metrics TEXT NOT NULL,
    spike_data TEXT,
    wall_time_seconds REAL NOT NULL,
    seed INTEGER NOT NULL,
    metric_provenance TEXT NOT NULL DEFAULT 'cpu_estimated'
)
```

Apply the same addition to the `baselines` table DDL if it has identical structure.

- [ ] **Step 4: Add a migration call inside `_init_db()`**

After the `CREATE TABLE IF NOT EXISTS` statement inside `_init_db()`, add:

```python
# Migration: add metric_provenance column to pre-existing databases.
for table in ("results", "baselines"):
    try:
        conn.execute(
            f"ALTER TABLE {table} ADD COLUMN "
            "metric_provenance TEXT NOT NULL DEFAULT 'cpu_estimated'"
        )
    except Exception:
        pass  # Column already exists — sqlite3.OperationalError is expected on subsequent runs
```

- [ ] **Step 5: Update `_row_to_benchmark_result()` to read column 12**

The current method reads 12 columns (row[0]–row[11]). Add `metric_provenance` at position 12:

```python
def _row_to_benchmark_result(self, row: tuple[Any, ...]) -> BenchmarkResult:
    return BenchmarkResult(
        id=row[0],
        benchmark_id=row[1],
        network_spec_hash=row[2],
        timestamp=row[3],
        target_id=row[4],
        quantization_bits=row[5],
        encoding_method=row[6],
        params=json.loads(row[7]),
        metrics=json.loads(row[8]),
        spike_data=json.loads(row[9]) if row[9] else None,
        wall_time_seconds=row[10],
        seed=row[11],
        metric_provenance=row[12] if len(row) > 12 else "cpu_estimated",
    )
```

The `len(row) > 12` guard ensures rows read from `SELECT *` on a pre-migration database (which returns only 12 columns) fall back to `cpu_estimated`.

- [ ] **Step 6: Update `save_result()` to include `metric_provenance`**

Replace the INSERT statement (lines ~260–290) to include the new column:

```python
cursor.execute(
    """
    INSERT OR REPLACE INTO results (
        id, benchmark_id, network_spec_hash, timestamp, target_id,
        quantization_bits, encoding_method, params, metrics, spike_data,
        wall_time_seconds, seed, metric_provenance
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
        result.id,
        result.benchmark_id,
        result.network_spec_hash,
        result.timestamp,
        result.target_id,
        result.quantization_bits,
        result.encoding_method,
        result.model_dump_json(include={"params"})
            .split('{"params":', 1)[1].rsplit("}", 1)[0],
        result.model_dump_json(include={"metrics"})
            .split('{"metrics":', 1)[1].rsplit("}", 1)[0],
        result.model_dump_json(include={"spike_data"})
            .split('{"spike_data":', 1)[1].rsplit("}", 1)[0]
            if result.spike_data is not None
            else None,
        result.wall_time_seconds,
        result.seed,
        result.metric_provenance,
    ),
)
```

- [ ] **Step 7: Run the two new tests — expect PASS**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest tests/ -k "roundtrips_metric_provenance or legacy_rows" -v 2>&1 | tail -10
```

Expected: both PASS.

- [ ] **Step 8: Run full test suite — no regressions**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest -v --tb=short tests/ 2>&1 | tail -20
```

Expected: all previously-passing tests still pass.

- [ ] **Step 9: Commit**

```bash
git add Neurobench/neurobench/app/services/result_store.py \
  Neurobench/neurobench/tests/
git commit -m "feat(neurobench): persist metric_provenance in SQLite with backward-compat migration

Adds metric_provenance column to results/baselines tables via ALTER TABLE migration
(safe to run on existing databases). Updated save_result() and _row_to_benchmark_result()
to include the new column. Legacy rows without the column default to cpu_estimated."
```

---

## Task 3: Populate `metric_provenance` at all result creation sites in `benchmark_runner.py` and hardware runners

**Files:**
- Modify: `Neurobench/neurobench/app/services/benchmark_runner.py`
- Modify: `Neurobench/neurobench/app/runners/spinnaker2_runner.py`
- Modify: `Neurobench/neurobench/app/runners/synsense_runner.py`
- Modify: `Neurobench/neurobench/app/runners/pynq_runner.py`

- [ ] **Step 1: Find all `BenchmarkResult(` instantiation sites across the module**

```bash
grep -rn "BenchmarkResult(" \
  $HOME/NeuroMorphicToolKit/Neurobench/neurobench/app/ | grep -v "__pycache__"
```

Note each file and line number.

- [ ] **Step 2: Write a failing test that covers all target-to-provenance mappings**

Add to `Neurobench/neurobench/tests/test_contracts.py` (after the tests from Task 1):

```python
def test_provenance_helper_covers_all_runner_target_ids() -> None:
    """Every target_id used across benchmark_runner.py and hardware runners maps correctly."""
    # Simulation paths — all CPU-based
    for cpu_target in [None, "neurobench", "neurosense_recording", "neurosim", "neurochip"]:
        assert _provenance_from_target_id(cpu_target) == MetricProvenance.CPU_ESTIMATED, (
            f"Expected CPU_ESTIMATED for target_id={cpu_target!r}"
        )

    # Hardware paths — measured on physical neuromorphic chips
    for hw_target in ["spinnaker2", "synsense", "pynq"]:
        assert _provenance_from_target_id(hw_target) == MetricProvenance.ON_DEVICE, (
            f"Expected ON_DEVICE for target_id={hw_target!r}"
        )

    # Akida: simulator_only per modules.json localModeFallback — NOT on_device
    assert _provenance_from_target_id("akida") == MetricProvenance.CPU_ESTIMATED
```

Run it — expect FAIL before Task 1 is complete, PASS after:

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest tests/test_contracts.py::test_provenance_helper_covers_all_runner_target_ids -v 2>&1 | tail -8
```

- [ ] **Step 3: Update Site 1 (recording input, line ~160) in `benchmark_runner.py`**

Add `metric_provenance=_provenance_from_target_id("neurosense_recording")` (which resolves to `CPU_ESTIMATED`):

```python
from neurobench.contracts.benchmark_contracts import (
    BenchmarkResult,
    MetricProvenance,
    _provenance_from_target_id,
)

# Site 1 (lines ~160-171):
result = BenchmarkResult(
    id=f"res_{uuid.uuid4().hex[:8]}",
    benchmark_id=benchmark_id,
    network_spec_hash=hashlib.sha256(artifact_path.encode()).hexdigest(),
    timestamp=datetime.utcnow().isoformat() + "Z",
    target_id="neurosense_recording",
    params=run_params,
    metrics=metrics,
    spike_data=artifact_summary,
    wall_time_seconds=round(ingest_latency_ms / 1000, 6),
    seed=seed,
    metric_provenance=_provenance_from_target_id("neurosense_recording"),
)
```

- [ ] **Step 4: Update Site 2 (NeuroBench library, line ~226) in `benchmark_runner.py`**

```python
# Site 2 (lines ~226-236):
result = BenchmarkResult(
    id=f"res_{uuid.uuid4().hex[:8]}",
    benchmark_id=benchmark_id,
    network_spec_hash=network_hash,
    timestamp=datetime.utcnow().isoformat() + "Z",
    target_id="neurobench",
    params=run_params,
    metrics=metrics,
    wall_time_seconds=wall_time,
    seed=seed,
    metric_provenance=_provenance_from_target_id("neurobench"),
)
```

- [ ] **Step 5: Update Site 3 (simulation, line ~403) in `benchmark_runner.py`**

```python
# Site 3 (lines ~403-412):
result = BenchmarkResult(
    id=f"res_{uuid.uuid4().hex[:8]}",
    benchmark_id=benchmark_id,
    network_spec_hash=network_hash,
    timestamp=datetime.utcnow().isoformat() + "Z",
    params=run_params,
    metrics=metrics,
    wall_time_seconds=wall_time,
    seed=seed,
    metric_provenance=_provenance_from_target_id(None),  # simulation → cpu_estimated
)
```

- [ ] **Step 6: Update hardware runner files**

For each of `spinnaker2_runner.py`, `synsense_runner.py`, `pynq_runner.py` — find the `BenchmarkResult(...)` call and add `metric_provenance=MetricProvenance.ON_DEVICE`:

```python
# In each hardware runner file, add import:
from neurobench.contracts.benchmark_contracts import BenchmarkResult, MetricProvenance

# And at the BenchmarkResult(...) call, add:
    metric_provenance=MetricProvenance.ON_DEVICE,
```

- [ ] **Step 7: Run full test suite — no regressions**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench && \
  poetry run pytest -v --tb=short tests/ 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add \
  Neurobench/neurobench/app/services/benchmark_runner.py \
  Neurobench/neurobench/app/runners/
git commit -m "feat(neurobench): populate metric_provenance at all BenchmarkResult creation sites

Sites: recording input (cpu_estimated), NeuroBench library (cpu_estimated),
simulation (cpu_estimated), hardware runners — spinnaker2/synsense/pynq
(on_device). Uses _provenance_from_target_id() helper from contracts."
```

---

## Task 4: Flutter model update + provenance badge in `ResultsSummaryCard`

**Files:**
- Modify: `Neurobench/frontend/lib/models/result.dart`
- Modify: `Neurobench/frontend/lib/widgets/results_summary_card.dart`
- Test: `Neurobench/frontend/test/` (find or create widget test)

- [ ] **Step 1: Read the current Dart model and widget**

```bash
cat $HOME/NeuroMorphicToolKit/Neurobench/frontend/lib/models/result.dart
grep -n "targetId\|metricProvenance\|_SummaryStatusChip" \
  $HOME/NeuroMorphicToolKit/Neurobench/frontend/lib/widgets/results_summary_card.dart
```

- [ ] **Step 2: Write a failing Flutter test**

Find the Flutter test directory:
```bash
ls $HOME/NeuroMorphicToolKit/Neurobench/frontend/test/
```

Create or update a test file (e.g., `test/widgets/results_summary_card_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurobench_frontend/models/result.dart';

void main() {
  test('BenchmarkResult.fromJson parses metric_provenance', () {
    final json = {
      'id': 'r1',
      'benchmark_id': 'b1',
      'network_spec_hash': 'hash',
      'timestamp': '2026-01-01T00:00:00Z',
      'params': <String, dynamic>{},
      'metrics': <String, dynamic>{'accuracy': 0.9},
      'wall_time_seconds': 1.0,
      'seed': 42,
      'metric_provenance': 'on_device',
    };
    final result = BenchmarkResult.fromJson(json);
    expect(result.metricProvenance, equals('on_device'));
  });

  test('BenchmarkResult.fromJson defaults to cpu_estimated when field absent', () {
    final json = {
      'id': 'r1',
      'benchmark_id': 'b1',
      'network_spec_hash': 'hash',
      'timestamp': '2026-01-01T00:00:00Z',
      'params': <String, dynamic>{},
      'metrics': <String, dynamic>{'accuracy': 0.9},
      'wall_time_seconds': 1.0,
      'seed': 42,
      // no metric_provenance key
    };
    final result = BenchmarkResult.fromJson(json);
    expect(result.metricProvenance, equals('cpu_estimated'));
  });
}
```

- [ ] **Step 3: Run the failing test**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench/frontend && \
  flutter test --no-pub 2>&1 | tail -12
```

Expected: FAIL (`The getter 'metricProvenance' was called on null` or compile error)

- [ ] **Step 4: Add `metricProvenance` to `result.dart`**

In `Neurobench/frontend/lib/models/result.dart`, add `metricProvenance` as a field and update `fromJson`:

```dart
class BenchmarkResult {
  final String id;
  final String benchmarkId;
  final String networkSpecHash;
  final String timestamp;
  final String? targetId;
  final int? quantizationBits;
  final String? encodingMethod;
  final Map<String, dynamic> params;
  final Map<String, double> metrics;
  final Map<String, dynamic>? spikeData;
  final double wallTimeSeconds;
  final int seed;
  final String metricProvenance;   // ← add this field

  const BenchmarkResult({
    required this.id,
    required this.benchmarkId,
    required this.networkSpecHash,
    required this.timestamp,
    this.targetId,
    this.quantizationBits,
    this.encodingMethod,
    required this.params,
    required this.metrics,
    this.spikeData,
    required this.wallTimeSeconds,
    required this.seed,
    this.metricProvenance = 'cpu_estimated',   // ← add with default
  });

  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    return BenchmarkResult(
      id: json['id'] as String,
      benchmarkId: json['benchmark_id'] as String,
      networkSpecHash: json['network_spec_hash'] as String,
      timestamp: json['timestamp'] as String,
      targetId: json['target_id'] as String?,
      quantizationBits: json['quantization_bits'] as int?,
      encodingMethod: json['encoding_method'] as String?,
      params: (json['params'] as Map<String, dynamic>?) ?? {},
      metrics: (json['metrics'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
      spikeData: json['spike_data'] as Map<String, dynamic>?,
      wallTimeSeconds: (json['wall_time_seconds'] as num).toDouble(),
      seed: json['seed'] as int,
      metricProvenance:
          json['metric_provenance'] as String? ?? 'cpu_estimated',   // ← add this line
    );
  }
}
```

- [ ] **Step 5: Run the model tests — expect PASS**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench/frontend && \
  flutter test --no-pub 2>&1 | tail -10
```

Expected: both new model tests PASS.

- [ ] **Step 6: Update `ResultsSummaryCard` to show provenance badge**

In `Neurobench/frontend/lib/widgets/results_summary_card.dart`, replace lines 66–69 (the `_SummaryStatusChip` call for `targetId`):

```dart
// BEFORE (line ~67):
trailing: _SummaryStatusChip(
  label: latestResult.targetId ?? 'Latest run',
  icon: Icons.insights_outlined,
),

// AFTER:
trailing: _SummaryStatusChip(
  label: latestResult.metricProvenance == 'on_device'
      ? 'On-Device'
      : 'CPU Estimated',
  icon: latestResult.metricProvenance == 'on_device'
      ? Icons.memory_outlined
      : Icons.computer_outlined,
  tone: latestResult.metricProvenance == 'on_device'
      ? NmtkTone.success
      : NmtkTone.warning,
),
```

**If `_SummaryStatusChip` does not currently accept a `tone` parameter**, add it:

```dart
class _SummaryStatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final NmtkTone tone;   // ← add

  const _SummaryStatusChip({
    required this.label,
    required this.icon,
    this.tone = NmtkTone.info,   // ← add with default
  });

  @override
  Widget build(BuildContext context) {
    return NmtkStatusBadge(
      label: label,
      icon: icon,
      tone: tone,   // ← pass through
    );
  }
}
```

- [ ] **Step 7: Run full Flutter test suite — no regressions**

```bash
cd $HOME/NeuroMorphicToolKit/Neurobench/frontend && \
  flutter test --no-pub 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add \
  Neurobench/frontend/lib/models/result.dart \
  Neurobench/frontend/lib/widgets/results_summary_card.dart \
  Neurobench/frontend/test/
git commit -m "feat(neurobench-ui): show CPU Estimated / On-Device provenance badge on result card (P0 #6)

Replaces the raw targetId chip with a tone-coded badge:
- ON_DEVICE → NmtkTone.success, 'On-Device', memory icon
- CPU_ESTIMATED → NmtkTone.warning, 'CPU Estimated', computer icon
Defaults to cpu_estimated when field absent for backward compatibility."
```

---

## End-to-End Verification

Run after all 4 tasks are complete:

```bash
# 1. MetricProvenance in contracts
python3 -c "
from neurobench.contracts.benchmark_contracts import MetricProvenance, _provenance_from_target_id
assert _provenance_from_target_id('spinnaker2') == MetricProvenance.ON_DEVICE
assert _provenance_from_target_id(None) == MetricProvenance.CPU_ESTIMATED
print('PASS: provenance helper')
"

# 2. SQLite round-trip
cd Neurobench && poetry run python3 -c "
import tempfile, os
from neurobench.app.services.result_store import ResultStore
from neurobench.contracts.benchmark_contracts import BenchmarkResult, MetricProvenance
with tempfile.TemporaryDirectory() as d:
    store = ResultStore(db_path=os.path.join(d, 'test.sqlite'))
    r = BenchmarkResult(id='x', benchmark_id='b', network_spec_hash='h',
        timestamp='2026-01-01T00:00:00Z', params={}, metrics={},
        wall_time_seconds=1.0, seed=1, metric_provenance=MetricProvenance.ON_DEVICE)
    store.save_result(r)
    loaded = store.get_result('x')
    assert loaded.metric_provenance == MetricProvenance.ON_DEVICE
    print('PASS: SQLite round-trip')
"

# 3. All Python tests
poetry run pytest -v --tb=short tests/ 2>&1 | tail -10; cd ..

# 4. Flutter tests
cd Neurobench/frontend && flutter test --no-pub 2>&1 | tail -5; cd ../..
```

---

## After This Plan: What's Next

| Next Plan | Addresses |
|-----------|-----------|
| **Plan C2: neurocnl Honesty** | P1 #11 (validation panel deploy-readiness alignment), P1 #12 (pre-export topology capability check for sinabs/spinnaker2 targets) |
| **Plan D: Distribution Hardening** | P1 #10 (codesigning/notarization), P1 #13 (Neurohub CI to green), P1 #14 (golden-path CI gate) |
| **P0 #5 (Neurochip hardware path)** | Requires hardware access + dedicated investigation; separate planning session |
