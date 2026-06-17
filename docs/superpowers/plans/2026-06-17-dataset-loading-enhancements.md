# Dataset Loading Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the three main dataset-loading friction points blocking Jupyter → CNLStudio migration: (1) no `.pt` TensorDataset support despite the frontend dropdown already listing it, (2) no way to import a hyperparameter JSON file into the Pipeline tab config, (3) no in-canvas synthetic spike generator forcing the LIF notebook workaround of running external Python.

**Architecture:** Three independent features share no state. `.pt` is a pure backend code-gen extension — add one helper and wire it into the existing `_dag_node_code()` match. JSON Import Config is a pure frontend action — pick file → `PipelineConfig.fromJson()` → `canvasProvider.updatePipeline()`. Spike Generator is a new canvas node type registered in both the DAG enum and the `_dag_node_code()` match, with no backend service changes.

**Tech Stack:** Python 3.12, PyTorch (`torch.load`), FastAPI/Pydantic v2 (backend); Flutter/Dart, Riverpod (frontend); pytest (tests).

> **Scope note:** These are three independent subsystems. If implementation stalls on one, the other two ship independently.

---

## File Map

| File | Change |
|------|--------|
| `neurocnl/neurocnl/training/dataset_loader.py` | Add `DatasetFormat.pt`; extend `_resolve_dataset_format()`; add `_load_pt_dataset()` |
| `neurocnl/backend/app/routers/notebook.py` | Add `_pt_loading_code()`; add `_spike_generator_code()`; extend `_dag_node_code()` |
| `neurocnl/neurocnl/tests/test_dataset_loader.py` | Add 3 tests for `.pt` loading and format resolution |
| `neurocnl/backend/tests/test_notebook_codegen.py` | New file: tests for `_pt_loading_code()` and `_spike_generator_code()` |
| `neurocnl/frontend/lib/models/canvas/pipeline_dag.dart` | Add `spikeGenerator` enum value; add `dataset_path` to DataLoader defaults; add SpikeGenerator defaults/ports/label/category/framework |
| `neurocnl/frontend/lib/widgets/canvas/pipeline_node_property_panel.dart` | Add conditional `dataset_path` field in `_DataLoaderFields`; add `_SpikeGeneratorFields` class; wire `spikeGenerator` into `_fieldsFor()` |
| `neurocnl/frontend/lib/widgets/export_menu.dart` | Add `importConfig` action constant; add "Import Config..." button; add `_importConfig()` implementation |

---

## Task 1: `DatasetFormat.pt` — backend enum & format resolution

**Files:**
- Modify: `neurocnl/neurocnl/training/dataset_loader.py:16-96`

- [ ] **Step 1: Add `pt` to `DatasetFormat` and `.pt` extension resolution**

In `dataset_loader.py`, make these two additions:

```python
class DatasetFormat(StrEnum):
    nmnist_bin = "nmnist_bin"
    hdf5_shd = "hdf5_shd"
    hdf5_dvs_gesture = "hdf5_dvs_gesture"
    hdf5_generic_event = "hdf5_generic_event"
    aedat = "aedat"
    aedat4 = "aedat4"
    tonic_nmnist = "tonic_nmnist"
    tonic_shd = "tonic_shd"
    pt = "pt"                        # ← add this line
```

In `_resolve_dataset_format()`, add a `.pt` extension branch **before** the final `raise` (after the `.bin` check, around line 92):

```python
    if source.suffix.lower() == ".pt":
        return DatasetFormat.pt
    raise DatasetLoadError(
        f"Could not infer dataset format from '{source.name}'. "
        "Set 'format' in the dataset catalog entry."
    )
```

- [ ] **Step 2: Add `_load_pt_dataset()` and wire into `_load_samples()`**

First, find `_load_samples()` — it is the internal dispatch function that routes by `DatasetFormat`. Add a `pt` branch there **and** define the loader. The loader goes near the end of the file, before `_dense_tensor_to_samples()`:

