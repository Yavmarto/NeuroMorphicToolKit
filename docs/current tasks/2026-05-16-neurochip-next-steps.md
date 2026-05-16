# Neurochip — Next Steps

**Date**: 2026-05-16
**Status of prior block**: T0-NC (9-phase stabilisation from `CODE_REVIEW_CRITICAL_2026-05-14.md`) marked Complete on 2026-05-14.
**Scope reminder**: Neurochip's active role is CNL Studio deployment-flow backend truthfulness. Full hardware product UX remains out of scope until explicitly re-scoped.

---

## Completed (T0-NC)

All 9 phases of the critical review remediation are marked complete:

- Startup: `neurochip.app.main` imports with all optional SDKs absent
- Verification harness: `pytest`, `ruff`, `mypy` green
- PYNQ export: fail-closed, validated against `PynqOverlayConfigArtifactContract` before returning ZIPs
- Analysis: target-specific synapse capacity (15,360-synapse PYNQ limit) enforced in constraint analyzer
- Deploy semantics: responses include `runtime_mode`, `preflight_status`, `support_level`; simulator fallback explicitly labelled
- PYNQ HTTP error taxonomy: `DEVICE_NOT_FOUND` → 503, overlay mismatch → 422, MMIO overflow → 413/422
- Docs: AGENTS.md, README, neurochip_spec.md reconciled to CNL Studio frontend ownership
- Hardening: auth/CORS defaults, Akida SSRF allowlist, flash job bounds, ZIP validation, deployment DB path
- Heuristic labelling: quantizer, fault_runner, power_estimator, partitioner all emit `support_level` / `is_estimate`

---

## Step 1 — Verify T0-NC Exit Criteria (Before New Work)

T0-NC was marked complete the same day as the code review. Run this gate before building on top:

```bash
cd Neurochip
poetry run python -c "import neurochip.app.main"
poetry run pytest neurochip/tests -q
poetry run ruff check .
poetry run mypy .
```

And cross-module:
```bash
# From repo root
python3 scripts/launcher_control_service.py --doctor --json
python3 -m pytest tests/integration/test_cross_module.py -q
```

If any checks are red → fix using the existing T0-NC phase plans before proceeding.

---

## Step 2 — T1-x: API Provenance and Production-Safe Defaults (Near-Term)

**Priority**: P1 — now unblocked (T0-CR complete)
**Why now**: Neurochip exposes hardware control routes (flash, PYNQ deploy, Akida dispatch, loop start/stop) without authentication by default. T1-x is the right moment to harden this correctly, not after adding more endpoints.

### Tasks

| # | Task | Key files |
|---|------|-----------|
| 1 | Fail startup when `NEUROCHIP_AUTH_ENABLED=true` and key is still the default `neurochip-secret-key` | `Neurochip/neurochip/app/auth.py` |
| 2 | Narrow default CORS from `*` to loopback (`localhost`, `127.0.0.1`) unless `ALLOWED_ORIGINS` is explicitly set | `Neurochip/neurochip/app/main.py` |
| 3 | Add Akida `remote_server` allowlist: block loopback/private/link-local/metadata-service targets by default | `Neurochip/neurochip/app/routers/akida.py` |
| 4 | Add `generated_at`, `neurochip_version`, and `validation_status` to export/deploy response schemas | `Neurochip/neurochip/app/schemas/`, affected routers |
| 5 | Test: local-dev defaults work; production env with default key fails closed | `Neurochip/neurochip/tests/test_auth.py` |

---

## Step 3 — Wire `/partition` to Real Partitioner (Near-Term, Small Win)

**Priority**: P1 — one-function wiring job, removes last placeholder 501 from a deployed route
**Why now**: `partitioner.py` is fully implemented (`suggest_partitions()` exists). The router just returns a placeholder.

```python
# Neurochip/neurochip/app/routers/analysis.py lines ~20-29
# Replace placeholder with: result = suggest_partitions(payload); return result
```

