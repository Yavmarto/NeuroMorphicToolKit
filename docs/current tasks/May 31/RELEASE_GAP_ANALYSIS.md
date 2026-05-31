# NMTK Release Gap Analysis — Essential Missing Functions

**Date:** 2026-05-31
**Scope:** Suite control plane + all modules mapped in `nmtk/neuro_toolkit/assets/modules.json`, plus `neurocli` and `nmtk_ui_core`.
**Purpose:** Identify the functions that are essential and currently missing or incomplete for a serious, credible product release. This is a release-readiness gap list, not a status brag sheet.

> Method: derived from direct reading of module backends (`*/app/routers`, services), Flutter frontends (`*/frontend/lib`), the launcher (`nmtk/`), `suite_api`, manifests, specs, and existing audits (`docs/2026-05-feasibility-review.md`, `docs/archive/16-May-2026-status-Claude.md`, `docs/current tasks/nmtk-strategic-action-plan.md`). Where an older audit and the current tree disagree, the current tree wins.

---

## How To Read This

Each module section lists:

- **Current state** — what is actually implemented in the tree today.
- **Essential & missing** — functions that block a serious release (P0/P1).
- **Important but deferrable** — valuable for a polished release, not a hard blocker (P2).

Priority key:

- **P0** — blocks any credible release. Trust, safety, or core-promise breaker.
- **P1** — needed for a stable, demoable, non-misleading release.
- **P2** — quality/polish; ship-after.

---

## Suite-Wide (Cross-Cutting) — Highest Leverage

These are not owned by one module but gate the whole product. They are the single biggest release risk per the feasibility review.

### Essential & missing

- **P0 — Default-secure auth posture.** Every backend defaults to no auth: `AUTH_ENABLED=false` in module middleware (`neurocnl/backend/app/middleware/auth.py:20`), and `suite_api` ships CORS open to `*` by default (`suite_api/middleware/__init__.py:40`). A shipped product must default to authenticated, or refuse to bind to non-localhost without a key. Add a single suite-level auth story (API key or token) enforced at `suite_api`, not per-module opt-in.
- **P0 — Remove hardcoded secrets from compose.** Grafana admin password is hardcoded `admin` (`docker-compose.yml:209`). No shared/prod deployment can ship this. Move to env/secret with a generated default.
- **P0 — Licensing coverage.** No root `LICENSE` file and no per-module `LICENSE` (only `nmtk_ui_core/LICENSE` exists), while READMEs claim "MIT". A serious release needs a root license, per-module license headers/files, and a third-party dependency/license manifest (especially for vendored SDK adapters: Lava, Akida/MetaTF, SynSense, Rockpool).
- **P0 — First-run installer reliability + repair.** The feasibility review names distribution as the real product risk. Installer scaffolding exists (`nmtk/installer/{macos,windows,linux}`) but the essential missing functions are: resumable/repairable installs, half-install rollback, Python-env provisioning verification, and surfaced diagnostics when a module install fails midway. Without this the "one-click backend" promise collapses.
- **P1 — Signed builds + update channel.** Codesigning/notarization (macOS), signed installers (Windows), and a signed module-delivery/update pipeline. Referenced in feasibility doc as required for a credible desktop product; not present as a delivered function.
- **P1 — End-to-end golden-path test in CI.** A single automated test that runs Golden Path 1 (author → validate → simulate → inspect → persist) against real services. `tests/integration/` has cross-module and teensy e2e tests, but the canonical no-hardware golden path should be a gated, named release check.

### Important but deferrable

- **P2 — Support-tier matrix as shipped product truth.** A machine-readable per-module/per-target support matrix (`faithful`/`approximate`/`parser-recognized`/`unsupported`) surfaced in the UI, not just in docs.
- **P2 — Telemetry/observability opt-in + privacy notice** for a distributed desktop app.
- **P2 — Crash/log capture and "export diagnostics bundle"** action from the launcher.

---

## neurocnl / NeuroStudio (incl. NeuroSim canvas)

**Current state:** Most mature module. Backend has real routers for parse, validate, generate, simulate (NIR-only; legacy `simulate` returns HTTP 410), export, deploy, jobs, training, nir_inspect, neurosim_handoff, prosthetic. NeuroSim canvas routers (components, nir_canvas, preview, simulation_ws, sweep, spinnaker2) are integrated under the Studio surface. Large Flutter frontend with canvas editor, validation panel, pipeline bar, spike raster.

### Essential & missing