```python
def _load_pt_dataset(
    source: Path,
    loader_config: dict[str, Any],
    *,
    max_samples: int | None,
) -> list[EventSample]:
    """Load a PyTorch TensorDataset (.pt) file.

    Supports three shapes written by the paper notebooks:
    - TensorDataset(data_tensor, label_tensor)  — torch.utils.data.TensorDataset
    - dict with keys 'data' and 'labels'
    - bare tuple (data_tensor, label_tensor)

    data_tensor shape: (N, T, F) or (N, F) where N=samples, T=timesteps, F=features.
    Labels tensor/array shape: (N,).

    The tensors are converted to numpy for downstream _dense_tensor_to_samples().
    """
    try:
        import torch
    except ImportError as exc:
        raise DatasetLoadError(
            "PyTorch is required to load .pt datasets. "
            "Install it with: pip install torch"
        ) from exc

    raw = torch.load(source, weights_only=False)  # noqa: S614

    if hasattr(raw, "tensors"):
        # TensorDataset — attribute added by torch.utils.data.TensorDataset
        tensors = raw.tensors
        if len(tensors) < 2:
            raise DatasetLoadError(
                f"TensorDataset in '{source.name}' must have at least 2 tensors "
                "(data, labels). Found only 1."
            )
        data_np = tensors[0].numpy()
        labels_np = tensors[1].long().numpy()
    elif isinstance(raw, dict):
        if "data" not in raw or "labels" not in raw:
            raise DatasetLoadError(
                f"Dict .pt file '{source.name}' must have 'data' and 'labels' keys. "
                f"Found: {sorted(raw.keys())}"
            )
        data_np = raw["data"].numpy() if hasattr(raw["data"], "numpy") else raw["data"]
        labels_np = raw["labels"].numpy() if hasattr(raw["labels"], "numpy") else raw["labels"]
    elif isinstance(raw, (tuple, list)) and len(raw) >= 2:
        data_np = raw[0].numpy() if hasattr(raw[0], "numpy") else raw[0]
        labels_np = raw[1].numpy() if hasattr(raw[1], "numpy") else raw[1]
    else:
        raise DatasetLoadError(
            f"Unrecognised .pt format in '{source.name}'. "
            "Expected TensorDataset, dict with 'data'/'labels', or a (data, labels) tuple."
        )

    import numpy as np
    data_np = np.asarray(data_np, dtype=np.float32)
    labels_np = np.asarray(labels_np, dtype=np.int64)

    if data_np.ndim == 2:
        # (N, F) → add a trivial timestep axis → (N, 1, F)
        data_np = data_np[:, np.newaxis, :]

    return _dense_tensor_to_samples(data_np, labels_np, max_samples=max_samples)
```

In `_load_samples()`, add an `if` branch **before** the final `raise` at line 191:

```python
    if dataset_format == DatasetFormat.pt:
        return _load_pt_dataset(source, loader_config, max_samples=max_samples)
    raise DatasetLoadError(f"Dataset format '{dataset_format}' is not implemented.")
```

- [ ] **Step 3: Run existing tests to confirm nothing broke**

```bash
cd neurocnl && python -m pytest neurocnl/tests/test_dataset_loader.py -v
```

Expected: all 4 existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add neurocnl/neurocnl/training/dataset_loader.py
git commit -m "feat(dataset-loader): add DatasetFormat.pt and TensorDataset loader"
```

---

## Task 2: `.pt` backend tests

**Files:**
- Modify: `neurocnl/neurocnl/tests/test_dataset_loader.py`

- [ ] **Step 1: Write failing tests**

Append to `test_dataset_loader.py`:

```python
def test_pt_format_resolved_from_extension(tmp_path: Path) -> None:
    torch = pytest.importorskip("torch")
    pt_path = tmp_path / "ds.pt"
    ds = torch.utils.data.TensorDataset(
        torch.zeros(4, 10, 3),
        torch.tensor([0, 1, 0, 1]),
    )
    torch.save(ds, pt_path)

    fixture = load_event_dataset(
        dataset_name="braille",
        dataset_path=str(pt_path),
        dataset_format=None,   # auto-infer from .pt extension
        timesteps=10,
        max_samples=4,
    )

    assert fixture.source_format == "pt"
    assert fixture.synthetic is False
    assert len(fixture.samples) == 4
    assert fixture.num_classes == 2


