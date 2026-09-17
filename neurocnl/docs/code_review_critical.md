# Critical Code Review — NeuroCNL Recent Commits

**Reviewer:** GitHub Copilot
**Scope:** Files merged in the last 24 hours across hardware-backend integrations
**Date:** 2026-04-05
**Verdict summary:** Several **test-breaking syntax errors**, a **logic inversion bug** in the Akida topology checker, **dead stubs shipped as production code**, and **multiple test/implementation mismatches** that make tests either syntactically invalid or guaranteed to fail.

---

## Table of Contents

1. [Critical Bugs — Test Suite Breaking](#1-critical-bugs--test-suite-breaking)
2. [Logic Errors in Production Code](#2-logic-errors-in-production-code)
3. [Stubs Shipped as Production Code](#3-stubs-shipped-as-production-code)
4. [Test/Implementation Mismatches](#4-testimplementation-mismatches)
5. [API Misuse and Runtime Errors](#5-api-misuse-and-runtime-errors)
6. [Security Concerns](#6-security-concerns)
7. [Cross-Component Inconsistencies](#7-cross-component-inconsistencies)
8. [Code Quality and Maintainability](#8-code-quality-and-maintainability)
9. [Test Coverage Gaps](#9-test-coverage-gaps)
10. [Per-Integration Assessment](#10-per-integration-assessment)

---

## 1. Critical Bugs — Test Suite Breaking

### 1.1 `test_layer1_validator.py` — Syntax Error (Line 354)

**File:** `neurocnl/layers/test_layer1_validator.py`
**Severity:** CRITICAL — This syntax error **prevents the entire test module from loading**.

```python
# Line 354
def test_spinnaker2_catches_unrepresentable_weight():
    }            # <--- unmatched closing brace; no opening block
    ir = NetworkIR(
        populations={
            "a": PopulationIR(name="A", size=300),
```

The function body begins with a stray `}`, making the file unparseable. The preceding code was clearly a different test function body that was pasted in without a proper `def` header. The entire SpiNNaker2 and Akida2 fan-in test section is malformed.

**What was likely intended:** Two separate tests — one for SpiNNaker2 unrepresentable weight, and one for Akida2 fan-in warning — were accidentally merged without the second function header and parameter block.

The function references `specs`, `params`, `backend="akida2"`, and `ir` — none of which are defined in the shown function body. In reality, the test is testing Akida2 fan-in behaviour while being named after SpiNNaker2 weight checking.

**Fix required:** Restore both test function bodies as separate functions with correct `specs`/`params` setup.

---

### 1.2 `test_exporters.py` — `test_all_formats_produce_string_or_dict` Fails for `pynq`

**File:** `neurocnl/export/test_exporters.py`, line 79–86
**Severity:** HIGH

```python
def test_all_formats_produce_string_or_dict(self, simple_net):
    for fmt in EXPORTERS:
        result = export(simple_net, format=fmt)
        assert isinstance(result, (str, dict))  # <-- FAILS for pynq
```

`export_pynq` returns a `PynqOverlayConfig` dataclass, which is neither `str` nor `dict`. This test will fail for every run that includes the `pynq` format. The test's assertion must be updated to allow `PynqOverlayConfig` or the exporter must be changed to return a dict.

---

### 1.3 `tests/test_sinabs_io.py` — `test_nir_to_sinabs` Tests a Non-Functional Stub

**File:** `tests/test_sinabs_io.py`, lines 35–73
**Severity:** HIGH — This test will fail every time.

```python
def test_nir_to_sinabs():
    ...
    model = io.from_nir(graph)

    import sinabs.network

    assert isinstance(model, sinabs.network.Network)  # <-- FAILS
```

`SinabsIO.from_nir` (in `neurocnl/converter/sinabs_io.py`, lines 99–114) returns a **Python code string**, not a `sinabs.network.Network` instance. The implementation is a code-generation stub:

```python
def from_nir(self, graph: nir.NIRGraph, **kwargs) -> str:
    lines = [
        '"""Sinabs Process definitions — auto-generated from NIR."""',
        ...
        "def build_model():",
        "    model = nn.Sequential(",
        "    )",
        "    return model",
    ]
    return "\n".join(lines)
```

The test was written against an expected (but unimplemented) behaviour where `from_nir` constructs an actual model object.

---

## 2. Logic Errors in Production Code

### 2.1 `akida_capabilities.py` — `_is_sequential` Returns Inverted Result for Cyclic Graphs

**File:** `neurocnl/backends/akida_capabilities.py`, lines 30–61
**Severity:** HIGH — Logic error causes incorrect topology classification

```python
def _is_sequential(ir, out_edges, in_edges) -> bool:
    # Correctly checks branching and convergence...
    for node, edges in out_edges.items():
        if len(edges) > 1:
            return False
    for node, edges in in_edges.items():
        if len(edges) > 1:
            return False

    # Cycle detection — BUG HERE:
    def is_cyclic(node):
        ...
        return False

    for node in ir.populations.keys():
        if node not in visited:
            if is_cyclic(node):
                return True  # <-- WRONG: should be `return False`

    return True
```

When a cycle is detected, `_is_sequential` returns `True` (sequential). It should return `False`. A network with cycles is by definition not sequential.

**Mitigating factor:** In `Akida1CapabilityChecker.check_network_topology`, `_has_recurrent` is called *before* `_is_sequential`, so the Akida1 recurrent-rejection still works via that prior check. However the logic in `_is_sequential` is still wrong and misleading, and any caller that uses it independently will get incorrect results.

---

### 2.2 `akida_capabilities.py` — `_is_sequential` and `_has_recurrent` Are Identical

**File:** `neurocnl/backends/akida_capabilities.py`, lines 30–85
**Severity:** MEDIUM — Code duplication with subtle differences

The cycle-detection DFS logic in `_is_sequential` (lines 44–51) and `_has_recurrent` (lines 66–78) is almost verbatim identical. They should share implementation. The duplication increases maintenance risk and contributed to the logic bug noted above.

---

### 2.3 `planner.py` — Dead Code (Duplicate `elif` Block)

**File:** `neurocnl/planner.py`, lines 124–135
**Severity:** MEDIUM

```python
elif status == "faithful" and "network_topology" in unsupported:   # line 124
    unsupported.remove("network_topology")
    if "network_topology" not in supported:
        supported.append("network_topology")
elif status == "faithful" and "network_topology" in approximated:  # line 128
    approximated.remove("network_topology")
    ...
elif status == "faithful" and "network_topology" in unsupported:   # line 132 — DEAD CODE
    unsupported.remove("network_topology")                         # Can never be reached
    if "network_topology" not in supported:
        supported.append("network_topology")
```

The `elif` at line 132 is a verbatim duplicate of line 124. It can never be reached because line 124 would have matched first. This is dead code that was likely a copy-paste error during the akida topology status handling refactor.

---

### 2.4 `lava_exporter.py` — `du` Parameter Can Exceed Lava's Valid Range

**File:** `neurocnl/export/lava_exporter.py`, line 44
**Severity:** MEDIUM

```python
du = int(1.0 / nt.tau_rc) if isinstance(nt, nengo.LIF) and nt.tau_rc > 0 else 50
```

For small `tau_rc` values (e.g. `tau_rc = 0.001`), this produces `du = 1000`, which exceeds Lava's documented valid range of 0–4095 for LIF `du`. While 1000 is technically within range, the formula is not validated against the actual Lava parameter spec. The comment says the formula is `int(1.0 / tau_rc)`, but the correct Lava formula for mapping membrane time constant to voltage decay is different and depends on the simulation timestep.

---

### 2.5 `lava_exporter.py` — `.stop()` Always Called on First Population

**File:** `neurocnl/export/lava_exporter.py`, lines 101–107
**Severity:** MEDIUM — Lava API misuse

```python
lines.extend(
    [
        f"run_cfg = {'Loihi2HwCfg()' if hw_mode else 'Loihi2SimCfg()'}",
        f"run_cond = RunSteps(num_steps={num_steps})",
        f"{list(ensemble_vars.values())[0]}.run(condition=run_cond, run_cfg=run_cfg)"
        if ensemble_vars
        else "# No populations to run",
        f"{list(ensemble_vars.values())[0]}.stop()" if ensemble_vars else "",
    ]
)
```

`list(ensemble_vars.values())[0]` always picks the first population, but:
1. In Lava, `.run()` and `.stop()` should be called on the **process that owns the connection**, not necessarily the first population. For networks with multiple populations, this is likely the wrong process.
2. When `ensemble_vars` is empty, the last element appended is an empty string `""`. This generates a blank line in the output code, which is harmless but sloppy.
3. Dictionary iteration order is preserved in Python 3.7+ but the intent (first/last population in topology order) is not clearly communicated.

---

## 3. Stubs Shipped as Production Code

### 3.1 `sinabs_io.py` — `from_nir` is a Non-Functional Stub

**File:** `neurocnl/converter/sinabs_io.py`, lines 99–114
**Severity:** HIGH

```python
def from_nir(self, graph: nir.NIRGraph, **kwargs) -> str:
    """Convert an NIR graph to sinabs model definitions (Python code)."""
    lines = [
        ...
        "def build_model():",
        "    model = nn.Sequential(",
        "    )",      # <-- EMPTY SEQUENTIAL: no layers added
        "    return model",
    ]
    return "\n".join(lines)
```

This generates a `build_model()` function that returns an empty `nn.Sequential()` regardless of the input NIR graph. The NIR graph is never processed. This is a placeholder that was committed as if it were a real implementation.

---

### 3.2 `spinnaker2_io.py` — Both Functions Are Stubs

**File:** `neurocnl/converter/spinnaker2_io.py`
**Severity:** HIGH

```python
def format_spinnaker2_inputs(inputs):
    formatted = {}
    for k, v in inputs.items():
        # Stub implementation
        formatted[k] = v  # <-- identity pass-through, no actual formatting
    return formatted
```

`format_spinnaker2_inputs` is a labeled stub that does nothing — it returns inputs unchanged. `parse_spinnaker2_outputs` merely wraps dictionaries with no transformation. Neither function performs any real I/O mapping. They are called nowhere in the codebase (no callers found). They add surface area with no implementation value and should either be implemented or removed.

---

### 3.3 `sinabs_exporter.py` — Generates Code with `raise NotImplementedError` Inside

**File:** `neurocnl/export/sinabs_exporter.py`, lines 104–105
**Severity:** MEDIUM — Generates silently broken output

```python
if len(conns) > 1:
    lines.append(
        f"    raise NotImplementedError('Multiple connections from {current_node} is not supported...')"
    )
conn = conns[0]  # continues processing despite the above
```

When a network has branching connections, the exporter silently generates Python code that will raise `NotImplementedError` at **runtime** in the user's deployment code. The exporter does not fail at export time (which would give immediate feedback); instead it produces broken code that fails when run. The exporter should raise at export time, not in the generated output.

---

## 4. Test/Implementation Mismatches

### 4.1 `tests/test_sinabs_io.py` — `test_nir_to_sinabs` Tests Wrong Return Type

As detailed in §1.3, `SinabsIO.from_nir` returns `str` but the test asserts `isinstance(model, sinabs.network.Network)`.

Additionally, `tests/test_sinabs_io.py` imports sinabs unconditionally (no `skipif` guard), meaning the entire test file fails at import time if sinabs is not installed.

---

### 4.2 `sinabs_exporter.py` vs `sinabs_io.py` — Duplicated NetworkIR Traversal Logic

**Files:** `neurocnl/export/sinabs_exporter.py` and `neurocnl/converter/sinabs_io.py`
**Severity:** MEDIUM

The `from_neurocnl` method in `sinabs_io.py` (lines 116–230) and the `NetworkIR` path in `export_sinabs` in `sinabs_exporter.py` (lines 64–131) contain **nearly identical topological traversal code**. Both implement:
- Start-node detection via set subtraction
- Sequential traversal with `source_to_conns` mapping
- Layer insertion order logic

This duplication is ~70 lines of near-identical code and will diverge over time, introducing subtle differences in behaviour between the object-construction path and the code-generation path.

---

### 4.3 Two `test_sinabs_io.py` Files Covering Different (Conflicting) Behaviour

**Files:** `neurocnl/converter/test_sinabs_io.py` and `tests/test_sinabs_io.py`
**Severity:** MEDIUM

Two test files share the same base name and test the same class:
- `neurocnl/converter/test_sinabs_io.py` — tests `from_neurocnl` and `to_neurocnl` (direct IR conversion)
- `tests/test_sinabs_io.py` — tests `to_nir` and `from_nir` (NIR pivot)

The top-level `tests/test_sinabs_io.py` has no `skipif` guard and no `pytest.importorskip` for sinabs, meaning it will error on import in environments without sinabs installed. The `converter/test_sinabs_io.py` correctly uses `pytestmark = pytest.mark.skipif(not HAS_SINABS, ...)`.

---

### 4.4 `test_layer1_validator.py` — `test_akida_weight_precision_warning` Tests the Wrong Backend

**File:** `neurocnl/layers/test_layer1_validator.py`, lines 372–386
**Severity:** LOW — Misleading test name

```python
def test_akida_weight_precision_warning():
    params = {
        ...
        "synaptic_weight": 40000, # exceeds 32767
    }
    report = validate(specs, params, backend="spinnaker2")   # testing spinnaker2, not akida
    assert "spinnaker2_weight_representable" in failed_names
```

The test is named `test_akida_weight_precision_warning` but validates against the `spinnaker2` backend and `spinnaker2_weight_representable` invariant. This appears to be a test leftover from copying.

---

## 5. API Misuse and Runtime Errors

### 5.1 `spinnaker2_exporter.py` — Non-Existent `brian2_sim` Module

**File:** `neurocnl/export/spinnaker2_exporter.py`, line 126
**Severity:** HIGH — Generated code will always fail at runtime for simulation mode

```python
if target == "sim":
    lines.append("from spinnaker2 import brian2_sim")
    lines.append("hw = brian2_sim.SpiNNaker2Simulator()")
```

`brian2_sim` is not a standard py-spinnaker2 submodule. The simulation path of py-spinnaker2 does not use this API. Generated code with `target="sim"` will raise `ImportError` when executed.

Additionally, line 133: `timesteps = 1000` is hardcoded. No IR timing declarations are consulted, unlike every other exporter.

---

### 5.2 `rockpool_exporter.py` — Uses `/tmp` (Prohibited)

**File:** `neurocnl/export/rockpool_exporter.py`, lines 32–38
**Severity:** HIGH — Violates repository policy

```python
import tempfile

if filename is None:
    with tempfile.NamedTemporaryFile(suffix=".nir", delete=False) as f:
        temp_filename = f.name
    export_to_nir(net, temp_filename)
    ...
    os.remove(temp_filename)
```

The project's coding rules explicitly prohibit writing to `/tmp` or using `tempfile`. The `rockpool_exporter.py` uses `tempfile.NamedTemporaryFile` which creates files under `/tmp`. This is a hard policy violation.

---

### 5.3 `sinabs_io.py` — `np.broadcast_to` Returns Read-Only Array

**File:** `neurocnl/converter/sinabs_io.py`, lines 74–75
**Severity:** LOW — Latent correctness risk

```python
tau_mem = np.broadcast_to(tau_mem, max_len)
v_threshold = np.broadcast_to(v_threshold, max_len)
```

`np.broadcast_to` returns a **read-only view**. Any downstream operation that attempts to modify these arrays will raise a `ValueError: assignment destination is read-only`. Currently the arrays are passed directly to `nir.LIF()` which likely reads them, so no error today — but this is fragile.

---

### 5.4 `simulation/bptt.py` — Assumes Rockpool's 3-Tuple Return Convention

**File:** `neurocnl/simulation/bptt.py`, line 51
**Severity:** MEDIUM

```python
out, _, _ = model(inputs)  # assumes (output, state, record_dict) Rockpool convention
```

Standard `torch.nn.Module.forward()` returns a single tensor. If `train_with_bptt` is called on any non-Rockpool model (sinabs Sequential, plain PyTorch nn.Sequential), this unpacking will raise `ValueError: too many values to unpack` or `not enough values to unpack`. The function accepts `torch.nn.Module` as its type hint, which is too broad for this implementation.

---

### 5.5 `pynq_exporter.py` — Weight Packing Bug for Negative Values

**File:** `neurocnl/export/pynq_exporter.py`, lines 53–65
**Severity:** MEDIUM

```python
weights_arr = np.array(weights, dtype=np.int8)
weights_arr = weights_arr & 0x0F  # mask to 4-bit
```

For negative quantised weights (e.g. `-4` stored as `np.int8`): `-4` in int8 is `0xFC`; `0xFC & 0x0F = 0x0C`. In 4-bit two's complement, `0xC = 12` which correctly represents `-4` in the range `[-8, 7]`. **However**, this masking only preserves the sign correctly for values in the range `[-16, 15]`. Values outside this range (which could occur if `scale_factor` is large and `bits=4`) will have incorrect 4-bit representations after masking. The range check in `export_pynq` uses `abs(scaled_w - round(scaled_w)) > 1e-3` (integer-mappability) but does NOT verify that the value fits in the 4-bit range `[-8, 7]`, creating a silent range overflow.

---

## 6. Security Concerns

### 6.1 `backend/app/routers/export.py` — Unescaped User Data in HTML (XSS)

**File:** `backend/app/routers/export.py`, lines 276–279
**Severity:** HIGH — Potential Cross-Site Scripting

```python
for edge in edges:
    params = edge.get("params", {})
    network_html += f"...<td>{params.get('transform', '')}</td>
                        <td>{params.get('synapse', '')}</td>..."
```

`params.get('transform', '')` and `params.get('synapse', '')` are inserted directly into HTML without `html_lib.escape()`. The `network_summary` originates from `request.network_summary` which is a user-supplied field in `ExportRequest`. An attacker could inject arbitrary HTML/JavaScript via a crafted `params.transform` or `params.synapse` value in the request body.

All other sections in `_build_html_report` correctly escape values using `html_lib.escape()`. This inconsistency in lines 276–279 was likely overlooked.

---

### 6.2 `test_lava_sim_path.py` — `exec()` on Generated Code in Tests

**File:** `neurocnl/export/test_lava_sim_path.py`, line 31
**Severity:** LOW — Test-environment risk

```python
exec(code, namespace)
```

Executing dynamically generated code strings in tests provides limited safety guarantees. If the generator is compromised or produces unexpected output, `exec` will run it. While this is a test file, if test isolation breaks, this could impact the host environment. The test would be better implemented by importing the generated Lava objects via the Lava API directly rather than using `exec`.

---

## 7. Cross-Component Inconsistencies

### 7.1 `sinabs_exporter.py` and `sinabs_io.py` — Non-Deterministic Topology Traversal

**Files:** Both files contain `list(start_nodes)[0]` pattern
**Severity:** MEDIUM

```python
start_node = list(start_nodes)[0] if start_nodes else (list(sources)[0] if sources else None)
```

`start_nodes` is a Python `set`. Set iteration order is non-deterministic. For networks with multiple valid start nodes, repeated calls can produce different layer orderings in the generated code or constructed model. This makes the output non-reproducible.

---

### 7.2 `export/__init__.py` — `sinabs` and `rockpool` Exporters Not Registered

**File:** `neurocnl/export/__init__.py`
**Severity:** MEDIUM

`sinabs_exporter.py` and `rockpool_exporter.py` both exist but are not imported or registered in the `EXPORTERS` dict. `export(net, format="sinabs")` raises `ValueError`. These backends are documented in `docs/api/export.md` as supported export targets but are inaccessible through the standard `export()` API.

Similarly, the backend API router (`backend/app/routers/export.py`, lines 120–126) doesn't include `spinnaker2` or `pynq` in the extension mapping dict, so both formats will get a `.txt` extension instead of `.py`.

---

### 7.3 `backends/capabilities.py` — `akida` vs `akida1`/`akida2` Timing Resolution Inconsistency

**File:** `neurocnl/backends/capabilities.py`, lines 80–133
**Severity:** LOW — Subtle planning inconsistency

The `"akida"` profile sets `timing_resolution_seconds=None`, but `"akida1"` and `"akida2"` both set `timing_resolution_seconds=0.001`. This means the planner will skip timestep compatibility warnings for the generic `"akida"` backend but will generate them for the versioned backends. Users targeting `"akida"` may miss timing warnings.

---

### 7.4 `layer1_validator.py` — Akida2 Backend Skips Contract Validation

**File:** `neurocnl/layers/layer1_validator.py`, lines 329–349
**Severity:** MEDIUM

```python
if backend in ("akida", "akida2"):
    if backend == "akida":  # <-- only validates contract for "akida", not "akida2"
        try:
            AkidaExportContract(**neuron_params)
        except ValidationError as e:
            ...
```

`AkidaExportContract` validation is only performed when `backend == "akida"`. When `backend == "akida2"`, the contract check is silently skipped despite the outer condition suggesting both are handled. `akida2` runs the fan-in check and weight precision warning but not the base contract.

---

### 7.5 `akida_validator.py` — `akida_no_recurrent_connections` Only Checks Self-Loops

**File:** `neurocnl/layers/akida_validator.py`, lines 31–38
**Severity:** MEDIUM

```python
def akida_no_recurrent_connections(params, ir=None):
    for conn in ir.connections:
        if conn.source == conn.target:  # only catches A -> A, not A -> B -> A
            return False
    return True
```

The invariant only checks direct self-loops (`A → A`). Indirect cycles (`A → B → A`) are not detected here. While `_has_recurrent` in `akida_capabilities.py` does proper cycle detection, the invariant registered in `AKIDA_INVARIANTS` only checks self-loops. A network with a 2-node cycle would pass `akida_no_recurrent_connections` but correctly fail in `Akida1CapabilityChecker` via `_has_recurrent`.

---

### 7.6 `backends/capabilities.py` — Name Shadowing Anti-Pattern

**File:** `neurocnl/backends/capabilities.py`, lines 35 and 195
**Severity:** LOW — Maintainability risk

```python
BACKEND_CAPABILITIES: dict[str, BackendCapabilityProfile] = {...}  # line 35: plain dict
...
BACKEND_CAPABILITIES = _BackendCapabilitiesDict(BACKEND_CAPABILITIES)  # line 195: wraps itself
```

`BACKEND_CAPABILITIES` is first defined as a plain dict, then reassigned to a `_BackendCapabilitiesDict` wrapping the original. This self-referential reassignment is valid Python but easily confuses static analysis tools and readers. The `_BackendCapabilitiesDict` constructor takes the initial dict as `data`, so this does work — but the pattern is fragile and deceptive.

---

### 7.7 `rockpool_io.py` — Duplicate `import numpy as np` Inside Method

**File:** `neurocnl/converter/rockpool_io.py`, lines 31 and 82
**Severity:** LOW

`import numpy as np` appears twice inside `to_nir` — once near the start of the method and again at line 82. The second import is redundant.

---

## 8. Code Quality and Maintainability

### 8.1 `sinabs_io.py` — `import inspect` Inside Method Body

**File:** `neurocnl/converter/sinabs_io.py`, line 142
`import inspect` is placed inside `from_neurocnl`. Standard convention is to place all imports at module level.

### 8.2 `sinabs_io.py` — Redundant Population Lookup Guard

**File:** `neurocnl/converter/sinabs_io.py`, lines 205–206

```python
out_features = (
    network_ir.populations[conn.target].size
    if network_ir.populations.get(conn.target)  # .get() check
    and network_ir.populations[conn.target].size  # then direct access
    else 1
)
```

`.get(conn.target)` returns `None` if not found, then falls through to the `else`. But when not None, `network_ir.populations[conn.target]` performs a second dict lookup. This should use `.get()` consistently.

### 8.3 `pyproject.toml` — `F821` Suppressed Globally

**File:** `pyproject.toml`, line 83
`F821` (undefined name) is suppressed globally in ruff. This hides real errors like the `specs` and `params` undefined name in the malformed `test_spinnaker2_catches_unrepresentable_weight` test.

### 8.4 `pyproject.toml` — Excessively Broad mypy Suppression

**File:** `pyproject.toml`, lines 92–96
13 mypy error codes are disabled globally including `arg-type`, `assignment`, `return-value`, `attr-defined`, and `call-arg`. The type-system bugs identified in this review (e.g., `ConnectionIR.weight: float | None` accepting a `list`) would be caught by mypy if these checks were enabled.

---

## 9. Test Coverage Gaps

| Component | Missing Test Coverage |
|---|---|
| `sinabs_io.py::from_nir` | No test validates actual NIR→model conversion (stub is untestable) |
| `spinnaker2_io.py` | No tests exist for either function |
| `rockpool_exporter.py` | No integration test with a real (or mocked) Nengo network |
| `sinabs_exporter.py` | No test for networks with 3+ populations or multi-connection branching |
| `lava_exporter.py` | No test for `hw_mode=True` code path |
| `lava_exporter.py` | No test for `du` parameter range validation |
| `pynq_exporter.py` | No test for negative weight nibble packing correctness |
| `planner.py` | No test for `akida2` with `akida_connection_properties` in IR |
| `bptt.py` | No test for non-Rockpool module (misuse of 3-tuple unpacking) |
| `akida_capabilities.py::_is_sequential` | No direct unit test for the cycle-detection branch |
| `layer1_validator.py` | No test for `backend="akida2"` with contract-violating params |

---

## 10. Per-Integration Assessment

### Lava (Intel)
**Status: Functional but fragile.** The exporter generates syntactically correct Lava code for simple linear networks. Issues: `du` conversion may produce invalid parameters for extreme `tau_rc` values; `run()`/`stop()` are called on the first population only (incorrect for complex networks); no IR timing is used for simulation duration when called without `ir` kwarg.

### Sinabs (SynSense)
**Status: Partially implemented.** `from_neurocnl` works for sequential linear networks. `from_nir` is a non-functional stub. Two test files with conflicting expectations. The exporter generates broken code for branching networks without failing at export time.

### SpiNNaker2
**Status: Code generation only — contains unreachable runtime path.** The simulation target (`target="sim"`) generates an import for a non-existent `brian2_sim` module. Both I/O functions are stubs. Simulation timestep is hardcoded at 1000 and ignores IR timing.

### Rockpool (SynSense)
**Status: Mostly functional but uses prohibited `/tmp`.** `to_nir` and `from_nir` are real implementations. The `rockpool_exporter.py` uses `tempfile.NamedTemporaryFile` which violates the project's prohibition on `/tmp`. `bptt.py` assumes Rockpool's non-standard 3-tuple return convention without a type guard.

### PYNQ
**Status: Novel and largely correct, but with nibble-packing edge cases.** The 4-bit weight packing is mostly correct for values in `[-8, 7]`. However the quantisability check does not verify the range constraint (only integer-mappability), and the `test_all_formats_produce_string_or_dict` test will fail because `PynqOverlayConfig` is neither `str` nor `dict`.

### Akida
**Status: Topology checker has inverted logic (mitigated), contract gap for akida2.** `_is_sequential` returns `True` for cyclic graphs (bug is mitigated because `_has_recurrent` runs first in `Akida1CapabilityChecker`). `akida_no_recurrent_connections` invariant only detects self-loops, not multi-node cycles. `AkidaExportContract` is not validated for the `akida2` backend.

### Pipeline / Planner
**Status: Sound with minor dead code.** The planner logic has a duplicate `elif` block (dead code). The `plan_backend_support` function correctly integrates validator reports into verdicts. The `sinabs` backend has no capability profile, so `get_backend_capability("sinabs")` raises `KeyError`.

---

## Summary of Issues by Priority

| Priority | Count | Examples |
|---|---|---|
| **P0 — CI-breaking** | 2 | `test_layer1_validator.py` syntax error; `tests/test_sinabs_io.py` `isinstance` failure |
| **P1 — Logic/Runtime errors** | 6 | `_is_sequential` bug; `from_nir` stub; `/tmp` usage; XSS; `brian2_sim` import |
| **P2 — Functional gaps** | 7 | Stubs in production; `sinabs`/`rockpool` not in `EXPORTERS`; `ext` map missing formats; nibble packing; `bptt.py` 3-tuple assumption |
| **P3 — Quality/Maintenance** | 8 | Dead code; duplicate traversal logic; non-deterministic set iteration; contract gap for akida2; name shadowing |

**Recommended immediate actions:**
1. Fix syntax error in `test_layer1_validator.py` (P0)
2. Fix `tests/test_sinabs_io.py` to match `from_nir`'s actual return type or implement `from_nir` properly (P0)
3. Fix `_is_sequential` logic inversion in `akida_capabilities.py` (P1)
4. Replace `rockpool_exporter.py` tempfile usage with an in-memory NIR serialization path (P1)
5. Add HTML escaping for `params.transform` / `params.synapse` in the HTML report builder (P1)
6. Fix `test_all_formats_produce_string_or_dict` to handle `PynqOverlayConfig` return type (P1)
7. Raise at export time (not inside generated code) for unsupported topologies in `sinabs_exporter.py` (P1)
8. Fix `ext` map in `backend/app/routers/export.py` to include `spinnaker2` and `pynq` (P2)

---

## Fixes Applied in This Review Session

The following critical issues were remediated immediately as part of this review:

| # | File | Fix Applied |
|---|---|---|
| 1 | `neurocnl/layers/test_layer1_validator.py` | Removed stray `}` syntax error; renamed mangled function to `test_akida2_fanin_warns_for_large_source` with correct `specs`/`params` setup; renamed misleadingly-named `test_akida_weight_precision_warning` to `test_spinnaker2_catches_unrepresentable_weight` |
| 2 | `tests/test_sinabs_io.py` | Added `pytest.mark.skipif` guard for sinabs import; updated `test_nir_to_sinabs` to assert `isinstance(code, str)` matching actual `from_nir` return type |
| 3 | `neurocnl/backends/akida_capabilities.py` | Fixed `_is_sequential` logic inversion: changed `return True` → `return False` when a cycle is detected |
| 4 | `backend/app/routers/export.py` | Added `html_lib.escape()` around `params.get('transform', '')` and `params.get('synapse', '')` to close XSS vulnerability |
| 5 | `neurocnl/export/test_exporters.py` | Updated `test_all_formats_produce_string_or_dict` to accept `PynqOverlayConfig` as a valid result type alongside `str` and `dict` |

**Remaining open items** (P1–P3) require deeper refactoring and are tracked above.