- **P1 — Honest validation semantics.** The Layer 1 "biological invariant" framing predates the NIR-only pivot; an in-flight task (`docs/current tasks/2026-05-27-validation-deploy-readiness.md`) flags that several invariants may no longer be meaningful and that deploy-readiness failures (generate/preflight) are not mirrored in the validation panel. Essential missing function: a single source of truth so a red Deploy step always shows a red Validation panel, with NIR-relevant rule labels. Replace "biological validation" claims with "structural/architectural invariant verification" per the strategic plan.
- **P1 — Export fidelity truth-telling.** Multiple exporters raise `NotImplementedError` for unsupported topologies (`neurocnl/converter/sinabs_io.py`, `spinnaker2_io.py`, `rockpool_io.py`; `export/sinabs_exporter.py`). Essential missing function: a pre-export capability check that tells the user *before* export which constructs won't survive a given target, instead of failing mid-pipeline. "Exportable" must not imply "deployable."
- **P1 — Training pipeline completion.** `training_registry.py:128` raises bare `NotImplementedError`. If training is advertised in the manifest (`installExtras: training`), the registered training paths must be complete or explicitly gated as experimental in the UI.

### Important but deferrable

- **P2 — Spec verification / synthesis** (Z3-based formal checks, inverse spec synthesis) — listed as research directions in `neurocnl/ROADMAP.md`; not release blockers.
- **P2 — BrainFlow live-acquisition phase** (ROADMAP Phase 9) — defer to Neurosense ownership.

---

## Neurochip (hardware execution / deployment)

**Current state:** Backend is broad and real: routers for targets, analysis (partition/compare now implemented), quantization, estimation, faults, export, deployments, serial, akida, lava, pynq, speck, spinnaker2. Hardware SDKs degrade gracefully via optional imports. **No standalone frontend** — `Neurochip/frontend` has no `lib/` (by design; NeuroStudio owns deployment UI via ADR 0021 handoff).

### Essential & missing

- **P0 — One genuinely validated hardware path.** This is the feasibility review's Golden Path 2. Today hardware support spans many targets (Akida, PYNQ-Z2, Loihi/Lava, Speck, SpiNNaker2, Teensy serial) but breadth without depth is a credibility risk. Essential missing function: one target proven end-to-end (preflight → install-missing-from-launcher → deploy → capture logs/metrics/failure reason) with honest diagnostics. Teensy and PYNQ have release-readiness docs; pick one and make it the shipped, tested path.
- **P1 — Deployment telemetry & failure surfacing in the owning UI.** Since Neurochip has no own frontend, the handoff contract must guarantee that deploy state, logs, and failure reasons render in NeuroStudio. Essential missing function: verified round-trip of deployment records/telemetry to the Studio deployment panel (not just stored server-side).
- **P1 — Preflight honesty for unsupported targets.** Ensure every advertised target either runs preflight that returns a real capability verdict or is clearly labeled `simulator_only` / `unsupported` in the UI (manifest already has `localModeFallback: simulator_only` for Akida — extend this contract to all targets).

### Important but deferrable

- **P2 — Prune advanced HW-engineering features** (fault injection/dead-neuron sweeps) from the shipped scope per the strategic plan; keep as research/optional.
- **P2 — Multi-target "write once, deploy everywhere"** — explicitly out of near-term scope.

---

## Neurobench (benchmarking)

**Current state:** Real routers: benchmarks, runner, results, comparison, baselines, reports, regression, faults, perturbation, pynq, spinnaker2, synsense. Flutter frontend complete (execution, comparison, robustness). SQLite result store.

### Essential & missing

- **P0 — Simulated vs. on-chip metric demarcation.** Per the strategic plan, CPU-estimated metrics must be visibly labeled so they are never confused with physical on-chip results. Essential missing function: every metric/report carries and renders a provenance tag (`cpu-estimated` vs `on-device`), enforced in both the report payload and UI. Shipping energy/latency numbers without this is actively misleading.
- **P1 — Reproducibility metadata on every result.** A serious benchmark store must record model hash, target, SDK versions, seed, and environment with each run so results are comparable and citable. Confirm/complete this on the result schema and report export.

### Important but deferrable

- **P2 — Standard published baselines** bundled and versioned for headline tasks.
- **P2 — Regression gating** wired into CI as an optional check.

---

## Neurosense (sensory encoding / acquisition)

**Current state:** Real routers: devices, encoding, presets, recording, sessions, stream, quality, export, nir, prophesee, pynq. Has its own `auth.py`. Flutter frontend complete (live acquisition, spike encoding).

### Essential & missing