def test_pt_format_explicit_string(tmp_path: Path) -> None:
    torch = pytest.importorskip("torch")
    pt_path = tmp_path / "weirdname.bin"
    ds = torch.utils.data.TensorDataset(
        torch.ones(2, 5, 12),
        torch.tensor([3, 6]),
    )
    torch.save(ds, pt_path)

    fixture = load_event_dataset(
        dataset_name="braille",
        dataset_path=str(pt_path),
        dataset_format="pt",   # explicit override
        timesteps=5,
        max_samples=2,
    )

    assert fixture.source_format == "pt"
    assert fixture.num_classes == 2


def test_pt_dict_format(tmp_path: Path) -> None:
    torch = pytest.importorskip("torch")
    pt_path = tmp_path / "dict_ds.pt"
    torch.save(
        {"data": torch.zeros(3, 8, 4), "labels": torch.tensor([0, 1, 2])},
        pt_path,
    )

    fixture = load_event_dataset(
        dataset_name="custom",
        dataset_path=str(pt_path),
        dataset_format="pt",
        timesteps=8,
        max_samples=3,
    )

    assert len(fixture.samples) == 3
    assert fixture.num_classes == 3
```

- [ ] **Step 2: Run tests to see them fail**

```bash
cd neurocnl && python -m pytest neurocnl/tests/test_dataset_loader.py -v -k "pt"
```

Expected: 3 test failures (format not implemented yet is already done in Task 1 — these should PASS if Task 1 is complete; if run before Task 1, they fail with `DatasetLoadError: Unsupported dataset format 'pt'`).

- [ ] **Step 3: Confirm all 7 tests pass**

```bash
cd neurocnl && python -m pytest neurocnl/tests/test_dataset_loader.py -v
```

Expected: 7 tests pass.

- [ ] **Step 4: Commit**

```bash
git add neurocnl/neurocnl/tests/test_dataset_loader.py
git commit -m "test(dataset-loader): add .pt TensorDataset loading tests"
```

---

## Task 3: `.pt` notebook code-gen

**Files:**
- Modify: `neurocnl/backend/app/routers/notebook.py:1077-1090`

- [ ] **Step 1: Add `_pt_loading_code()` helper**

Insert this function immediately after `_tonic_loading_code()` (after line 1283):

```python
def _pt_loading_code(path: str, batch_size: int, *, shuffle: bool = True) -> str:
    """Return Python code that loads a PyTorch TensorDataset from a .pt file."""
    shuffle_str = "True" if shuffle else "False"
    return (
        "import torch\n"
        "from torch.utils.data import DataLoader\n\n"
        f"_raw = torch.load({path!r}, weights_only=False)\n"
        "# Handle TensorDataset, dict, or raw tuple\n"
        "_ds = _raw if hasattr(_raw, 'tensors') else "
        "torch.utils.data.TensorDataset(*_raw) if isinstance(_raw, (tuple, list)) "
        "else torch.utils.data.TensorDataset(_raw['data'], _raw['labels'])\n\n"
        f"train_loader = DataLoader(_ds, batch_size={batch_size}, shuffle={shuffle_str}, num_workers=0)\n"
        f"test_loader  = DataLoader(_ds, batch_size={batch_size}, shuffle=False,          num_workers=0)\n"
        f"print(f'.pt dataset: {{len(_ds)}} samples, batch_size={batch_size}')"
    )
```

- [ ] **Step 2: Wire into `_dag_node_code()` `"dataLoader"` case**

The current `"dataLoader"` case ends at line 1088:
```python
        case "dataLoader":
            bs = p.get("batch_size", cfg.batch_size)
            fmt = str(p.get("format", "auto") or "auto")
            if fmt.startswith("tonic_"):
                tw = int(p.get("time_window_ms", 1) or 1)
                return _tonic_loading_code(fmt, bs, tw)
            return _dataset_loading_code(dataset, bs)
