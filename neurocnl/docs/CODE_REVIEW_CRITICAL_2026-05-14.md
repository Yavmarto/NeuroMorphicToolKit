# Critical Code Review — NeuroCNL

**Date:** 2026-05-14
**Scope:** `neurocnl` Python library, FastAPI backend wrappers, CNL/IR/NIR path, backend capability claims, and focused regression tests.
**Reviewer:** Codex
**Bottom line:** The direct `CNL -> IR -> NIR` compiler is in much better shape than the older Nengo-era surface, but the module as a whole does **not** currently hold up as a coherent product contract. The biggest risk is not a single broken algorithm; it is contract drift between parser, canonical document rendering, REST validation/generation, support matrix, capability registry, and checked-in tests.

## Executive Verdict

NeuroCNL has a credible core: `neurocnl.compile.compile_to_nir()` is structured, fail-closed, and has focused tests that passed in this review. The NIR materializer also has explicit lowering summaries and handles advisory metadata honestly.

However, the implementation around that core is inconsistent enough that I would not treat the current `neurocnl` module as beta-stable. Existing checked-in tests fail in multiple areas, `/api/validate` can return green for specs that cannot lower, `/api/generate` emits CNL that cannot round-trip through the project’s own compiler, and the public/backend capability story still simultaneously says “Nengo removed” and “Nengo primary execution backend.”

## Implementation Plan

This plan assumes the current product boundary remains `CNL -> IR -> NIR`, with Nengo and runtime-specific execution paths treated as legacy or out of active scope unless explicitly re-approved. The goal is to restore one executable truth across parser, IR lowering, NIR materialization, REST endpoints, public Python API, docs, and tests.

### Phase 1 — Make validation and generation fail closed together

**Priority:** P0
**Goal:** A spec that cannot lower/materialize must never receive a green validation result, and generation must never crash with an unhandled lowering/materializer exception.

**Implementation steps:**

1. In `backend/app/services/neurocnl_bridge.py`, stop swallowing `LoweringError` when the request is validating the active NIR-backed workflow.
2. Convert lowering failures into the same structured diagnostic shape already used for parse/validation errors: `code`, `message`, `hint`, `line`, `raw`, and stage information when available.
3. In `backend/app/routers/generate.py`, catch `LoweringError` and `MaterializerError` alongside parse/value failures and return `422` with structured diagnostics.
4. Add regression coverage for conflicting declarations such as two incompatible sizes for the same population.
5. Confirm `/api/validate` and `/api/generate` agree on invalidity for the same malformed-but-parseable spec.

**Key files:**

- `backend/app/services/neurocnl_bridge.py`
- `backend/app/routers/validate.py`
- `backend/app/routers/generate.py`
- `neurocnl/pipeline.py`
- `backend/tests/test_validate_router.py`
- `backend/tests/test_generate_router.py`

**Exit criteria:**

- `/api/validate` returns `overall: false` or an equivalent structured failure for specs that fail IR lowering.
- `/api/generate` returns a structured `422`, not an exception traceback, for the same specs.
- Backend generate/validate tests pass.

### Phase 2 — Make canonical CNL parser-compatible

**Priority:** P0
**Goal:** NeuroCNL must not emit visible canonical CNL that its own parser rejects.

**Implementation steps:**

1. Inventory every sentence shape emitted by `emit_canonical_cnl()` and `render_cnl_document()`.
2. For each emitted sentence, choose one of two fixes:
   - Change the emitted text to an already-supported grammar form.
   - Extend `parse_spec_text()`/the CNL parser to support the emitted canonical form.
3. Fix the known broken inhibitory line shape currently emitted as `The hidden MUST inhibit output`.
4. Fix the known broken STDP line shape currently emitted as `The connection from hidden to output MUST exhibit STDP WITH ...`.
5. Add a parser-focused test that renders canonical CNL from a representative IR and immediately parses every visible generated sentence.
6. Keep embedded IR metadata as a fidelity aid, not as an excuse for invalid visible grammar.

**Key files:**

- `neurocnl/cnl/document.py`
- `neurocnl/cnl/cnl_parser.py`
- `neurocnl/cnl/test_cnl_parser.py`
- `backend/tests/test_generate_router.py`