- **P1 — Encoding-preset honesty.** Per the strategic plan, add explicit disclaimers that spike-encoding presets are empirical research starting points, not validated biological models. Essential missing function: preset metadata + UI copy clarifying provenance/intended use.
- **P1 — Hardware-acquisition support tiering.** Live device paths (BrainFlow/OpenBCI, Prophesee event camera) must degrade clearly when SDK/hardware is absent and declare their support tier. Confirm graceful "no device" UX rather than silent empty streams.

### Important but deferrable

- **P2 — Dataset import/export round-trip** with NIR-compatible artifacts validated against Neurobench/NeuroStudio consumers.
- **P2 — Recording session retention/cleanup policy** for long-running captures.

---

## Neurohub (sharing / registry)

**Current state:** Largest router surface: auth, projects, members, milestones, notes, activity, dashboard, assets, sharing, workflows, config, plus registry_* (artefacts, auth, community, health, search). SQLAlchemy ORM + Alembic migrations. Auth service implemented. Frontend complete. README lists 85% with ⚠️ tests / ❌ CI.

### Essential & missing

- **P0 — Trustworthy auth + access control for a network-exposed service.** A registry that accepts uploads and shares artifacts is the highest-risk surface to ship without enforced authN/authZ. Essential missing function: enforced auth by default on write paths, per-project membership checks verified end-to-end, and rate limiting on registry endpoints.
- **P1 — Artifact integrity + storage backing.** `neurocli` already verifies SHA-256 on pull; ensure the server computes/stores checksums on upload and that object storage (MinIO/S3 per spec) is wired, not just local filesystem. Essential missing function: checksum-on-write + configurable storage backend.
- **P1 — CI + test coverage to green.** README marks tests ⚠️ and CI ❌. For the module that brokers shared artifacts, a passing test+CI gate is a release prerequisite, not polish.
- **P1 — Team-first / private-lab repository mode.** Per the strategic plan, prioritize the private-team use case and the "open in Studio" deep-link. Essential missing function: a verified private-repo permission model and the deep-link round-trip.

### Important but deferrable

- **P2 — Moderation / abuse controls** for any public community registry.
- **P2 — Federation across registries** — explicitly future.

---

## Neuro-Dream-Hand (applied robotics example)

**Current state:** Rich Python package (core/envs, sensors, hardware, learning, analytics, overlays, verification, shell, contracts). Manifest lists it as `neuro_dream_hand` — "Prosthetic SNN physics simulation (CLI only)", MuJoCo-required, no frontend, standalone-only.

### Essential & missing

- **P1 — Reclassify as example/demo, not a core peer module.** Per the strategic plan, move NDH out of the core launcher peer manifest into an `examples/`/`demos/` framing. Essential missing function: manifest + launcher model/test updates so it presents as a reference application, not suite infrastructure (must be paired per AGENTS.md launcher rules).
- **P1 — MuJoCo dependency gating.** Since it requires MuJoCo, the install/run path must detect MuJoCo and fail with a clear, actionable message rather than a stack trace when absent.

### Important but deferrable

- **P2 — Physical Teensy/gripper end-to-end** kept as an advanced, separately-documented demo (Teensy release-readiness doc already exists).

---

## NMTK Launcher (`nmtk/`) + Control Plane

**Current state:** Flutter desktop launcher (screens, services, providers), `launcher_control` server, `scripts/launcher_control_service.py` doctor, guardrail wrapper `scripts/run_launcher_guardrails.sh`. Manifest-driven module lifecycle. iOS/Android folders present (mobile companion).

### Essential & missing

- **P0 — Robust install-state machine with repair.** The launcher is the product's front door. Essential missing functions: per-module install/readiness/repair state that survives restarts, a "repair" action that re-runs a failed step, and clear preflight-failed vs degraded-optional-capability reporting (the AGENTS.md launcher rules already require this distinction — verify it is surfaced in UI, not just logs).
- **P1 — Backend-connection modes proven.** README advertises Local/Docker/Kubernetes/Connect-to-existing. Essential missing function: each advertised mode either works end-to-end or is hidden behind a "coming soon"/disabled state. Do not show modes that aren't wired.
- **P1 — Launcher doctor as a release gate.** Treat `python3 scripts/launcher_control_service.py --doctor --json` `fatalCount > 0` as a hard blocker in CI for any launcher/manifest change (per AGENTS.md).

### Important but deferrable

- **P2 — Mobile companion scope lock.** Per feasibility review, ship mobile as a monitor/browse/trigger companion only; explicitly do not promise local backend hosting on mobile. The essential near-term function is read-only health/jobs/projects + safe remote triggers.

