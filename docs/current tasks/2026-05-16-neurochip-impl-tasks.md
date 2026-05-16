# Neurochip Implementation Tasks — 2026-05-16

Six self-contained code changes; no hardware or optional SDKs required.
All files live under `Neurochip/neurochip/`.

## Execution order

| # | Task | Risk |
|---|------|------|
| 1 | Auth hardening — fail startup on default key | Low |
| 2 | CORS — narrow wildcard default to loopback | Low |
| 3 | SpiNNaker 2 — mount router in main.py | Low (additive) |
| 4 | Akida SSRF — disable `remote_server` without allowlist | Medium |
| 5 | Provenance — add headers/fields to responses | Medium |
| 6 | `/partition` — wire to real partitioner service | Medium |

---

## Task 1 — Auth: Fail Startup on Default Key

**Files**: `app/auth.py`, `tests/test_auth.py`

Replace `warn_if_insecure_default_api_key()` (logs a warning) with
`validate_startup_auth_config()` (raises `RuntimeError`).
Update the call site in `main.py` to use the new name.

Exit criteria:
- `NEUROCHIP_AUTH_ENABLED=true` + default key → `RuntimeError` at import
- `NEUROCHIP_AUTH_ENABLED=true` + custom key → startup succeeds

---

## Task 2 — CORS: Narrow Wildcard Default

**File**: `app/main.py`

Change `os.getenv("ALLOWED_ORIGINS", "*")` default to a comma-separated
loopback list covering `localhost:8000` (neurocnl), `localhost:3000`,
`localhost:5173`, and `127.0.0.1` variants.

---

## Task 3 — SpiNNaker 2: Mount Router

**File**: `app/main.py`

Import `spinnaker2` router using the same try/except optional pattern as Lava.
Mount conditionally. Log availability in `log_startup_configuration()`.

---

## Task 4 — Akida SSRF: Require Explicit Allowlist

**File**: `app/routers/akida.py`

Add two changes to `_validate_remote_url()`:
1. If `NEUROCHIP_AKIDA_ALLOWED_HOSTS` is unset → 403
   `remote_dispatch_not_configured` with remediation hint.
2. Extend `_BLOCKED_AKIDA_NETWORKS` with `0.0.0.0/8` and `fc00::/7`.

**New test file**: `tests/test_akida_ssrf.py`

---

## Task 5 — Provenance Headers

**New file**: `app/utils/provenance.py`
**Files**: `app/routers/export.py`, `app/routers/akida.py`

`provenance_headers(validation_status)` returns three HTTP headers:
- `X-Neurochip-Generated-At`
- `X-Neurochip-Version`
- `X-Neurochip-Validation-Status`

Apply to every `Response(content=zip_bytes, …)` in `export.py` and the
scaffold/on_device return paths in `akida.py`'s `_dispatch_package()`.

**New test file**: `tests/test_provenance.py`

---

## Task 6 — Wire `/partition`

**Files**: `app/schemas/runtime.py`, `app/services/partitioner.py`,
`app/routers/analysis.py`

1. Add `PartitionShard`, `PartitionPlanResponse`, `PartitionResult` schemas.
2. Add `plan_to_response(plan)` helper to `partitioner.py`.
3. Replace placeholder `/partition` handler with real implementation:
   look up target neuron capacity → call `suggest_partitions()` → return
   `PartitionResult` with `support_level: "heuristic"` / `is_estimate: true`.

**Test file**: `tests/test_analysis_router.py`

---

## Verification gate

```bash
cd Neurochip
poetry run pytest neurochip/tests -q
poetry run ruff check .
poetry run mypy .
```