**Exit criteria:**

- `test_generate_roundtrip_cnl_recompiles_to_nir` passes.
- Generated CNL containing inhibitory and STDP semantics parses successfully.
- Any future emitted canonical sentence must have a parser regression test.

### Phase 3 — Resolve the NIR-only vs legacy-Nengo contract

**Priority:** P1
**Goal:** Docs, public API, backend API, capability registry, and tests must describe the same support boundary.

**Implementation steps:**

1. Confirm the product decision: active support is `CNL -> IR -> NIR`; Nengo generation/export is legacy unless explicitly restored.
2. Update `docs/support_matrix.md` so the active and legacy surfaces are named unambiguously.
3. Update `neurocnl/__init__.py` package documentation and exports so direct NIR APIs are primary and legacy APIs are either clearly labeled or removed from the top-level surface.
4. Update `neurocnl/export/__init__.py` so docstrings and exported names do not imply active Nengo-based export support.
5. Update `neurocnl/backends/capabilities.py` so `nengo` is not simultaneously “unsupported” in docs and “Primary execution backend” in planner data.
6. Update `backend/app/routers/export.py` and export-router tests so legacy formats intentionally return `410 Gone` if they remain disabled.
7. Add a compact compatibility note for downstream modules explaining which path is supported and which imports are legacy.

**Key files:**

- `docs/support_matrix.md`
- `neurocnl/__init__.py`
- `neurocnl/export/__init__.py`
- `neurocnl/backends/capabilities.py`
- `backend/app/routers/export.py`
- `backend/tests/test_export_router.py`

**Exit criteria:**

- A maintainer can identify the supported compiler/export path from docs, package imports, planner output, and REST behavior without contradiction.
- Export-router tests assert the intended `410` behavior for disabled legacy formats or the restored supported behavior if legacy support is deliberately reintroduced.

### Phase 4 — Sync regression tests with the intended contracts

**Priority:** P1
**Goal:** The focused NeuroCNL test suite should become a trustworthy release gate again.

**Implementation steps:**

1. Update IR lowering/materializer tests to reflect the intended normalized identifier contract, such as `"sensory"` instead of `"sensory neuron"` when that is the stable semantic key.
2. Add a short doc note describing stable population identifier normalization rules for downstream modules.
3. Update backend export tests whose mocks target removed symbols or stale legacy exporter paths.
4. Keep tests that reveal real regressions, especially the generated-CNL round-trip failure, and fix implementation rather than deleting coverage.
5. Run focused suites after each contract area is updated rather than waiting for one large final test run.

**Key files:**

- `neurocnl/ir/test_ir_lowering.py`
- `neurocnl/ir/test_materializer.py`
- `neurocnl/cnl/test_cnl_parser.py`
- `backend/tests/test_export_router.py`
- `backend/tests/test_generate_router.py`
- `docs/support_matrix.md` or a small companion contract note

**Exit criteria:**

- Parser, IR lowering, materializer, backend generate/validate/export, and planner/capability tests encode one current contract.
- Test failures no longer mix stale historical expectations with real implementation defects.

### Phase 5 — Align Akida1 topology semantics without expanding hardware scope

**Priority:** P1
**Goal:** Akida1 support claims must be internally consistent, but this work should not become a broad hardware-deployment project.

**Implementation steps:**

1. Decide whether sequential Akida1 topology is currently supported, approximate, or unsupported in the active NeuroCNL planner.
2. If unsupported, update docs/tests to make the rejection explicit and remove the expectation that sequential topology is faithful.
3. If supported, update `BACKEND_CAPABILITIES["akida1"]` and planner logic so a valid sequential graph returns the expected support level.
4. Keep non-sequential, recurrent, or unsupported Akida1 cases fail-closed.

**Key files:**

- `neurocnl/backends/capabilities.py`
- `neurocnl/planner.py`
- `neurocnl/test_planner.py`
- `docs/support_matrix.md`

**Exit criteria:**

- Akida1 docs, capability data, planner output, and tests agree.
- No new hardware deployment work is introduced beyond correcting the support contract.

