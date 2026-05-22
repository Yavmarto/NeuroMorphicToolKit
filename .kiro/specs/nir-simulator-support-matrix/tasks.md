# Implementation Plan: NIR Simulator Support Matrix

## Overview

Expand `_BACKEND_NIR_SUPPORT` in `nir_support.py` to cover all 17 NIR primitives
explicitly per backend, extend `SnnTorchSimulatorAdapter._simulate()` with five new
node-type branches, add an early-rejection guard to `LavaSimulatorAdapter._run_in_process()`,
and update tests and documentation accordingly.

Following the bug-condition methodology: exploration and property tests are written
**first** (against unfixed code), implementation follows in Wave 2, verification re-runs
those same tests in Wave 3, and Hypothesis PBT plus docs land in Wave 4.

---

## Tasks

- [x] 1. Write exploration tests (Wave 1 — run against UNFIXED code to confirm failures)
  - [x] 1.1 Write `COMPLETE_PRIMITIVE_SET` constant and parametrized `EXPECTED_VERDICTS` verdict table in `test_nir_support.py`
    - Add `COMPLETE_PRIMITIVE_SET` frozenset (18 entries: `Input`, `Output`, `Linear`, `Affine`, `Conv2d`, `Flatten`, `IF`, `LIF`, `CubaLIF`, `LI`, `AvgPool2d`, `SumPool2d`, `Delay`, `Scale`, `Threshold`, `Sigmoid`, `I`, `CubaLI`) at module scope in `neurocnl/neurocnl/runtime/test_nir_support.py`
    - Add `EXPECTED_VERDICTS` dict with the full lava_sim and snntorch_sim sub-dicts as specified in the design (e.g. `snntorch_sim["Affine"] == "exact"`, `lava_sim["Affine"] == "unsupported"`, etc.)
    - Add parametrized test `test_verdict_for_primitive(backend, primitive, expected)` that calls `get_supported_node_types(backend)` and asserts `table.get(primitive) == expected`
    - Run with `PYTHONPATH=. pytest neurocnl/neurocnl/runtime/test_nir_support.py::test_verdict_for_primitive -v` — the 5 snnTorch new-type rows (`Affine`, `Conv2d`, `Flatten`, `IF`, `AvgPool2d`) MUST fail before implementation
    - _Requirements: 1.1, 1.2, 6.1_

  - [x] 1.2 Write no-fallthrough structural test in `test_nir_support.py`
    - Add `test_no_fallthrough_all_primitives()` that loops over both backends and asserts every member of `COMPLETE_PRIMITIVE_SET` is an explicit key in `get_supported_node_types(backend)` (i.e. present in the dict, not just reachable via `.get()` default)
    - Run against UNFIXED code — MUST fail because the current table has only 6 entries and 12 primitives are absent
    - _Requirements: 1.1, 1.2, 6.2_

  - [x] 1.3 Create `test_snntorch_simulator_primitives.py` with 5 no-skip-warning tests
    - Create new file `neurocnl/neurocnl/runtime/test_snntorch_simulator_primitives.py`
    - Add `_make_graph_with_node(name, node, in_size)` helper that wraps a single node in `Input → node → LIF → Output` topology
    - Add `_make_minimal_stimulus(graph, timesteps)` helper producing a `ValidatedStimulus` with one spike at t=0 on neuron 0
    - Add `NEW_SNNTORCH_NODES` dict of lambdas for `Affine`, `Conv2d`, `Flatten`, `IF`, `AvgPool2d` (exact constructors from design doc §"File 2")
    - Add `test_new_node_type_no_skip_warning(node_type_name)` parametrized over all 5 types — uses `pytest.importorskip("torch")` and `pytest.importorskip("snntorch")`, calls `SnnTorchSimulatorAdapter().run(...)`, asserts no warning contains `"not supported"` or `"skipped"`
    - Add `test_new_node_type_not_classified_as_unsupported(node_type_name)` that asserts `classify_nir_graph(graph, "snntorch_sim").level != "unsupported"` for each new type
    - Run against UNFIXED code — `test_new_node_type_no_skip_warning` MUST fail (adapter falls through to `else:` skip-warning branch), `test_new_node_type_not_classified_as_unsupported` MUST fail (current table lacks entries)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 6.3, 6.4_

  - [x] 1.4 Write Lava early-rejection test in `test_snntorch_simulator_primitives.py`
    - Add `test_lava_early_rejection_names_unsupported_types()` — builds a graph containing `nir.Conv2d`, calls `LavaSimulatorAdapter()._run_in_process(graph, timesteps=5, seed=0)`, asserts `LavaDispatchError` is raised and `"Conv2d"` appears in the error message
    - Use `pytest.importorskip("lava")` to skip gracefully when lava-nc is not installed
    - Run against UNFIXED code — MUST fail because no guard exists yet and `_run_in_process` will not raise the expected error before entering the Lava process-construction path
    - _Requirements: 3.3, 6.5_