```

Replace the last line with:
```python
        case "dataLoader":
            bs = p.get("batch_size", cfg.batch_size)
            fmt = str(p.get("format", "auto") or "auto")
            if fmt.startswith("tonic_"):
                tw = int(p.get("time_window_ms", 1) or 1)
                return _tonic_loading_code(fmt, bs, tw)
            if fmt == "pt":
                path = str(p.get("dataset_path", "") or cfg.custom_dataset_path or "./dataset.pt")
                shuffle = bool(p.get("shuffle", True))
                return _pt_loading_code(path, bs, shuffle=shuffle)
            return _dataset_loading_code(dataset, bs)
```

- [ ] **Step 3: Write failing code-gen test**

Create `neurocnl/backend/tests/test_notebook_codegen.py`:

```python
from __future__ import annotations

from neurocnl.backend.app.routers.notebook import _pt_loading_code


def test_pt_loading_code_tensordataset() -> None:
    code = _pt_loading_code("data/ds_train.pt", batch_size=64, shuffle=True)
    assert "torch.load" in code
    assert "data/ds_train.pt" in code
    assert "batch_size=64" in code
    assert "shuffle=True" in code
    assert "test_loader" in code


def test_pt_loading_code_no_shuffle() -> None:
    code = _pt_loading_code("data/ds_test.pt", batch_size=32, shuffle=False)
    assert "shuffle=False" in code
    # train_loader should also be present
    assert "train_loader" in code
```

- [ ] **Step 4: Run failing test**

```bash
cd neurocnl && python -m pytest backend/tests/test_notebook_codegen.py -v
```

Expected: 2 tests pass (the helper is already written).

- [ ] **Step 5: Commit**

```bash
git add neurocnl/backend/app/routers/notebook.py neurocnl/backend/tests/test_notebook_codegen.py
git commit -m "feat(notebook): add .pt dataset code-gen to _dag_node_code dataLoader"
```

---

## Task 4: Frontend — DataLoader `dataset_path` field for `.pt` / `npy`

**Files:**
- Modify: `neurocnl/frontend/lib/models/canvas/pipeline_dag.dart:180-185`
- Modify: `neurocnl/frontend/lib/widgets/canvas/pipeline_node_property_panel.dart:462-484`

- [ ] **Step 1: Add `dataset_path` to DataLoader and TestLoader defaults**

In `pipeline_dag.dart`, extend both default maps:

```dart
    PipelineDagNodeType.dataLoader => {
      'batch_size': 32,
      'shuffle': true,
      'format': 'auto',
      'time_window_ms': 1,
      'dataset_path': '',      // ← add
    },
    PipelineDagNodeType.testLoader => {
      'batch_size': 32,
      'shuffle': false,
      'format': 'auto',
      'time_window_ms': 1,
      'dataset_path': '',      // ← add
    },
```

- [ ] **Step 2: Add conditional `dataset_path` text field in `_DataLoaderFields`**

In `pipeline_node_property_panel.dart`, in the `_DataLoaderFields.build()` method, insert between the `tonic_` conditional block and the Batch Size field (around line 469):

```dart
        if (fmt == 'pt' || fmt == 'npy') ...[
          const SizedBox(height: 12),
          _TextField(
            label: 'Dataset Path',
            value: (p['dataset_path'] as String?) ?? '',
            hint: 'e.g. data/ds_train.pt',
            onChanged: (v) => onUpdate({...p, 'dataset_path': v}),
          ),
        ],
```

Where `fmt` is:
```dart
    final fmt = (p['format'] as String?) ?? 'auto';
```

Add that `fmt` local at the top of `build()` alongside `final p = node.parameters;`.

- [ ] **Step 3: Verify `_TextField` exists in the file**

```bash
grep -n "_TextField" neurocnl/frontend/lib/widgets/canvas/pipeline_node_property_panel.dart | head -5
```

If `_TextField` does not exist (the file uses `_IntField`, `_DropdownField`, `_SwitchField`), use a `TextField`-based widget with the same pattern as `_IntField` — create `_TextField` immediately after `_IntField`:

```dart
class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
  });

  final String label;
  final String value;
  final String hint;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: value,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Hot-restart and verify**

Start the dev server (`make dev`), open the Training canvas, add a Data Loader node, switch format to `pt` — confirm a "Dataset Path" text field appears. Switch back to `auto` — confirm it disappears.

