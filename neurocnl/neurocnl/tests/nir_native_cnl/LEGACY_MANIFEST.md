# Legacy Removal Manifest

**Captured:** 2026-05-19 (first run of `test_static_repo_invariants.py`)

This file inventories every Python source under `neurocnl/neurocnl/` and
`neurocnl/neurosim/` that contains either a Biological_Grammar keyword in
code or a Structured_DSL_Token form inside a string literal. It is the
input list for tasks 1.2 through 1.5 of the `nir-native-cnl` spec.

The scan excludes the test directory `neurocnl/neurocnl/tests/nir_native_cnl/`
(this directory) because tests there intentionally embed forbidden tokens
as test data.

**Total offending files: 29**

## Files containing Biological_Grammar keywords

These files reference `sensory`, `motor`, `MUST`, `MUST NOT`,
`threshold_firing`, `refractory_period`, or `STDP` as code identifiers
(not inside string literals). Per Requirement 8.6, each of these must
either be deleted (if the file's only purpose is the legacy biological
grammar) or rewritten to drop the legacy token (if the file has a wider
remit and the token is only one of several uses).

| File | Lines | Tokens |
|------|-------|--------|
| `neurocnl/neurocnl/cnl/document.py` | 254, 328, 341, 351 | `refractory_period` |
| `neurocnl/neurocnl/contracts/hardware_export.py` | 106, 125 | `refractory_period` |
| `neurocnl/neurocnl/contracts/neuron_params.py` | 15 | `refractory_period` |
| `neurocnl/neurocnl/export/test_exporters.py` | 22, 25, 28, 32, 41, 43-46 | `sensory`, `motor` |
| `neurocnl/neurocnl/export/test_nir_integration.py` | 280, 288 | `sensory` |
| `neurocnl/neurocnl/generation/nengo_generator.py` | 676, 678 | `sensory`, `motor` |
| `neurocnl/neurocnl/generation/test_nengo_generator.py` | 46-65, 169-170, 322, 342, 495-522 | `sensory`, `motor` |
| `neurocnl/neurocnl/ir/lowering.py` | 134, 150, 510 | `refractory_period` |
| `neurocnl/neurocnl/ir/materializer.py` | 548, 549 | `refractory_period` |
| `neurocnl/neurocnl/ir/test_ir_lowering.py` | 29, 180-185, 193-196 | `refractory_period`, `sensory` |
| `neurocnl/neurocnl/ir/test_materializer.py` | 53, 340, 343 | `refractory_period`, `sensory` |
| `neurocnl/neurocnl/ir/types.py` | 65 | `refractory_period` |
| `neurocnl/neurocnl/layers/layer1_invariants.py` | 33, 34, 36 | `refractory_period` |
| `neurocnl/neurocnl/layers/test_layer1_invariants.py` | 61, 65, 69 | `refractory_period` |
| `neurocnl/neurocnl/test_planner.py` | 179 | `refractory_period` |
| `neurocnl/neurocnl/tests/properties/test_physics_properties.py` | 211-215, 308-319, 419-426 | `refractory_period` |
| `neurocnl/neurocnl/tests/test_pipeline.py` | 205, 206, 207 | `sensory` |

## Files containing Structured_DSL_Token forms in string literals

These files embed the legacy structured-DSL surface (`Primitive "id"`
and/or `"a" -> "b"`) inside string literals (templates, docstrings,
demo CNL strings, test fixtures). Per Requirement 8.6, each must either
be deleted (if the file's only purpose is the legacy structured DSL) or
rewritten so the embedded CNL strings use the new natural-language
grammar (`Define <noun phrase> named <id> with ...`,
`Connect <src> to <target>.`).

| File | Lines | Notes |
|------|-------|-------|
| `neurocnl/neurocnl/nir_cnl/compiler.py` | 305, 313 | Structured-DSL examples in error-message strings or docstrings |
| `neurocnl/neurocnl/nir_cnl/ir_types.py` | 41 | Docstring example |
| `neurocnl/neurocnl/nir_cnl/parser.py` | 306 | Docstring/error-message example |
| `neurocnl/neurocnl/tests/properties/test_nir_native_cnl_properties.py` | 586-590, 688-692, 728-733 | Property-test inputs in structured DSL |
| `neurocnl/neurocnl/tests/test_compile_nir_native.py` | 1, 29, 37, 47 | Pins structured-DSL surface |
| `neurocnl/neurocnl/tests/test_compiler.py` | 53 | Pins structured-DSL surface |
| `neurocnl/neurocnl/tests/test_grammar.py` | 1, 117, 118, 126, 135, 162, 179, 185 | Grammar regex tests pin structured DSL |
| `neurocnl/neurocnl/tests/test_nir_native_cnl.py` | 1, 49, 433-436 | Pins structured-DSL surface |
| `neurocnl/neurocnl/tests/test_nir_native_cnl_integration.py` | 84 | Pins structured-DSL surface |
| `neurocnl/neurocnl/tests/test_parser.py` | 27, 62, 76, 87, 101, 111, 119, 129, 160, 172, 182, 195, 207, 245, 267, 278, 286 | Parser tests pin structured DSL |
| `neurocnl/neurocnl/tests/test_pipeline_entry_points.py` | 82 | Pipeline entry-point test pins structured DSL |
| `neurocnl/neurocnl/tests/test_renderer.py` | 67, 74, 83, 95, 108, 122, 136, 143, 151, 160, 167, 183, 202, 219, 231, 239, 246, 252, 451 | Renderer snapshot tests pin structured-DSL output |

## Notes on cross-cutting concerns

- `refractory_period` appears in `contracts/`, `ir/`, `layers/`,
  `cnl/document.py`, and `test_planner.py` as a *neuron parameter
  identifier* on the biological-grammar path; tasks 1.3 and 1.4 will
  decide which of these are pure-legacy (delete) vs cross-cutting
  (refactor to remove the biological-grammar dependency).
- `neurocnl/neurosim/` produced no offending files in this scan. If
  templates or manifests under `neurosim/` carry the legacy grammar in
  non-`.py` files (`.json`, `.yaml`, `.cnl`, `.md`), task 1.5 still
  needs to sweep those — this scan is `.py` only.
- The test directory `neurocnl/neurocnl/tests/nir_native_cnl/` is
  intentionally *excluded* from the scan and from this manifest. New
  tests for the NIR-Native CNL feature live there and will contain
  forbidden tokens as test data.

## Re-running the scan

```bash
cd neurocnl
PYTHONPATH=. .venv/bin/python -m pytest \
    neurocnl/tests/nir_native_cnl/test_static_repo_invariants.py -q
```

Task 1.5 expects this test to pass (zero offending files) once tasks
1.2-1.4 have completed.
