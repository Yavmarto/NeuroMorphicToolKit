# Notebook 2 (`snntorch_sim`) — `weights.npz` KeyError Fix Plan

**Date:** 2026-07-06
**Scope:** `KeyError: 'n_0_weight' is not a file in the archive'` raised on `net = Net().float()` in a `generate-v2` notebook targeting `snntorch_sim`. A prior agent claimed this flow "completely worked" — it does not, and the gap is a testing blind spot, not a one-off fluke.

## Symptom

The generated `Net.__init__` does:
```python
self.n_0 = nn.Conv2d(2, 16, (5, 5), stride=(2, 2), padding=(1, 1), bias=True)
self.n_0.weight.data = torch.from_numpy(_w['n_0_weight'].copy())
```
against `_w = np.load('weights.npz')`, and `weights.npz` does not actually contain `n_0_weight`. The code cell and the weights dict are generated from the *same* pass over the *same* graph inside `_generate_snntorch_code` (`neurocnl/backend/app/routers/notebook.py (421-846)`), so the key names are provably consistent with each other at generation time. A `KeyError` (not a `FileNotFoundError`) therefore means the notebook is loading a `weights.npz` that exists but was written for a **different** architecture than the one whose code it is running.

## Root cause 1 — `weights.npz` is a shared, non-namespaced artifact

`_build_v2_notebook` (`neurocnl/backend/app/routers/notebook.py (2059-2065)`) always writes the artifact under the fixed name `weights.npz`, and `generate_notebook_v2` (`neurocnl/backend/app/routers/notebook.py (2118-2132)`) writes it into `{workspace_folder}/notebooks/weights.npz` — one file per **workspace**, not per notebook/target/architecture (the `.ipynb` filename *is* namespaced by target: `pipeline_{cfg.framework}.ipynb`, but the weights file is not). It is only overwritten `if arch_weights:` is truthy for the *current* call. Any earlier generation in the same workspace (an earlier architecture iteration, a different target, or a since-edited CNL spec) leaves its `weights.npz` in place until a later call happens to produce non-empty `arch_weights` again. A user iterating on the Architecture tab — exactly the reported workflow — can regenerate the notebook after materially changing the graph and still end up executing against a stale, structurally different `weights.npz` sitting next to it.

## Root cause 2 — custom kernel runner never sets the working directory

`workers/jupyter_server/nmtk_env_manager/handlers.py::_execute_notebook_job` (199-246) starts the execution kernel with:
```python
kernel_manager = jupyter_client.KernelManager(kernel_name=resolved_kernel)
kernel_manager.start_kernel()
```
No `cwd` is passed anywhere. Verified against the installed `jupyter_client` source: `KernelManager.start_kernel(**kw)` forwards `kw` through `pre_start_kernel` → `LocalProvisioner.pre_launch(**kwargs)` (`local_provisioner.py`, no `cwd` default set) → `launcher.launch_kernel(cmd, **kwargs)`, whose signature is `cwd: Optional[str] = None` and only sets `Popen`'s `cwd` `if cwd:` truthy. With no `cwd` supplied, the kernel subprocess inherits the **Jupyter-worker process's own cwd**, not `{workspace}/notebooks/` where `weights.npz` was actually written. Every relative path in generated notebooks (`np.load('weights.npz')`, `tonic.datasets.NMNIST(save_to='data/')`, etc.) is therefore at the mercy of whatever the server process's cwd happens to be whenever this API-triggered execution path runs — a second, independent way to load an unrelated, stale `weights.npz`.

Either root cause alone reproduces the exact symptom (a `KeyError`, implying some file was found, just the wrong one). Both are real defects and should be fixed together.

## Why this slipped through review

`neurocnl/backend/tests/test_notebook_generate_v2.py` only calls `_build_v2_notebook` directly and asserts the in-memory `nb`/`artifacts` pair is internally consistent (e.g. `test_snntorch_notebook_preserves_imported_weight_values`, `test_snntorch_notebook_supports_imported_mixed_nir_graph`). Nothing exercises `generate_notebook_v2`'s on-disk write path across two calls to the same `workspace_path`, and nothing exercises `_execute_notebook_job`'s working directory. A prior "it works" claim was true for a single, one-shot in-memory codegen check and never tested the real user path (regenerate → run).

## Fix

1. **Namespace `weights.npz` per notebook/target** instead of per workspace folder, e.g. `weights_{cfg.framework}.npz`, matching the existing `pipeline_{cfg.framework}.ipynb` convention. Update the three codegen functions that reference it (`_generate_snntorch_code`, `_generate_sc_neurocore_code`, `_generate_akida_code` in `neurocnl/backend/app/routers/notebook.py`) and the artifact key set in `_build_v2_notebook` accordingly. This removes cross-generation/cross-target artifact collisions in the same workspace folder entirely, rather than relying on every future call happening to overwrite it correctly.
2. **Set the kernel's working directory explicitly** in `_execute_notebook_job`:
   ```python
   kernel_manager.start_kernel(cwd=str(resolved_path.parent))
   ```
   so relative paths in any programmatically-executed notebook always resolve next to the notebook file, independent of the worker process's own cwd.
3. **Fail closed with an actionable error** (per this repo's end-user-convenience/error-message rule) instead of a bare `KeyError`: emit a small helper in the generated snnTorch/SC-NeuroCore/Akida cells that checks all expected `_w` keys up front and raises a clear message (e.g. `"weights.npz does not match this notebook's architecture — regenerate the notebook from the Architecture tab."`) rather than crashing deep inside `Net.__init__` on an opaque `KeyError`.
4. **Regression tests:**
   - `workers/jupyter_server/nmtk_env_manager/tests/test_handlers_execute.py`: capture the kwargs passed to `FakeKernelManager.start_kernel`/`blocking_client` and assert `cwd == str(notebook_path.parent)`.
   - `neurocnl/backend/tests/test_notebook_generate_v2.py` (or a new endpoint-level test): invoke the disk-writing path (`generate_notebook_v2`, or a thin wrapper around it) twice for the same `workspace_path` with two structurally different specs, and assert the second call's weights artifact contains only the second graph's keys — proving no cross-generation staleness is possible with the new per-target filename.
   - A codegen-level test asserting the new key-validation cell/error message is present in generated `snntorch_sim` code.

## Files touched
- `neurocnl/backend/app/routers/notebook.py`
- `workers/jupyter_server/nmtk_env_manager/handlers.py`
- `neurocnl/backend/tests/test_notebook_generate_v2.py`
- `workers/jupyter_server/nmtk_env_manager/tests/test_handlers_execute.py`

## Verification
- `PYTHONPATH=. pytest neurocnl/backend/tests/test_notebook_generate_v2.py`
- `pytest workers/jupyter_server/nmtk_env_manager/tests/test_handlers_execute.py`
- `ruff check neurocnl/backend/app/routers/notebook.py workers/jupyter_server/nmtk_env_manager/handlers.py`
- `mypy` over both touched modules per `neurocnl/AGENTS.md`
- Manual repro: regenerate the CNN spec from this bug report twice in the same workspace (once as a smaller/older architecture, once as the reported 13-hidden-node CNN) via `/notebook/generate-v2`, then run the resulting notebook end-to-end and confirm no `KeyError`.