- [ ] **Step 5: Commit**

```bash
git add neurocnl/frontend/lib/models/canvas/pipeline_dag.dart \
        neurocnl/frontend/lib/widgets/canvas/pipeline_node_property_panel.dart
git commit -m "feat(canvas): add dataset_path field to DataLoader node for .pt/npy formats"
```

---

## Task 5: JSON Import Config button

**Files:**
- Modify: `neurocnl/frontend/lib/widgets/export_menu.dart`

- [ ] **Step 1: Add import and action constant**

Add to imports at top of `export_menu.dart` (alongside existing `canonical_doc_provider.dart` import):

```dart
import '../models/canvas/pipeline_config.dart';
import '../providers/canvas/canvas_provider.dart';
```

Add to `_ExportAction` class (after line 1000):

```dart
abstract final class _ExportAction {
  static const String importNir = 'import_nir';
  static const String importConfig = 'import_config';  // ← add
  // ... existing constants unchanged ...
}
```

- [ ] **Step 2: Add "Import Config..." button to the Core card**

In the Core `_WorkspaceButtonCard` actions list (around line 165), add after the Import NIR button:

```dart
          _WorkspaceActionButton(
            icon: Icons.tune_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'Import Config...',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.importConfig),
          ),
```

- [ ] **Step 3: Add action handler in `runAction()`**

In `runAction()` (around line 276), add after the `importNir` handler:

```dart
    if (action == _ExportAction.importConfig) {
      await _importConfig(context, ref);
      return;
    }
```

- [ ] **Step 4: Add `_importConfig()` implementation**

Add this method alongside `_importNir()` (around line 423):

```dart
  Future<void> _importConfig(BuildContext context, WidgetRef ref) async {
    final files = await const FilePickerDialogGateway().pickFiles(
      allowMultiple: false,
      allowedExtensions: const ['json'],
    );
    if (files == null || files.isEmpty) return;
    final f = files.first;

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(f.bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object at the top level.');
      }
      json = decoded;
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Invalid JSON: $e', isError: true);
      return;
    }

    final config = PipelineConfig.fromJson(json);
    ref.read(canvasProvider.notifier).updatePipeline(config);

    if (!context.mounted) return;
    _showSnackBar(context, 'Pipeline config imported from ${f.name}');
  }
```

- [ ] **Step 5: Verify — hot-restart and test the flow**

1. Create a test JSON file:
   ```json
   {"epochs": 200, "learning_rate": 0.0005, "optimizer": "AdamW", "batch_size": 64}
   ```
2. Open CNLStudio → Export panel → click "Import Config..."
3. Select the JSON file.
4. Open the Pipeline tab → confirm epochs shows 200, LR shows 0.0005, optimizer shows AdamW.
5. Verify fields not in the JSON (e.g. `loss_function`) keep their defaults.

- [ ] **Step 6: Commit**

```bash
git add neurocnl/frontend/lib/widgets/export_menu.dart
git commit -m "feat(export-menu): add Import Config JSON button for pipeline hyperparameters"
```

---

## Task 6: Spike Generator node — backend code-gen

**Files:**
- Modify: `neurocnl/backend/app/routers/notebook.py`

- [ ] **Step 1: Add `_spike_generator_code()` helper**

Insert after `_pt_loading_code()`:

```python
def _spike_generator_code(
    n_neurons: int,
    n_timesteps: int,
    pattern: str,
    isi_period: int,
    rate_hz: float,
    seed: int,
) -> str:
    """Generate Python code that creates a synthetic spike dataset in memory."""
    return (
        "import torch\n"
        "from torch.utils.data import DataLoader, TensorDataset\n\n"
        f"torch.manual_seed({seed})\n"
        f"_n_neurons   = {n_neurons}\n"
        f"_n_timesteps = {n_timesteps}\n"
        f"_n_samples   = 1  # single synthetic sample\n\n"
        + _spike_pattern_code(pattern, isi_period, rate_hz)
        + "\n\n"
        "_labels = torch.zeros(_n_samples, dtype=torch.long)\n"
        "_ds = TensorDataset(_spikes.unsqueeze(0), _labels)  # (1, T, N)\n"
        f"train_loader = DataLoader(_ds, batch_size=1, shuffle=False)\n"
        f"test_loader  = DataLoader(_ds, batch_size=1, shuffle=False)\n"
        f"print(f'Spike generator: {{_n_timesteps}} timesteps x {{_n_neurons}} neurons ({pattern})')"
    )


def _spike_pattern_code(pattern: str, isi_period: int, rate_hz: float) -> str:
    """Return the tensor-creation lines for each spike pattern."""
    if pattern == "isi_regular":
        return (
            f"_spikes = torch.zeros(_n_timesteps, _n_neurons)\n"
            f"_spikes[{isi_period - 1}::{isi_period}] = 1.0  # fire every {isi_period} steps"
        )
    if pattern == "poisson":
        return (
            f"_rate   = {rate_hz} / 1000.0  # Hz → probability per ms timestep\n"
            "_spikes = (torch.rand(_n_timesteps, _n_neurons) < _rate).float()"
        )
    if pattern == "constant_rate":
        return (
            f"_interval = max(1, round(1000.0 / {rate_hz}))  # ms between spikes\n"
            "_spikes   = torch.zeros(_n_timesteps, _n_neurons)\n"
            "_spikes[::_interval] = 1.0"
        )
    # fallback: all zeros
    return "_spikes = torch.zeros(_n_timesteps, _n_neurons)"
```

- [ ] **Step 2: Wire into `_dag_node_code()`**

Add a new `case` after `"spikeEncoder"` (around line 1092):

```python
        case "spikeGenerator":
            return _spike_generator_code(
                n_neurons=int(p.get("n_neurons", 1)),
                n_timesteps=int(p.get("n_timesteps", 100)),
                pattern=str(p.get("pattern", "isi_regular")),
                isi_period=int(p.get("isi_period", 10)),
                rate_hz=float(p.get("rate_hz", 10.0)),
                seed=int(p.get("seed", 42)),
            )
```

- [ ] **Step 3: Write and run failing tests**

Add to `neurocnl/backend/tests/test_notebook_codegen.py`:

```python
from neurocnl.backend.app.routers.notebook import _spike_generator_code


def test_spike_gen_isi_regular() -> None:
    code = _spike_generator_code(
        n_neurons=1, n_timesteps=100, pattern="isi_regular",
        isi_period=10, rate_hz=10.0, seed=42,
    )
    assert "torch.zeros" in code
    assert "10" in code          # isi_period
    assert "train_loader" in code
    assert "test_loader" in code


def test_spike_gen_poisson() -> None:
    code = _spike_generator_code(
        n_neurons=4, n_timesteps=256, pattern="poisson",
        isi_period=10, rate_hz=50.0, seed=0,
    )
    assert "torch.rand" in code
    assert "50.0" in code        # rate_hz


def test_spike_gen_constant_rate() -> None:
    code = _spike_generator_code(
        n_neurons=1, n_timesteps=100, pattern="constant_rate",
        isi_period=10, rate_hz=100.0, seed=7,
    )
    assert "1000.0" in code
    assert "100.0" in code
```

Run:
```bash
cd neurocnl && python -m pytest backend/tests/test_notebook_codegen.py -v
```

Expected: all 5 tests pass (2 from Task 3 + 3 new).

- [ ] **Step 4: Commit**

```bash
git add neurocnl/backend/app/routers/notebook.py neurocnl/backend/tests/test_notebook_codegen.py
git commit -m "feat(notebook): add spikeGenerator node code-gen with isi/poisson/constant-rate patterns"
```

---

## Task 7: Spike Generator node — frontend

**Files:**
- Modify: `neurocnl/frontend/lib/models/canvas/pipeline_dag.dart`
- Modify: `neurocnl/frontend/lib/widgets/canvas/pipeline_node_property_panel.dart`

- [ ] **Step 1: Add `spikeGenerator` to the enum and all switches**

In `pipeline_dag.dart`, add `spikeGenerator` to the enum **in the Data section** (after `spikeEncoder`):

```dart
enum PipelineDagNodeType {
  // Data
  dataLoader,
  testLoader,
  spikeEncoder,
  spikeGenerator,   // ← add here
  // Time control
  ...
```