- [x] 2. Core implementation (Wave 2 — apply the fixes)
  - [x] 2.1 Expand `_BACKEND_NIR_SUPPORT` in `nir_support.py` to all 17 primitives per backend
    - File: `neurocnl/neurocnl/runtime/nir_support.py`
    - Replace the existing 6-entry `_BACKEND_NIR_SUPPORT` dict with the full 17-entry version specified in design §"Expanded `_BACKEND_NIR_SUPPORT` dict" (both `lava_sim` and `snntorch_sim` sub-dicts with inline comments)
    - Add `COMPLETE_PRIMITIVE_SET: frozenset[str]` constant at module level (18 members matching design §"Data Models") and export it from the module
    - Verify `get_supported_node_types("snntorch_sim")` now returns 17 entries including `"Affine": "exact"`, `"IF": "exact"`, `"AvgPool2d": "exact"`
    - Verify `get_supported_node_types("lava_sim")` now returns 17 entries including `"Affine": "unsupported"`, `"Conv2d": "unsupported"` with inline comments
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 3.1, 3.2, 3.4, 3.5_

  - [x] 2.2 Add 5 new `elif` branches to `SnnTorchSimulatorAdapter._simulate()` in `snntorch_simulator.py`
    - File: `neurocnl/neurocnl/runtime/snntorch_simulator.py`
    - In the module-building loop (`for name in topo_order:`), insert 5 new `elif` branches **after** the existing `elif isinstance(node, nir.Delay):` block and **before** the final `else:` catch-all, exactly as specified in design §"snnTorch Adapter Extensions":
      - `elif isinstance(node, nir.Affine):` — construct `nn.Linear(in_features, out_features, bias=True)`, copy weight and bias tensors with `torch.no_grad()`, set `requires_grad_(False)`, assign `modules[name]`
      - `elif isinstance(node, nir.Conv2d):` — extract weight shape `(out_ch, in_ch, kH, kW)`, handle `node.stride` and `node.padding` as int-or-array, construct `nn.Conv2d`, copy weight, set `requires_grad_(False)`, assign `modules[name]`
      - `elif isinstance(node, nir.Flatten):` — construct `nn.Flatten(start_dim=getattr(node,"start_dim",1), end_dim=getattr(node,"end_dim",-1))`, assign `modules[name]`
      - `elif isinstance(node, nir.IF):` — compute `r = float(np.mean(np.asarray(node.r)))`, `threshold = _lif_threshold(node)`, construct `snntorch.Lapicque(R=r, C=1e6, time_step=1.0, threshold=threshold)`, assign `modules[name]`, append `name` to `lif_node_names`
      - `elif isinstance(node, nir.AvgPool2d):` — use `getattr(node, "pool_size", None) or getattr(node, "sumpool_size", None)` for kernel; if neither found raise `SnnTorchDispatchError`; extract stride via `getattr(node, "stride", None)`; construct `nn.AvgPool2d(kernel_size, stride)`, assign `modules[name]`
    - In the timestep loop's dispatch section, add two new dispatch branches after the existing `elif isinstance(node, nir.Delay):` branch:
      - `elif isinstance(node, (nir.Affine, nir.Conv2d, nir.Flatten, nir.AvgPool2d)):` — `outputs[name] = modules[name](x)` (stateless forward pass)
      - Extend the existing `elif isinstance(node, (nir.LIF, nir.CubaLIF)):` condition to also include `nir.IF` so IF nodes participate in the same spike/mem recording branch
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [x] 2.3 Add Lava pre-execution guard in `LavaSimulatorAdapter._run_in_process()`
    - File: `neurocnl/neurocnl/runtime/lava_simulator.py`
    - Add module-level constant `_LAVA_NC_SUPPORTED_TYPES: frozenset[str] = frozenset({"Input", "Output", "LIF", "CubaLIF", "Linear", "Delay"})` near the top of the file after imports
    - Insert the guard block as the **first action** inside `_run_in_process`, immediately after the `_import_lava()` call and before `np.random.seed(seed)`:
      ```python
      unsupported_in_graph = [
          f"nir.{type(node).__name__} (node '{name}')"
          for name, node in graph.nodes.items()
          if type(node).__name__ not in _LAVA_NC_SUPPORTED_TYPES
      ]
      if unsupported_in_graph:
          raise LavaDispatchError(
              "The lava-nc adapter cannot execute this NIR graph. "
              "The following node types are not supported by lava-nc processes: "
              + ", ".join(unsupported_in_graph)
              + ". Note: some of these types are supported by lava-dl (netx), "
              "which is outside the scope of lava_sim. "
              "Use snntorch_sim for graphs containing these node types."
          )
      ```
    - The guard must fire before any Lava `LIF`, `Dense`, or `Monitor` process is constructed
    - _Requirements: 3.3_