### Phase 6 — Unify or rename the duplicate `compile_to_nir()` APIs

**Priority:** P1
**Goal:** Avoid two different APIs with the same name but different signatures, return types, and error behavior.

**Implementation steps:**

1. Rename the older `neurocnl.pipeline.compile_to_nir()` helper to a name that reflects its actual legacy/IR-document role, or convert it into a compatibility wrapper around `neurocnl.compile.compile_to_nir()`.
2. Update backend imports to use the structured public compiler where possible.
3. Preserve compatibility only where there is an explicit downstream need, and mark it deprecated in docstrings/tests.
4. Ensure errors from backend export and generation paths use the structured `CompileError`/diagnostic model rather than plain `ValueError` where possible.

**Key files:**

- `neurocnl/pipeline.py`
- `neurocnl/compile.py`
- `neurocnl/__init__.py`
- `backend/app/routers/export.py`
- Compiler/export tests

**Exit criteria:**

- There is one primary public `compile_to_nir()` contract.
- Any legacy helper has a distinct name or explicit deprecation path.
- Backend code no longer accidentally imports the weaker/older API.

### Phase 7 — Harden report provenance and production defaults

**Priority:** P2
**Goal:** Keep local development easy while making official-looking artifacts and non-local backend exposure safer.

**Implementation steps:**

1. In HTML report export, recompute validation/backend support server-side where practical.
2. If client-supplied summaries remain accepted, label them as client-provided and include server-side validation status separately.
3. Add generated-at timestamp, NeuroCNL version, validation status, and source/provenance metadata to report exports.
4. Add a production/non-loopback configuration mode that requires explicit CORS origins and auth configuration.
5. Keep localhost launcher defaults developer-friendly.

**Key files:**

- `backend/app/routers/export.py`
- `backend/app/main.py`
- `backend/app/middleware/auth.py`
- `backend/tests/test_cors_config.py`
- Report/export tests

**Exit criteria:**

- HTML reports cannot silently present caller-provided claims as server-verified facts.
- Non-local production exposure fails closed unless auth and CORS are explicitly configured.

### Final Verification Gate

Run the following focused gate after Phases 1-7, using the project-approved wrapper/environment:

```bash
rtk python -m pytest backend/tests/test_generate_router.py backend/tests/test_validate_router.py -q
rtk python -m pytest backend/tests/test_export_router.py -q
rtk python -m pytest neurocnl/cnl/test_cnl_parser.py neurocnl/ir/test_ir_lowering.py neurocnl/ir/test_materializer.py -q
rtk python -m pytest neurocnl/test_planner.py neurocnl/backends/test_capabilities.py -q
rtk python -m pytest neurocnl/tests/test_compile.py neurocnl/export/test_nir_integration.py neurocnl/tests/test_nir_to_cnl.py -q
rtk ruff check backend/app/routers/generate.py backend/app/routers/export.py backend/app/services/neurocnl_bridge.py neurocnl/pipeline.py neurocnl/compile.py neurocnl/ir/lowering.py neurocnl/ir/materializer.py
```

If the implementation changes suite-visible CNL behavior, also run the root integration checks required by the repo instructions:

```bash
rtk python3 -m pytest tests/integration/test_cross_module.py
rtk python3 -m pytest tests/integration/test_teensy_e2e.py
```

## Verification Performed

Commands run from `/NeuroMorphicToolKit/neurocnl` unless noted otherwise:

- `python -m pytest backend/tests/test_generate_router.py backend/tests/test_validate_router.py -q`
  - Result: **1 failed, 11 passed**
  - Failure: `test_generate_roundtrip_cnl_recompiles_to_nir`
- `python -m pytest backend/tests/test_export_router.py -q`
  - Result: **11 failed, 13 passed**
  - Failures are mostly stale legacy-export expectations, plus one NIR/lateral-inhibition contract mismatch.
- `python -m pytest neurocnl/tests/test_compile.py neurocnl/export/test_nir_integration.py neurocnl/tests/test_nir_to_cnl.py -q`
  - Result: **65 passed**