Key files:
- `Neurochip/neurochip/app/routers/analysis.py`
- `Neurochip/neurochip/app/services/partitioner.py`
- `Neurochip/neurochip/tests/test_partitioner.py` — add router integration test

---

## Step 4 — Mount or Deprecate SpiNNaker 2 Router (Near-Term, Cleanup)

**Priority**: P2 — low-effort, prevents silent dead code
`Neurochip/neurochip/app/routers/spinnaker2.py` exists with basic routes but is not mounted in `main.py`.

Options:
- **Mount it**: add `app.include_router(spinnaker2.router, ...)` in `main.py`; ensure it follows the same optional-import pattern as Lava
- **Deprecate it**: move to `routers/archive/` and add a note in AGENTS.md

Key files:
- `Neurochip/neurochip/app/main.py`
- `Neurochip/neurochip/app/routers/spinnaker2.py`

---

## Step 5 — T2-1: Quantization-Aware Lowering (Medium-Term)

**Priority**: Tier 2 — requires Tier 1 NIR stability confirmed (T1-1 through T1-7 all complete ✅)
**Goal**: Replace seeded heuristic quantizer with real NIR-adjacent weight quantization for PYNQ (int8) and Akida (1–4 bit).

### Scope
- PYNQ: quantize weights to int8 via NIR `Linear` node weight tensors; validate against overlay contract
- Akida: pass quantized NIR to Akida SDK mapper; use real accuracy impact from SDK rather than seeded formula
- Keep synthetic estimator as fallback when real SDK unavailable; label it explicitly
- Gate: quantized PYNQ export must pass `validate_pynq_compile_artifact()`

Key files:
- `Neurochip/neurochip/app/services/quantizer.py`
- `Neurochip/neurochip/app/services/akida_backend.py`
- `Neurochip/neurochip/contracts/quantization_contracts.py`

---

## Step 6 — T2-3: Multi-Chip Partitioning (Medium-Term)

**Priority**: Tier 2 — requires T2-1 and stable single-graph semantics (T1-2 complete ✅)
**Goal**: Wire `suggest_partitions()` to a real response model and surface in CNL Studio for networks exceeding single-target capacity.

### Scope
- Add `PartitionResult` schema with `strategy`, `sub_graphs`, `latency_impact`, `warnings`
- Return it from `/api/neurochip/analysis/partition` (already wired in Step 3 above)
- CNL Studio partition view: show diagram of sub-graph assignment across targets
- Keep single-target deploy as the primary path; partitioning is an advisory output only

Key files:
- `Neurochip/neurochip/app/services/partitioner.py`
- `Neurochip/neurochip/app/schemas/` (new `PartitionResult`)
- `neurocnl/frontend/lib/features/deploy/` (CNL Studio partition display)

---

## Deferred (Out of Scope Until Re-Scoped)

| Feature | Spec ID | Reason |
|---------|---------|--------|
| Target comparison table (PDF/CSV) | NC-T2 | Hardware deployment not in active scope |
| Interactive quantization explorer UI | NC-Q1/Q2 | UI in CNL Studio; backend synthetic only until T2-1 |
| Real fault injection (not synthetic) | NC-F1 | Requires hardware-verified test rig |
| Loihi 2 real HDF5 deployment | NC-FW3 | NxSDK not available in current env |
| Real power/latency estimates | NC-P1/P2 | Requires hardware profiling data |
| BrainScaleS, SpiNNaker full support | — | Stub generators only; hardware access needed |

---

## Summary Priority Order

| # | Task | Effort | Blocking |
|---|------|--------|---------|
| 1 | **Verify T0-NC exit criteria** | ~1h | Must pass before building anything new |
| 2 | **T1-x: Auth/CORS/provenance** | ~1 day | Unblocked now |
| 3 | **Wire `/partition`** | ~2h | Unblocked now |
| 4 | **Mount/deprecate SpiNNaker 2** | ~30min | Unblocked now |
| 5 | **T2-1: Quantization-aware lowering** | ~2–3 days | Tier 1 stable ✅ |
| 6 | **T2-3: Multi-chip partitioning** | ~2–3 days | T2-1 done |
