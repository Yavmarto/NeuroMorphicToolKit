# Fix: `NIRGraph.__init__() got an unexpected keyword argument 'type_check'`

## Context

Loading a `.nire` file in the Flutter app triggers three errors, all with the message `NIRGraph.__init__() got an unexpected keyword argument 'type_check'`. The backend is the `suite_api` process running in a venv at `.nmtk/suite_api_env/venv/` (PID 88002, using anaconda Python 3.12). Investigation showed the venv directory has since been deleted (only `install-fingerprint.json` remains) but the process is still running with the old venv's files in memory.

## Root Cause

The running backend has a **nir version mismatch** where:

- `nir.read()` (in `nir/serialization.py`) adds `type_check=True` to the data dict and ultimately calls `NIRGraph(**kwargs)` where `kwargs` contains `type_check=True`
- But the installed nir's `NIRGraph.__init__` does **not** accept `type_check` as a parameter

This means `nir.read()` **always fails** in the current running environment.

The existing compat shim (`_nir_compat.py`) only guards calls to `nir.NIRGraph()` made by *our* code via `make_nir_graph()`. It cannot intercept the `type_check` kwarg that `nir.read()` adds internally to the graph data dict before calling `NIRGraph.from_dict → NIRGraph(**kwargs)`.

### Why three errors?

1. **`updateFromNirFile`** → calls `POST /nir-to-canonical` → `nir.read()` fails → HTTP 422 → Dart prints the error
2. **`parseCnl` / `updateFromCnl`** → both call `POST /parse-cnl-canonical` → `canonical_from_cnl()` → `compile_to_nir()` → `make_nir_graph()`. Here the shim's `NIR_HAS_TYPE_CHECK` detection **is also wrong** for this nir build (the compat shim sees `type_check` in `inspect.signature(nir.NIRGraph)` but the actual call still fails — a sign this is a transitional/dev nir build with inconsistent signature metadata). The reactive chain after the failed NIR load triggers these calls automatically.

Also: the `GET /generate-cnl-from-nir` endpoint (used by older compiled Dart code that may not have been hot-restarted) also calls `nir.read()` and fails the same way.

## Fix

### 1. Extend `_nir_compat.py` — add `safe_nir_read()`

**File:** `neurocnl/neurocnl/_nir_compat.py`

Add two things after the existing capability flags:

```python
# Detect whether nir.read() itself passes type_check into the data dict
_NIR_READ_PARAMS: frozenset[str] = (
    frozenset(inspect.signature(nir.read).parameters.keys())
    if hasattr(nir, "read")
    else frozenset()
)
NIR_READ_HAS_TYPE_CHECK: bool = "type_check" in _NIR_READ_PARAMS
```

Add a new helper function:

```python
def safe_nir_read(filename: str | os.PathLike[str]) -> nir.NIRGraph:
    """Read a ``.nir`` HDF5 file, tolerating nir version mismatches.

    On nir builds where ``nir.read()`` internally injects ``type_check``
    into the deserialized data dict but ``NIRGraph.__init__`` does not
    accept it (a transitional build inconsistency), this function falls
    back to the lower-level ``nir`` internals to reconstruct the graph
    without passing ``type_check``.
    """
    try:
        return nir.read(str(filename))
    except TypeError as exc:
        if "type_check" not in str(exc):
            raise
        # Mismatch: serialization layer passes type_check but NIRGraph
        # constructor rejects it.  Fall back to manual HDF5 read.
        try:
            import h5py
            from nir.serialization import hdf2dict
            with h5py.File(str(filename), "r") as _f:
                _data = hdf2dict(_f["node"])
            return nir.dict2NIRNode(_data)
        except (ImportError, AttributeError, KeyError):
            # If internals aren't accessible, re-raise with a clear message
            raise RuntimeError(
                "nir version incompatibility: nir.read() passes 'type_check' "
                "to NIRGraph but the installed nir does not accept it. "
                f"Please reinstall nir>=1.0.0 consistently. "
                f"Original error: {exc}"
            ) from exc
```

Also add a fallback safety net to `make_nir_graph()` itself — wrap the `nir.NIRGraph()` call in a try/except to handle the case where `NIR_HAS_TYPE_CHECK` detection is wrong:

```python
def make_nir_graph(...) -> nir.NIRGraph:
    if skip_type_check and NIR_HAS_TYPE_CHECK:
        kwargs["type_check"] = False
    try:
        return nir.NIRGraph(nodes=nodes, edges=edges, **kwargs)
    except TypeError as exc:
        if "type_check" not in str(exc):
            raise
        # Detection was wrong — nir claims type_check in signature but rejects it.
        # Strip it and retry.
        kwargs.pop("type_check", None)
        return nir.NIRGraph(nodes=nodes, edges=edges, **kwargs)
```

### 2. Use `safe_nir_read()` in all `nir.read()` call sites in the backend

**File:** `neurocnl/neurosim/app/routers/generation.py`

There are **two** places where `nir.read(handle.name)` is called:

**In `nir_bytes_to_canonical`** (line ~312):
```python
# Replace:
nir_graph = nir.read(handle.name)
# With:
from neurocnl._nir_compat import safe_nir_read
nir_graph = safe_nir_read(handle.name)
```

**In `generate_cnl_from_uploaded_nir`** (line ~357, inside the second `NamedTemporaryFile` block — check exact line):
```python
# Replace:
graph = nir.read(handle.name)
# With:
from neurocnl._nir_compat import safe_nir_read
graph = safe_nir_read(handle.name)
```

Move the imports to the top of the file alongside the existing `import nir` if preferred.

## Files to modify

| File | Change |
|------|--------|
| `neurocnl/neurocnl/_nir_compat.py` | Add `NIR_READ_HAS_TYPE_CHECK` flag, `safe_nir_read()` helper, fallback try/except in `make_nir_graph()` |
| `neurocnl/neurosim/app/routers/generation.py` | Replace `nir.read(handle.name)` with `safe_nir_read(handle.name)` in `nir_bytes_to_canonical` and `generate_cnl_from_uploaded_nir` |

## Verification

1. Restart the backend server so it picks up a fresh venv (required anyway since the current venv has been deleted — `make suite_api_dev` or equivalent should reinstall)
2. In the Flutter app, load a `.nire` file — should no longer show the `type_check` error
3. Verify `CanonicalDocNotifier.updateFromNirFile` succeeds and the canvas populates
4. Verify typing in the CNL editor (`parseCnl` / `updateFromCnl`) still works
5. Run the Python test suite: `cd neurocnl && python -m pytest neurocnl/tests/ -x -q` — all nir-related tests should pass

## Note on the deleted venv

The suite_api venv at `.nmtk/suite_api_env/venv/` has been deleted while the server is still running. After the code fix, restart the server — the launcher will reinstall the venv with a consistent nir version. The code fix makes the backend resilient to this class of nir version mismatch going forward.