- `python -m pytest neurocnl/test_planner.py neurocnl/backends/test_capabilities.py -q`
  - Result: **1 failed, 33 passed**
  - Failure: Akida1 sequential topology expected faithful but planner returned unsupported.
- `python -m pytest neurocnl/cnl/test_cnl_parser.py neurocnl/ir/test_ir_lowering.py neurocnl/ir/test_materializer.py -q`
  - Result: **12 failed, 165 passed**
  - Failures are all stale/current-contract conflicts around normalized population identifiers.
- `ruff check backend/app/routers/generate.py backend/app/routers/export.py backend/app/services/neurocnl_bridge.py neurocnl/pipeline.py neurocnl/compile.py neurocnl/ir/lowering.py neurocnl/ir/materializer.py --output-format full`
  - Result: **1 failure**
  - `backend/app/routers/generate.py` import block is unsorted.
- `uv run ...` could not be used reliably because the project attempted to fetch `py-spinnaker2` and failed on a private SSH submodule.

## Findings

### P0 — `/api/generate` emits a “round-trip” CNL document that does not compile back to NIR

**Evidence:** [neurocnl/neurocnl/cnl/document.py:136](../neurocnl/cnl/document.py) emits grammar-visible connection lines, including inhibitory and STDP forms at [line 158](../neurocnl/cnl/document.py) and [line 180](../neurocnl/cnl/document.py). The checked-in round-trip test at [backend/tests/test_generate_router.py:76](../backend/tests/test_generate_router.py) currently fails.

Reproduced generated grammar excerpt:

```text
The hidden MUST inhibit output
The connection from hidden to output MUST exhibit STDP WITH learning rate of 0.05 and window of 0 ms
```

`parse_spec_text()` rejects both lines:

```text
The hidden MUST inhibit output -> unsupported_sentence_family
The connection from hidden to output MUST exhibit STDP ... -> malformed_connection_syntax
```

This directly breaks the `NIR -> CNL -> NIR` story in the support matrix, which claims round-trip document generation at [docs/support_matrix.md:38](support_matrix.md). The embedded metadata may still preserve IR, but `compile_to_nir()` parses grammar text before consulting embedded IR in [neurocnl/pipeline.py:711](../neurocnl/pipeline.py), so invalid visible grammar still aborts.

**Impact:** Users can click Generate, receive a CNL document labeled as round-tripable, then fail when they feed that document back into NeuroCNL. That is a product-trust bug.

**Recommendation:** Make `emit_canonical_cnl()` emit only parser-accepted grammar, or change `parse_spec_text()`/`compile_to_nir()` to honor embedded IR before validating generated grammar. Add explicit parser tests for every line shape emitted by `emit_canonical_cnl()`.

### P0 — `/api/validate` can report success for specs that cannot lower, while `/api/generate` crashes

**Evidence:** The bridge catches `LoweringError` only while building planner data, discards it, and continues validation without IR at [backend/app/services/neurocnl_bridge.py:110](../backend/app/services/neurocnl_bridge.py). The underlying validation function accepts `ir=None` at [neurocnl/pipeline.py:356](../neurocnl/pipeline.py), so structural IR conflicts can be invisible to `/api/validate`.

Confirmed with this spec:

```text
The network MUST contain an excitatory input population of 4 neurons
The network MUST contain an excitatory input population of 5 neurons
```

Observed behavior:

- `/api/validate`: `200 OK`, `overall: true`
- `/api/generate`: unhandled `LoweringError: Conflicting population field 'size' for 'input': 4 vs 5.`

The crash path exists because `/api/generate` catches only `ValueError` at [backend/app/routers/generate.py:45](../backend/app/routers/generate.py), while `build_ir_from_spec_text()` raises `LoweringError` from [neurocnl/pipeline.py:315](../neurocnl/pipeline.py).

**Impact:** The frontend can show a green validation state for an impossible network, then fail during generation/export. That breaks the core authoring workflow.

**Recommendation:** Treat IR lowering as part of validation for NIR-backed workflows. If lowering fails, return a structured validation failure. In `/api/generate`, catch `LoweringError` and `MaterializerError`, not just `ValueError`.

