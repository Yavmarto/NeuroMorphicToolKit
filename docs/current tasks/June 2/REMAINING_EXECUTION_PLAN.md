# Remaining Execution Plan — Release Gap Work

**Date:** 2026-05-31  
**Context:** Picks up after Plans A, B, and C1 are merged to `dev`.  
**Reference:** [`RELEASE_GAP_ANALYSIS.md`](RELEASE_GAP_ANALYSIS.md) — all gap IDs (#N) refer to that document.

---

## What Has Already Shipped (on `dev`)

| Plan | Gap items | Status |
|------|-----------|--------|
| **A — Trust & Safety** | P0 #1–3, #7–8 | ✅ Merged |
| **B — Front-Door Reliability** | P0 #4, #9 | ✅ Merged |
| **C1 — Neurobench Metric Provenance** | P0 #6 | ✅ Merged |

**Also already resolved (no work needed):**
- Licensing: AGPL-3.0 LICENSE files exist across all modules
- neurocli de-listing: already absent from `modules.json`
- neurocnl auth startup warning: already logs `warning` when `AUTH_ENABLED` unset
- `THIRD_PARTY_LICENSES.md`: generated and committed

---

## Plan C2 — neurocnl Validation/Export Honesty
**Gap items:** P1 #11, P1 #12  
**Priority:** Ship-blocking — surfaces contradictory signals to users

### Why

A user can pass neurocnl validation (Layer 1 + Layer 2 + NIR backend verdict) and then have the PYNQ or Teensy deploy step fail for topology reasons the validation panel didn't surface. Conversely, some export-time `NotImplementedError` exceptions in converters are never shown as pre-flight warnings — they only appear as mid-export failures.

### P1 #11 — Validation panel deploy-readiness alignment

**What the gap analysis says:** "a single source of truth so a red Deploy step always shows a red Validation panel, with NIR-relevant rule labels."

**Current state:**
- `POST /api/validate` returns `ValidateResponse { layer1, layer2, overall, backend_support: BackendSupport | None }`
- `BackendSupport.verdict` can be `"faithful" | "approximate" | "unsupported"`
- The Flutter validation panel (`neurocnl/frontend/lib/widgets/validation_panel.dart`) renders Layer 1/2 results but may not prominently surface `backend_support.verdict == "unsupported"` as a "Deploy Blocked" state
- The deploy endpoints (`/api/deploy/teensy`, `/api/deploy/pynq`) run their own preflight checks that can fail for reasons not visible in validate

**What to implement:**
1. Verify that `validate.py` always populates `backend_support` (not None) for standard CNL specs
2. In `validation_panel.dart`: when `backend_support.verdict == "unsupported"`, render a prominent "Deploy Blocked" indicator (danger tone) alongside the standard Layer 1/2 results — so a user never sees green validation but red deploy without explanation
3. Replace "biological validation" / "biophysical invariant" labels with "structural/architectural invariant verification" per the strategic plan

**Key files to read:**
- `neurocnl/backend/app/routers/validate.py` — full endpoint implementation
- `neurocnl/backend/app/schemas/validate.py` — `ValidateResponse`, `BackendSupport`
- `neurocnl/frontend/lib/widgets/validation_panel.dart` — current render logic
- `neurocnl/frontend/lib/providers/canvas/canvas_validation_provider.dart` — state management

**AGENTS.md says:** Read `neurocnl/AGENTS.md`, `docs/support_matrix.md`, run `pytest neurocnl/tests/` + `flutter test`.

---

### P1 #12 — Pre-export capability check

**What the gap analysis says:** "a pre-export capability check that tells the user *before* export which constructs won't survive a given target."

**Current state:**
- `POST /api/export` for the `akida` format already calls `plan_backend_support(ir, "akida")` and surfaces the verdict in `X-NeuroCNL-Backend-Verdict` response header ✅
- `POST /api/export` for `nir` format returns `X-NeuroCNL-Backend-Verdict` header ✅
- Legacy formats (sinabs, spinnaker2, rockpool, etc.) are already blocked with HTTP 410 ✅
- The Flutter export dialog (`canvas/export_dialog.dart`) already renders a `NmtkBackendSupportBanner` with `verdict` and `warnings`
- **The remaining gap:** the banner only shows information from the validate response (`backend_support` from the last validate call). If the user hasn't validated recently, or if the export format has constraints that validate doesn't check (e.g., sinabs requires sequential-only — no branching/merging), the banner may show green when the export would fail

**What to implement:**
1. Add `POST /api/export/preflight` endpoint (or `GET /api/export/capability`) that accepts `{ spec, format }` and returns the capability verdict WITHOUT actually exporting — so the export dialog can query it on format selection
2. Or simpler: in the export dialog, disable the "Export" button and show the capability warning when `backendSupport.verdict == "unsupported"` AND trigger a re-check of `backendSupport` when the user changes the export format (not just on last-validate result)

**Key files to read:**
- `neurocnl/backend/app/routers/export.py` — full export endpoint
- `neurocnl/neurocnl/converter/sinabs_io.py` — what topologies raise NotImplementedError
- `neurocnl/frontend/lib/providers/canvas/canvas_export_provider.dart` — `ExportState`, `backendSupport` lifecycle
- `neurocnl/frontend/lib/widgets/canvas/export_dialog.dart` — current dialog and banner

**Tests:** `neurocnl/backend/tests/test_export_router.py` — add tests for preflight endpoint returning topology warnings.

---

### Verification for C2

```bash
# Backend
cd neurocnl && PYTHONPATH=. pytest neurocnl/tests/ backend/tests/ -p no:nengo -v --tb=short
# Frontend
cd neurocnl/frontend && flutter test
```

---

## Plan D — Distribution Hardening
**Gap items:** P1 #10, P1 #13, P1 #14  
**Priority:** Required for a credible public release — can be parallelised internally

### D1 — Signed builds + update channel (P1 #10)

**What the gap analysis says:** "Codesigning/notarization (macOS), signed installers (Windows), and a signed module-delivery/update pipeline."

#### Task 1 — macOS (✅ DONE 2026-06-01)

**Shipped:**
- `sign-and-notarize.sh` — Developer ID signing, `notarytool` submission/stapling, `--check` and `--dry-run` modes
- `import-signing-cert.sh` — CI keychain import from base64 `.p12` secrets
- `build-standalone.sh` — delegates to signing helper; reads `MACOS_SIGNING_IDENTITY` / `MACOS_NOTARIZE`
- `Makefile` targets: `macos-signing-check`, `build-macos-dmg-signed`
- `.github/workflows/release-desktop.yml` — conditional sign + notarize when secrets are set
- `.github/workflows/ci.yml` — `test-macos-installer-signing` job (dry-run plumbing verification)
- `nmtk/installer/macos/CODE_SIGNING.md` — certificate setup and GitHub secrets documentation
- `tests/test_macos_installer_signing.py` — 7 pytest cases (no real certs required)

**End-to-end signing still requires:** Apple Developer Program cert + repository secrets (`MACOS_CERTIFICATE_P12`, `MACOS_SIGNING_IDENTITY`, `APPLE_*`).

#### Task 2 — Windows (⬜ PENDING)

**Current state:**
- `nmtk/installer/windows/setup.iss` (Inno Setup) has no signing step
- `nmtk/installer/windows/build-standalone.ps1` has no `signtool.exe` integration

**What to implement:**
1. Add a `signtool.exe` call in `build-standalone.ps1` using a code-signing certificate
2. Document cert import steps for local and CI release builds
3. Wire conditional signing into `.github/workflows/release-desktop.yml` when Windows signing secrets are set

**Key files:**
- `nmtk/installer/windows/build-standalone.ps1`, `setup.iss`

#### Task 3 — Update channel (⬜ PENDING)

**What to implement:**
1. Verify that the launcher's `UpdateService` checks a signed manifest (not just a plain GitHub releases URL)
2. Add SHA-256 checksum verification on downloaded update payloads

**Key files:**
- `nmtk/neuro_toolkit/lib/services/update_service.dart`
- `nmtk/AGENTS.md` — launcher change rules

---

### D2 — Neurohub CI to green (P1 #13) ✅ DONE (2026-06-01)

**What the gap analysis says:** "For the module that brokers shared artifacts, a passing test+CI gate is a release prerequisite."

**Shipped:** `passlib` removed; `bcrypt` 4.x used directly; `pytest-asyncio` via `[dev]` + `asyncio_mode = "auto"`; CI installs `Neurohub[dev]`. Verified `226 passed, 3 skipped` locally.

**Original plan (for reference):**
1. Run `cd Neurohub && python -m pytest neurohub/tests/ -v` to get the full failure list
2. Fix the bcrypt/passlib version mismatch — likely `passlib` 1.7.x vs `bcrypt` 4.x incompatibility; fix by pinning `bcrypt<4` or replacing `passlib` with `bcrypt` directly
3. Fix any remaining test failures (likely auth flow tests, DB migration tests)
4. Set up GitHub Actions workflow (or verify the existing one) with a passing gate
5. Verify `registry_artefacts` and write-path auth tests pass with `NEUROHUB_AUTH_ENABLED=true`

**Key files:**
- `Neurohub/pyproject.toml` — dependency versions
- `Neurohub/neurohub/tests/` — all test files
- `Neurohub/.github/workflows/` (or root `.github/`) — CI config
- `Neurohub/AGENTS.md`

**Tests must pass:** `python -m pytest neurohub/tests/ -v` with 0 failures before this plan is done.

---

### D3 — Golden-path CI gate (P1 #14)

**What the gap analysis says:** "A single automated test that runs Golden Path 1 (author → validate → simulate → inspect → persist) against real services."

**Current state:**
- `tests/integration/test_cross_module.py` — cross-module integration tests
- `tests/integration/test_teensy_e2e.py` — hardware e2e (requires Teensy)
- No named "golden path 1" test that runs the full no-hardware flow end-to-end

**Golden Path 1 definition (no hardware required):**
1. **Author** — POST a valid CNL spec to `neurocnl /api/parse`
2. **Validate** — POST to `neurocnl /api/validate`, assert `overall=true`
3. **Simulate** — POST to `neurocnl /api/simulate` (or NeuroSim), get a simulation result
4. **Inspect** — GET the NIR graph from `neurocnl /api/nir_inspect`
5. **Persist** — Save result to Neurobench via `neurobench /api/benchmarks/run`, retrieve it

**What to implement:**
1. Create `tests/integration/test_golden_path_1.py` with a single `test_golden_path_1_no_hardware()` function that calls each step against the running services (using `requests` + the module ports from `modules.json`)
2. Add a pytest mark `@pytest.mark.golden_path` so it can be run selectively
3. Wire it into `scripts/run_launcher_guardrails.sh --with-integration` as a named check
4. Document which services must be running for the test (neurocnl + neurobench at minimum)

**Key files:**
- `tests/integration/test_cross_module.py` — patterns to follow
- `tests/integration/conftest.py` (if exists) — service URL fixtures
- `nmtk/neuro_toolkit/assets/modules.json` — ports for each module
- `scripts/run_launcher_guardrails.sh` — where to add the golden path gate
- `docs/agents/nmtk-backend-smoke.md` — smoke test patterns

**Pre-condition:** Requires neurocnl and neurobench services running locally (can be started with the launcher). The test should skip gracefully if services aren't available (`pytest.skip` with a clear message).

---

## P0 #5 — Neurochip Validated Hardware Path
**Gap item:** P0 #5  
**Priority:** P0 but hardware-dependent — requires device access or detailed investigation

### Why this is a separate investigation

The gap analysis says: "one target proven end-to-end (preflight → install-missing-from-launcher → deploy → capture logs/metrics/failure reason) with honest diagnostics."

Both Teensy and PYNQ-Z2 have release-readiness documents. This is not a software-only plan — it requires:
1. Access to a Teensy or PYNQ-Z2 device
2. A dedicated investigation session reading the release-readiness docs and running the actual flow
3. Identifying what specifically is missing in the end-to-end path

### Investigation tasks (prerequisite before writing a plan)

```bash
# Read the release-readiness docs
cat docs/current\ tasks/2026-05-27-validation-deploy-readiness.md   # if it exists
# Or equivalent Teensy/PYNQ readiness doc
find docs/ -iname "*teensy*" -o -iname "*pynq*" -o -iname "*hardware*" 2>/dev/null
```

**Questions to answer before writing the implementation plan:**
1. Which target (Teensy or PYNQ) is closer to a working end-to-end path right now?
2. What exactly fails when you run preflight → deploy against that target with the current code?
3. Does the Studio UI surface failure reasons when hardware deploy fails? (Neurochip has no frontend — verify the Studio deployment panel shows logs from `Neurochip` via the handoff contract in ADR 0021)
4. What is the `localModeFallback` behavior when the hardware isn't present — is it surfaced as `simulator_only` in the UI?

**Key files to read (during investigation):**
- `Neurochip/neurochip/app/routers/deployments.py` — deployment router
- `Neurochip/AGENTS.md`
- `neurocnl/backend/app/routers/deploy.py` lines 103–200 — Teensy / PYNQ deploy endpoints and their `TeensyNetworkResponse` / `PynqNetworkResponse` schemas
- `docs/archive/` or `docs/current tasks/` — Teensy and PYNQ release-readiness docs

**Output of investigation:** A concrete implementation plan scoped to one target, detailing what code changes are needed to go from "partially works" to "preflight → deploy → diagnostics captured end-to-end".

---

## Recommended Execution Order

| Step | Plan | Effort | Prerequisite |
|------|------|--------|--------------|
| 1 | **D2 (Neurohub CI)** | Medium | ✅ Done 2026-06-01 |
| 2 | **C2 (neurocnl honesty)** | Medium | None — isolated |
| 3 | **D3 (Golden path CI gate)** | Small | neurocnl + neurobench running |
| 4 | **D1 (Signed builds)** | Medium | Signing certs available |
| 5 | **P0 #5 investigation** | Variable | Hardware device available |

D2 first because green CI for Neurohub unlocks confident registry testing, which feeds into C2 and D3. C2 next because it's pure software. D1 last because it requires CI secrets/certs infrastructure.

---

## Scope Explicitly Out of This Sequence

These were flagged P2 or as explicitly deferred in the gap analysis and strategic plan:

- **neurocli binary / shell completion** — developer tooling, already de-listed from manifest
- **Neuro-Dream-Hand reclassification** — in modules.json as demo, reclassification to `examples/` is a Tier 2 fluff cut
- **Support-tier matrix UI** — P2, valuable polish but not blocking
- **Telemetry/observability opt-in** — P2
- **Mobile companion scope lock** — P2, read-only monitor mode only
- **nmtk_ui_core visual regression tests** — P2
- **Neurobench standard baselines / regression CI gating** — P2
- **Neurosense dataset import/export round-trip** — P2
- **Neurohub federation** — explicitly future