- [x] 3. Verification — re-run exploration tests (Wave 3 — all should now pass)
  - [x] 3.1 Re-run all verdict tests from task 1.1
    - Run `PYTHONPATH=. pytest neurocnl/neurocnl/runtime/test_nir_support.py::test_verdict_for_primitive -v`
    - All parametrized cases including the 5 previously-failing snnTorch new-type rows MUST now pass
    - _Requirements: 1.1, 1.2, 6.1_

  - [x] 3.2 Re-run no-fallthrough test from task 1.2
    - Run `PYTHONPATH=. pytest neurocnl/neurocnl/runtime/test_nir_support.py::test_no_fallthrough_all_primitives -v`
    - MUST pass — every member of `COMPLETE_PRIMITIVE_SET` is now an explicit key in both backend tables
    - _Requirements: 1.1, 1.2, 6.2_

  - [x] 3.3 Re-run snnTorch adapter tests from task 1.3
    - Run `PYTHONPATH=. pytest neurocnl/neurocnl/runtime/test_snntorch_simulator_primitives.py -v -k "no_skip_warning or not_classified"`
    - All 5 `test_new_node_type_no_skip_warning` cases and all 5 `test_new_node_type_not_classified_as_unsupported` cases MUST pass
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.7, 6.3, 6.4_

  - [x] 3.4 Re-run Lava early-rejection test from task 1.4
    - Run `PYTHONPATH=. pytest neurocnl/neurocnl/runtime/test_snntorch_simulator_primitives.py::test_lava_early_rejection_names_unsupported_types -v`
    - MUST pass — guard raises `LavaDispatchError` naming `Conv2d` before any Lava process construction
    - _Requirements: 3.3, 6.5_