---

## suite_api (unified gateway)

**Current state:** In-process domain mounts + proxy to workers, health router, graceful 503 when a worker is absent, CORS + request-id middleware.

### Essential & missing

- **P0 — Central auth enforcement** (see suite-wide). The gateway is the right place to enforce one auth story instead of per-module opt-in.
- **P1 — Production CORS default.** Default `ALLOWED_ORIGINS` should not be `*`; ship a locked-down default with an explicit dev override.
- **P1 — Rate limiting / request size limits** on proxied upload-capable routes (registry, recordings, NIR bundles).

---

## neurocli (scriptable front door)

**Current state:** Implemented Typer package (`neuro new`, `status`/`install`/`run`, `hub login`/`push`/`pull`/`search`) with SHA-256 verification and a shared URI parser kept byte-equivalent with the backend. Strategic plan recommends **de-listing from core manifest**.

### Essential & missing

- **P1 — De-list from core manifest, keep as developer tooling.** Per the strategic plan, remove `neurocli` from `modules.json` and launcher models/tests, and document it under "developer tooling/Planned Roadmap" so the suite presents an honest module count. (If it is currently not in the manifest, confirm and document that explicitly.)
- **P1 — Auth parity with Neurohub.** Once the registry enforces auth, `neuro hub` must handle token storage/refresh and 401s cleanly.

### Important but deferrable

- **P2 — Shell completion + packaged binary** for non-Python users.

---

## nmtk_ui_core (shared Flutter design system)

**Current state:** Real shared library (40+ widgets, design tokens, theme), the only module with a `LICENSE`. Frontends depend on it; `file_picker` version conflict from the May audit is resolved (all on `^11.0.2`).

### Essential & missing

- **P1 — Enforced boundary + version pinning.** As the shared UI foundation, essential missing function is a contract test/lint that prevents modules from drifting on shared dependency versions again (the prior `file_picker` conflict blocked the whole pub graph). Pin shared transitive deps centrally.
- **P1 — Accessibility baseline.** A shipped UI library should guarantee a contrast/semantics/focus baseline across shared widgets (full WCAG conformance requires manual AT testing and expert review).

### Important but deferrable

- **P2 — Visual regression / golden tests** for the shared widget set.
- **P2 — Published versioning** if it is ever consumed outside this monorepo.

---

## Release Blocker Summary (P0 First)

| # | Area | Essential missing function | Priority |
|---|------|----------------------------|:--------:|
| 1 | Suite | Default-secure auth (modules + `suite_api`), not opt-in | P0 |
| 2 | Suite | Remove hardcoded Grafana password; secret-manage compose | P0 |
| 3 | Suite | Root + per-module licensing and third-party license manifest | P0 |
| 4 | Suite/Launcher | Reliable, repairable first-run installer with rollback | P0 |
| 5 | Neurochip | One end-to-end validated hardware path with honest diagnostics | P0 |
| 6 | Neurobench | Visible simulated-vs-on-chip metric demarcation | P0 |
| 7 | Neurohub | Enforced auth/access control on a network-exposed registry | P0 |
| 8 | suite_api | Central auth enforcement at the gateway | P0 |
| 9 | Launcher | Robust install-state machine + repair + preflight/degraded reporting | P0 |
| 10 | Suite | Signed builds + signed update/module-delivery channel | P1 |
| 11 | neurocnl | Unified validation/deploy-readiness truth + NIR-relevant labels | P1 |
| 12 | neurocnl | Pre-export capability check (exportable ≠ deployable) | P1 |
| 13 | Neurohub | Artifact checksum-on-write + object storage backend; green CI | P1 |
| 14 | Suite | Gated golden-path-1 e2e test in CI | P1 |

## Recommended Sequencing

1. **Trust & safety first (P0 #1–3, #7–8):** auth defaults, secrets, licensing. Cheapest path to "not embarrassing/unsafe to ship."
2. **Front-door reliability (P0 #4, #9):** installer + launcher state machine. This is the product, per the feasibility review.
3. **Honesty of results (P0 #5–6, P1 #11–12):** one validated hardware path, metric provenance, validation/export truth-telling.
4. **Distribution hardening (P1 #10, #13–14):** signing/update channel, registry integrity + CI, golden-path gate.
5. **Scope honesty:** de-list `neurocli`, reclassify `Neuro-Dream-Hand` as a demo, ship the support-tier matrix.

> Guiding principle from the feasibility review: the project does not need less ambition — it needs a smaller *claim surface* than its *architecture surface*. Most P0 items narrow claims and harden trust rather than add features.