Add to the `label` switch (after `spikeEncoder => 'Spike Encoder'`):
```dart
    PipelineDagNodeType.spikeGenerator => 'Spike Generator',
```

Add to the `category` switch (after `spikeEncoder` line):
```dart
    PipelineDagNodeType.spikeGenerator => PipelineDagCategory.data,
```

Add to `defaultParameters` (after `spikeEncoder` entry):
```dart
    PipelineDagNodeType.spikeGenerator => {
      'n_neurons': 1,
      'n_timesteps': 100,
      'pattern': 'isi_regular',
      'isi_period': 10,
      'rate_hz': 10.0,
      'seed': 42,
    },
```

Add to `frameworkVisibility` — the `spikeEncoder` is already in the `snntorch_sim` group (line ~171). Extend that `||` chain to include `spikeGenerator`:

```dart
    // snnTorch-specific
    PipelineDagNodeType.mseCountLoss ||
    PipelineDagNodeType.membraneLoss ||
    PipelineDagNodeType.l1SpikeReg ||
    PipelineDagNodeType.l2SpikeReg ||
    PipelineDagNodeType.surrogateBackward ||
    PipelineDagNodeType.bpttBackward ||
    PipelineDagNodeType.spikeEncoder ||
    PipelineDagNodeType.spikeGenerator ||   // ← add this line
    PipelineDagNodeType.spikeRecorder ||
    PipelineDagNodeType.membraneRecorder ||
    PipelineDagNodeType.timeLoop => const {'snntorch_sim'},
```

Add output ports — find the `dataLoader || testLoader` port branch and extend it:
```dart
    PipelineDagNodeType.dataLoader ||
    PipelineDagNodeType.testLoader ||
    PipelineDagNodeType.spikeGenerator => const [  // ← add spikeGenerator
      PortSpec('data', PortType.data),
      PortSpec('labels', PortType.any),
    ],
```

- [ ] **Step 2: Add `_SpikeGeneratorFields` widget**

In `pipeline_node_property_panel.dart`, add after `_DataLoaderFields`:

```dart
class _SpikeGeneratorFields extends ConsumerWidget {
  const _SpikeGeneratorFields({required this.node, required this.onUpdate});

  final PipelineDagNode node;
  final void Function(Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = node.parameters;
    final pattern = (p['pattern'] as String?) ?? 'isi_regular';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IntField(
          label: 'Neurons',
          value: (p['n_neurons'] as int?) ?? 1,
          onChanged: (v) => onUpdate({...p, 'n_neurons': v}),
        ),
        const SizedBox(height: 12),
        _IntField(
          label: 'Timesteps',
          value: (p['n_timesteps'] as int?) ?? 100,
          onChanged: (v) => onUpdate({...p, 'n_timesteps': v}),
        ),
        const SizedBox(height: 12),
        _DropdownField<String>(
          label: 'Pattern',
          value: pattern,
          options: const ['isi_regular', 'poisson', 'constant_rate'],
          onChanged: (v) => onUpdate({...p, 'pattern': v}),
        ),
        if (pattern == 'isi_regular') ...[
          const SizedBox(height: 12),
          _IntField(
            label: 'ISI Period (steps)',
            value: (p['isi_period'] as int?) ?? 10,
            onChanged: (v) => onUpdate({...p, 'isi_period': v}),
          ),
        ],
        if (pattern == 'poisson' || pattern == 'constant_rate') ...[
          const SizedBox(height: 12),
          _FloatField(
            label: 'Rate (Hz)',
            value: (p['rate_hz'] as num?)?.toDouble() ?? 10.0,
            onChanged: (v) => onUpdate({...p, 'rate_hz': v}),
          ),
        ],
        const SizedBox(height: 12),
        _IntField(
          label: 'Seed',
          value: (p['seed'] as int?) ?? 42,
          onChanged: (v) => onUpdate({...p, 'seed': v}),
        ),
      ],
    );
  }
}
```