- [x] 4. Hypothesis PBT and documentation (Wave 4)
  - [x] 4.1 Add Hypothesis property tests (Properties 2–5, 7, 8) to `test_nir_support.py` and `test_snntorch_simulator_primitives.py`
    - File: `neurocnl/neurocnl/runtime/test_nir_support.py`
    - Add `_build_minimal_graph_from_types(node_types)` helper that constructs a `nir.NIRGraph` containing exactly the requested node type names, bridged between `nir.Input` and `nir.Output`
    - **Property 2** (`test_exact_only_graph_classifies_exact`): `@given(node_types=st.lists(st.sampled_from(all_exact_snn), min_size=2, max_size=6, unique=True))` — build graph, call `classify_nir_graph(graph, "snntorch_sim")`, assert `result.level == "exact"` and both unsupported/approximate lists are empty; `@settings(max_examples=100)`; tag comment `# Feature: nir-simulator-support-matrix, Property 2`; **Validates: Requirements 5.1**
    - **Property 3** (`test_approximate_present_graph_classifies_approximate`): `@given(node_types=st.lists(st.sampled_from([p for p,v in EXPECTED_VERDICTS["snntorch_sim"].items() if v=="approximate"]), min_size=1, max_size=2, unique=True))` combined with exact-only extras — assert `result.level == "approximate"`; **Validates: Requirements 5.2**
    - **Property 4** (`test_unsupported_present_graph_classifies_unsupported`): `@given(node_types=st.lists(st.sampled_from([p for p,v in EXPECTED_VERDICTS["snntorch_sim"].items() if v=="unsupported"]), min_size=1, max_size=4, unique=True))` — assert `result.level == "unsupported"` and `result.diagnostics` is non-empty; **Validates: Requirements 5.3, 5.6**
    - **Property 5** (`test_unsupported_nodes_all_named_in_diagnostics`): generate graphs from unsupported node types, assert every entry in `result.unsupported_nodes` appears as a substring in at least one `result.diagnostics` entry; **Validates: Requirements 5.4, 5.6**
    - **Property 7** (`test_capabilities_lists_partition_complete_primitive_set`): for both backends call `get_supported_node_types(backend)` and assert the union of keys with value "exact", "approximate", and "unsupported" equals `COMPLETE_PRIMITIVE_SET`; **Validates: Requirements 4.1, 4.2, 4.3, 4.4**
    - File: `neurocnl/neurocnl/runtime/test_snntorch_simulator_primitives.py`
    - **Property 8** (`test_lava_early_rejection_any_unsupported_type`): `@given(unsupported_types=st.lists(st.sampled_from(LAVA_UNSUPPORTED), min_size=1, max_size=3, unique=True))` — build a minimal graph containing the first unsupported type, assert `LavaDispatchError` is raised and the type name appears in the error message; `pytest.importorskip("lava")`; `@settings(max_examples=50)`; **Validates: Requirements 3.3**
    - _Requirements: 1.2, 3.3, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 5.4, 5.6, 6.1, 6.2_

  - [x] 4.2 Update `docs/support_matrix.md` with NIR Simulator Support Matrix section
    - File: `neurocnl/docs/support_matrix.md`
    - Insert a new `## NIR Simulator Support Matrix` H2 section immediately after the existing `## NIR Fidelity Subset` section and before `## Training Support`
    - The section must contain (per design §"Documentation update plan"):
      1. A `### lava-nc vs lava-dl distinction` subsection explaining that `lava_sim` uses `lava-nc` (not `lava-dl/netx`) and why certain primitives are `unsupported` in `lava_sim` despite appearing in the official NIR support matrix
      2. A `### Fidelity terms` subsection (exact/approximate/unsupported definitions)
      3. A `### lava_sim (lava-nc) support verdicts` markdown table with all 17 primitives and their verdicts and notes
      4. A `### snntorch_sim (snnTorch) support verdicts` markdown table with all 17 primitives and their verdicts and notes
      5. A `### Promotability` note listing which lava-nc `unsupported` primitives (`Conv2d`, `Flatten`, `Affine`) could be promoted if lava-dl netx integration were added
    - This file MUST be updated in the same change as `nir_support.py` per `neurocnl/AGENTS.md` constraint
    - _Requirements: 7.1, 7.2, 7.3_

- [x] 5. Final checkpoint
  - Ensure all tests pass, run the full suite and linters, ask the user if questions arise.
  - Run `PYTHONPATH=. pytest neurocnl/tests/ neurocnl/neurocnl/runtime/test_nir_support.py neurocnl/neurocnl/runtime/test_snntorch_simulator_primitives.py -v`
  - Run `ruff check .` — must exit 0
  - Run `mypy .` — must exit 0 (or pre-existing mypy errors only; no new type errors from this change)
  - _Requirements: 1.1–1.6, 2.1–2.7, 3.1–3.5, 4.1–4.5, 5.1–5.6, 6.1–6.5, 7.1–7.3_

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- The bug-condition ordering is deliberate: Wave 1 tests are written first and run against unfixed code to confirm they catch the bugs; implementation follows in Wave 2; Wave 3 re-runs the same tests to verify the fixes; Wave 4 adds PBT depth and docs
- The `COMPLETE_PRIMITIVE_SET` constant is defined in both `nir_support.py` (production) and `test_nir_support.py` (tests); the test copy is intentionally redundant so tests remain self-contained
- `nir.I` (Integrator) and `nir.CubaLI` are included in `COMPLETE_PRIMITIVE_SET` alongside `nir.Sigmoid`; `nir.Tanh` is excluded as it is not an official NIR primitive class in the installed `nir` package — verify against `nir.__all__` if in doubt
- The `snntorch.Lapicque` constructor signature (`R`, `C`, `time_step`, `threshold`) must match the installed snnTorch version; if the version pre-dates Lapicque, fall back to `snntorch.Leaky(beta=0.999, threshold=threshold)` and emit an approximation warning
- Lava early-rejection tests use `pytest.importorskip("lava")` so the test is silently skipped when `lava-nc` is not installed in CI — this is correct behaviour; the guard itself is always compiled in regardless of lava availability
- Checkpoints ensure incremental validation
- Each task references specific requirements for traceability

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "1.4"] },
    { "id": 1, "tasks": ["2.1", "2.2", "2.3"] },
    { "id": 2, "tasks": ["3.1", "3.2", "3.3", "3.4"] },
    { "id": 3, "tasks": ["4.1", "4.2"] }
  ]
}
```