### P1 — The support matrix, capability registry, public API, and REST API disagree on Nengo and legacy exporters

**Evidence:** The support matrix states that `nengo` is unsupported and removed from the public surface at [docs/support_matrix.md:28](support_matrix.md). The capability registry still marks `nengo` with notes `"Primary execution backend."` at [neurocnl/backends/capabilities.py:58](../neurocnl/backends/capabilities.py). The package docstring still says NeuroCNL generates Nengo networks at [neurocnl/__init__.py:1](../neurocnl/__init__.py), and it still exports `generate`, `export`, and `EXPORTERS` at [neurocnl/__init__.py:26](../neurocnl/__init__.py).

Meanwhile, the REST export endpoint returns `410 Gone` for formats listed in `EXPORTERS` at [backend/app/routers/export.py:107](../backend/app/routers/export.py), but `backend/tests/test_export_router.py` still expects those exports to succeed at [backend/tests/test_export_router.py:81](../backend/tests/test_export_router.py).

**Impact:** A user, downstream module, or agent cannot know which API surface is authoritative. The docs say “do not use Nengo,” the Python package still presents it as a first-class public API, and the backend rejects legacy exports.

**Recommendation:** Pick one contract and enforce it everywhere. If NIR-only is the supported product surface, move Nengo generation/export APIs behind clearly named legacy modules, remove/rename `BACKEND_CAPABILITIES["nengo"]` from public planning, and update tests to assert `410` for REST legacy exporters. If Python-library legacy APIs remain supported, the support matrix and backend should say so explicitly.

### P1 — Checked-in tests are out of sync with current implementation contracts

**Evidence:** Focused test runs produced:

- `backend/tests/test_generate_router.py`: 1 failure, the broken round-trip above.
- `backend/tests/test_export_router.py`: 11 failures. Legacy exporter tests expect `200`, but code returns `410`; mocks target `backend.app.routers.export.export` and `ensure_runtime_dependency`, which no longer exist in that module.
- `neurocnl/ir/test_ir_lowering.py`: 12 failures because tests expect IR keys like `"sensory neuron"` and `"input population"`, while current lowering normalizes them to `"sensory"` and `"input"`.
- `neurocnl/test_planner.py`: 1 failure where Akida1 sequential topology is expected `faithful`, but planner returns `unsupported`.
- `ruff`: 1 import-order failure in `backend/app/routers/generate.py`.

The IR identifier changes may be intentional, and recent Open Brain context suggests subject normalization was a deliberate fix. The problem is that the regression suite was not updated to encode the new contract.

**Impact:** CI cannot be trusted as a release signal. Some failures are probably stale tests; at least one is a real product regression. Either way, the project currently lacks a single executable truth.

**Recommendation:** Do a contract-sync pass before feature work: update or delete stale tests, add new tests for the intended NIR-only API behavior, and require the focused backend/core suites to pass before claiming readiness.

### P1 — Akida1 topology semantics contradict themselves

**Evidence:** The support matrix says Akida1 is strict sequential only at [docs/support_matrix.md:33](support_matrix.md). The test at [neurocnl/test_planner.py:97](../neurocnl/test_planner.py) expects a sequential Akida1 topology to be `faithful`. But `BACKEND_CAPABILITIES["akida1"]` marks `network_topology` as `unsupported` at [neurocnl/backends/capabilities.py:152](../neurocnl/backends/capabilities.py), and the planner returns `unsupported`.

**Impact:** Akida1 users get inconsistent answers depending on whether they read docs, tests, or planner output. Hardware deployment gates are exactly where ambiguity is most expensive.

**Recommendation:** Decide whether sequential Akida1 is supported, approximate, or unsupported. Then update `capabilities.py`, `plan_akida_exportability()`, docs, and tests together.

### P1 — There are two incompatible `compile_to_nir()` APIs

**Evidence:** The public API in [neurocnl/compile.py:118](../neurocnl/compile.py) returns a `nir.NIRGraph`, accepts `save_to=...`, and raises `CompileError` with structured diagnostics. The older pipeline API in [neurocnl/pipeline.py:709](../neurocnl/pipeline.py) requires a positional filename, returns `NetworkIR`, and raises plain `ValueError`.