> **Note:** `_FloatField` may not exist. Check with:
> ```bash
> grep -n "_FloatField\|class _Float" neurocnl/frontend/lib/widgets/canvas/pipeline_node_property_panel.dart
> ```
> If absent, add it following the `_IntField` pattern but with `TextFormField` and `double.tryParse`:
> ```dart
> class _FloatField extends StatelessWidget {
>   const _FloatField({required this.label, required this.value, required this.onChanged});
>   final String label;
>   final double value;
>   final void Function(double) onChanged;
>   @override
>   Widget build(BuildContext context) {
>     return Column(
>       crossAxisAlignment: CrossAxisAlignment.start,
>       children: [
>         Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
>         const SizedBox(height: 4),
>         TextFormField(
>           initialValue: value.toString(),
>           decoration: const InputDecoration(
>             isDense: true,
>             contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
>             border: OutlineInputBorder(),
>           ),
>           style: const TextStyle(fontSize: 12),
>           keyboardType: const TextInputType.numberWithOptions(decimal: true),
>           onChanged: (s) {
>             final parsed = double.tryParse(s);
>             if (parsed != null) onChanged(parsed);
>           },
>         ),
>       ],
>     );
>   }
> }
> ```

- [ ] **Step 3: Wire `spikeGenerator` into `_fieldsFor()`**

Find `_fieldsFor()` (or equivalent switch/factory that maps node type to property widget). Add:

```dart
    PipelineDagNodeType.spikeGenerator => _SpikeGeneratorFields(
      node: node,
      onUpdate: onUpdate,
    ),
```

- [ ] **Step 4: Hot-restart and verify**

1. Open Training canvas → node palette → Data section → confirm "Spike Generator" appears.
2. Drag it onto the canvas → open properties → confirm Neurons, Timesteps, Pattern dropdowns.
3. Switch Pattern to `poisson` → confirm Rate (Hz) appears, ISI Period disappears.
4. Generate notebook → confirm the cell contains `torch.rand` (poisson) or `::10` (isi_regular).

- [ ] **Step 5: Commit**

```bash
git add neurocnl/frontend/lib/models/canvas/pipeline_dag.dart \
        neurocnl/frontend/lib/widgets/canvas/pipeline_node_property_panel.dart
git commit -m "feat(canvas): add Spike Generator node for synthetic in-canvas data generation"
```

---

## Verification

### End-to-end `.pt` check (Braille notebook replication)

1. Open CNLStudio Training canvas.
2. Add a **Data Loader** node, set format to `pt`, dataset path to `paper/03_rnn/data/ds_train.pt`, batch_size 64, shuffle on.
3. Add a **Test Loader** node, set format to `pt`, dataset path to `paper/03_rnn/data/ds_test.pt`, batch_size 64, shuffle off.
4. Click **Generate Notebook** → open the `.ipynb`.
5. Confirm cell 2 contains `torch.load('paper/03_rnn/data/ds_train.pt', weights_only=False)`.
6. Run the notebook → confirm `DataLoader` wraps the TensorDataset without errors.

### End-to-end JSON Import Config check

1. Save `{"epochs": 300, "learning_rate": 0.0002, "optimizer": "SGD", "batch_size": 128}` as `test_config.json`.
2. Export panel → "Import Config..." → select `test_config.json`.
3. Navigate to Pipeline tab → confirm epochs=300, LR=0.0002, optimizer=SGD, batch_size=128.
4. Confirm `loss_function` still shows default (MSE Count Loss).

### End-to-end Spike Generator check (LIF notebook replication)

1. Open CNLStudio Eval canvas.
2. Add a **Spike Generator** node: n_neurons=1, n_timesteps=100, pattern=isi_regular, isi_period=10.
3. Connect: Spike Generator → State Reset → Forward Pass → Spike Rate Logger.
4. Click **Generate Notebook** → confirm cell contains `torch.zeros(100, 1)` and `[::10] = 1.0`.
5. Run the notebook → confirm it executes without importing any external dataset file.

### Backend tests

```bash
cd neurocnl && python -m pytest neurocnl/tests/test_dataset_loader.py backend/tests/test_notebook_codegen.py -v
```

Expected: 10 tests pass (7 dataset_loader + 3 notebook_codegen for spike_gen, 2 earlier pt codegen will already be counted).