The backend export router imports the old pipeline function at [backend/app/routers/export.py:24](../backend/app/routers/export.py), while `neurocnl.__init__` exports the new public function at [neurocnl/__init__.py:25](../neurocnl/__init__.py).

**Impact:** This is a trap for maintainers and downstream modules: the same name means different signatures, return types, and error contracts depending on import path. It also helps explain why API wrappers lag behind the healthier public compiler.

**Recommendation:** Rename the pipeline helper, or make it delegate to the public compiler and return a consistent result/diagnostic type. Backend code should consume the structured public API unless it has a strong reason not to.

### P2 — HTML report rendering trusts caller-supplied validation/network summaries too much

**Evidence:** `_build_html_report()` uses caller-supplied `validation_summary`, `network_summary`, `simulation_summary`, `backend_support`, and `generator_fidelity` from [backend/app/routers/export.py:189](../backend/app/routers/export.py). Values are HTML-escaped, which is good, but the report is not recomputed server-side from the submitted spec.

**Impact:** A client can ask NeuroCNL to export an official-looking report saying validation passed or backend support is favorable without the server verifying those summaries. This is not XSS, but it is a provenance/trust problem for a scientific/engineering artifact.

**Recommendation:** Either label supplied summaries as client-provided, or recompute validation/backend support server-side for HTML export and include a clear generated-at/version/provenance block.

### P2 — CORS and authentication defaults are development-friendly, not production-safe

**Evidence:** Authentication is disabled by default at [backend/app/middleware/auth.py:18](../backend/app/middleware/auth.py). CORS defaults to `*` when no origin env is set at [backend/app/main.py:130](../backend/app/main.py), and the test explicitly locks in allow-all default behavior at [backend/tests/test_cors_config.py:9](../backend/tests/test_cors_config.py).

**Impact:** This may be acceptable for local launcher use, but it is unsafe as a default if the backend is exposed beyond localhost. Several endpoints can generate artifacts, inspect jobs, and interact with deployment flows.

**Recommendation:** Gate production mode with fail-closed defaults: require explicit origins and auth configuration when binding to non-loopback hosts, while preserving easy local defaults for development.

## What Holds Up

- The new public `neurocnl.compile.compile_to_nir()` design is sound: structured diagnostics, explicit stages, fail-closed materialization, optional save path, and no Nengo construction.
- The NIR materializer is honest about approximation through `nir_lowering_summary` and advisory metadata.
- Focused compiler/NIR tests passed: `65 passed` across `test_compile.py`, `test_nir_integration.py`, and `test_nir_to_cnl.py`.
- Parse errors are generally normalized into actionable diagnostics with line/raw/hint fields.
- The backend is moving in the right direction by making simulation unsupported on the NIR-only surface rather than silently routing through Nengo.

## What Does Not Hold Up Yet

- The REST layer does not consistently use the direct NIR compiler contract.
- Validation does not reliably prove that a spec can lower/materialize.
- Generated CNL is not guaranteed to be parseable by NeuroCNL.
- Legacy Nengo/export surfaces are half-removed: unavailable in REST, still prominent in Python API/docs/capability registry, and expected by stale tests.
- Current tests are not a reliable quality gate because they encode multiple mutually incompatible historical contracts.

## Recommended Fix Order

1. Fix `/api/validate` and `/api/generate` error handling so IR lowering/materialization failures become structured 422 responses.
2. Make canonical CNL emission parser-compatible, then make the existing round-trip test pass.
3. Resolve the NIR-only vs legacy-Nengo product contract and update support matrix, capability registry, public exports, REST behavior, and tests in one change.
4. Sync IR identifier tests with the intended normalized subject contract and document the stable identifier rules for downstream modules.
5. Align Akida1 topology support across docs, planner, capability registry, and deployment tests.
6. Replace the old `neurocnl.pipeline.compile_to_nir()` API with a compatibility wrapper around the structured public compiler.
7. Re-run the full focused gate: backend generate/validate/export tests, IR/parser/materializer tests, planner/capability tests, `ruff`, and then the broader module suite.
