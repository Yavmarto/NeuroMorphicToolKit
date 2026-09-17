# NeuroCNL PoC Demo Readiness Assessment

**Date:** 2026-04-08
**Updated:** 2026-04-09
**Scope assessed:** `neurocnl`, plus the most directly related submodules on the demo path: `Neurosim`, `Neurochip`, and `Neurobench`
**Assessment basis:** current local working tree, targeted test execution where available, and direct inspection of integration code and docs

## Executive Summary

`neurocnl` is the most mature module in this group and is **ready for a constrained PoC demo**.

The strongest honest demo path today is:

1. Author or load a CNL spec in NeuroCNL Studio
2. Parse, validate, generate, and simulate through the `nengo` path
3. Show deployability gating for Teensy / PYNQ / Akida
4. Optionally hand off the Teensy flow into `Neurochip`
5. Optionally show the same canonical design in `Neurosim`
6. Optionally benchmark the simulation path in `Neurobench`

The suite is **not ready for a broad “everything works across all topologies and all hardware backends” demo**. It is ready for a guided PoC with a narrow script and known-good examples.

## Why These Modules

I treated these as the highly related submodules because they are the ones with direct runtime or handoff coupling to `neurocnl`:

- `Neurosim` depends on `neurocnl` for parsing, validation, support planning, and the canonical preview path.
- `Neurochip` is the downstream deployment target for Teensy and other hardware-facing export/flash flows.
- `Neurobench` directly imports `neurocnl.simulation.run_simulation.run_pipeline` and is the nearest benchmarking consumer.

I did **not** include `Neurohub`, `Neurosense`, or unrelated launcher pieces in the readiness judgment because they are not required to show a credible first PoC for NeuroCNL itself.

## Module-by-Module Status

| Module | Current state | Evidence | PoC demo status |
|---|---|---|---|
| `neurocnl` | Late PoC / pre-beta | mature backend API, deployment gates, large test surface, support matrix is explicit about fidelity | **Yes** |
| `Neurosim` | Demoable but constrained | canonical two-node shared runtime is strong; broader graphs fall back to NeuroSim-local execution and are marked approximate | **Yes, but narrow** |
| `Neurochip` | Demoable for handoff/export/flash paths, uneven elsewhere | Teensy flashing and serial flows are implemented; some analysis and backend routes still contain placeholders or mock behavior | **Yes, if you avoid weak routes** |
| `Neurobench` | Secondary / adjacent, not primary demo anchor | core simulation benchmark flow is real; some routes still use mock or placeholder behavior | **Optional only** |

## Detailed Findings

### 1. NeuroCNL is the strongest part of the stack

What is clearly far along:

- The backend is a real FastAPI app with parse, validate, generate, simulate, export, deploy, job, metrics, and prosthetic routes in `backend/app/main.py`.
- The deploy routes are not just stubs. `backend/app/routers/deploy.py` performs parse -> lower -> contract/planner checks for Teensy, PYNQ, and Akida-facing flows.
- The support claims are relatively honest. `docs/support_matrix.md` explicitly separates `faithful`, `approximate`, and `unsupported`, and documents backend limits instead of claiming universal support.
- The frontend is substantial: `frontend/lib/screens/studio_screen.dart`, `deploy_screen.dart`, `hardware_screen.dart`, and `analysis_screen.dart` are all present and wired through `frontend/lib/routing/app_router.dart`.
- The repo already contains a current internal readiness review at `docs/PRE_BETA_READINESS_REVIEW.md` that places the module in pre-beta territory.

Live verification:

- I ran `neurocnl/.venv/bin/pytest backend/tests/test_health.py backend/tests/test_deploy_endpoints.py tests/test_backend_smoke.py -q`
- Result: **23 passed, 1 skipped**

Important caveats:

- Browser E2E is not locally runnable in the current environment without Playwright. `tests/e2e/test_production_pipeline.py` failed during collection because `playwright` is not installed in `neurocnl/.venv`.
- The current local working tree is ahead of the recorded submodule SHA and includes local issue-archive churn, so this assessment reflects the checked-out workspace, not only the committed submodule state.

Bottom line:

- `neurocnl` is **ready for a PoC demo** if the demo is centered on the `nengo` execution path plus honest hardware readiness checks.

### 2. Neurosim is usable, but only the canonical shared runtime is truly aligned

What is good:

- `Neurosim` directly integrates with `neurocnl` in `neurosim/app/services/neurocnl_bridge.py`.
- The bridge now explicitly reports support fidelity instead of pretending all graphs are equal.
- `docs/neurocnl_runtime_alignment.md` is honest: only the canonical two-node sensory -> motor graph is considered `faithful` on the shared runtime.
- The tests in `neurosim/tests/test_simulation_integration.py` and `neurosim/tests/test_integration.py` are built around this exact canonical path and treat other flows as approximate or unsupported where appropriate.

What limits readiness:

- `neurosim/app/services/neurocnl_bridge.py` explicitly states that the shared `neurocnl` generator path only supports a strict sensory -> motor reflex arc. More complex graphs fall back to NeuroSim-local behavior.
- `preview_runner.py` still uses a local preview model builder outside that narrow topology.
- Export support is mixed: local serializers exist, but the code now correctly downgrades them to approximate rather than treating them as equivalent to shared NeuroCNL-backed export.

Verification gap:

- I could not run the targeted `Neurosim` tests locally because `Neurosim/.venv` exists but does not have `pytest` installed.
- That means the Neurosim readiness call here is based on static code inspection and the visible test suite, not a successful local test execution.

Bottom line:

- `Neurosim` is **ready for a PoC only if you keep the demo on the canonical reflex-style graph**.
- It is **not** ready to stand beside NeuroCNL as a general-purpose, topology-agnostic visual frontend with equal fidelity.

### 3. Neurochip is good enough for a guided hardware-adjacent demo, but not uniformly polished

What is solid:

- `neurocnl` already has a direct Teensy handoff path into Neurochip via `backend/app/routers/deploy.py`.
- Neurochip has real serial and flashing routes in `neurochip/app/routers/serial.py`.
- `neurochip/app/services/flash_service.py` implements async flashing, job polling, upload progress, and optional verification hooks.
- `neurochip/tests/test_hardware_pipeline.py` covers a realistic simulated flow: quantize -> generate firmware -> flash via virtual serial.

What is not finished:

- `neurochip/app/routers/analysis.py` still returns placeholder responses for `/partition` and `/compare`.
- `neurochip/app/services/spinnaker2_backend.py` still contains mock behavior when `py-spinnaker2` is unavailable.
- There are multiple backend paths where the code and tests still lean on mock execution or simulated packaging rather than end-to-end real hardware execution.

Bottom line:

- `Neurochip` is **good enough for a PoC demo focused on Teensy handoff/export/flash**, especially if you have either real hardware ready or are willing to show the simulated flash path.
- It is **not** strong enough yet to present as uniformly production-grade across all hardware targets and analysis routes.

### 4. Neurobench is adjacent and useful, but not core to the first PoC story

What is promising:

- `app/services/benchmark_runner.py` uses `neurocnl.simulation.run_simulation.run_pipeline` for the core simulation target.
- There is a real smoke test in `tests/test_smoke.py` that exercises benchmark execution, job polling, result retrieval, and report generation.

What weakens it as a PoC anchor:

- Several routes and runners still include mock or placeholder behavior, especially around PYNQ and SynSense-related paths.
- The README is thin and does not yet match the maturity of the codebase.
- Relative to `neurocnl`, its story is less focused and less obviously polished for a first demo.

Bottom line:

- `Neurobench` should be treated as an **optional extension** to the demo, not part of the core proof point.

## Readiness Call

### Ready for a PoC demo?

**Yes, with scope control.**

### Ready for a broad public product demo?

**No, not yet.**

## Recommended Demo Scope

This is the safest credible script:

1. Open `neurocnl` Studio and load a known-good example or template.
2. Show parse -> validate -> generate -> simulate using the `nengo` path.
3. Show backend support/fidelity messaging so the audience sees the tool is honest about limits.
4. Show Teensy deployability verdict and handoff payload generation.
5. If hardware is available, continue into `Neurochip` flash/verify.
6. If you want a second screen, show the same canonical graph inside `Neurosim`, but keep it to the sensory -> motor happy path.
7. If you want an appendix/demo tail, show a `Neurobench` simulation benchmark and generated report.

## What Needs To Happen For A Working Demo: Teensy, PYNQ Z2, And Akida

Assumption: "akoda" means **Akida**.

This section is the concrete worklist to get from the current state to a demo I would call operationally credible.

### Definition of "Working Demo"

For each target, the minimum honest bar should be:

- a known-good CNL spec can be validated in `neurocnl`
- the target-specific readiness gate returns the expected verdict
- a target-specific artifact or deployment step completes successfully
- the result can be shown in a way that matches the real capability level of that target

For this repo today, that means:

- **Teensy:** actual end-to-end from NeuroCNL to Neurochip export/flash, ideally on real hardware
- **PYNQ Z2:** export + deploy + status/verify on Neurochip, or clearly labeled simulator-backed runtime if no board is available
- **Akida:** mapped-network/package generation at minimum, and SDK/device verification only if the BrainChip SDK is actually present on a supported host

### Cross-Target Work That Must Happen First

These are shared prerequisites before any of the three target demos are trustworthy:

1. Freeze the exact demo spec set.
   Use one or two known-good feed-forward specs only. Do not improvise with arbitrary CNL during the demo.

2. Freeze the exact demo environment.
   Rehearse on the same workspace and machine image you will demo from. Both `neurocnl` and `Neurosim` currently have local working-tree changes.

3. Decide whether the target demos are:
   real hardware,
   simulator-backed,
   or export/scaffold-only.
   This must be stated explicitly in the script and on any demo slide.

4. Build a preflight checklist and run it immediately before demo day.
   At minimum check:
   - `http://localhost:8000/health` for NeuroCNL
   - `http://localhost:8002/health` for Neurochip
   - API key configuration for Neurochip routes
   - presence of required host tools and SDKs for the specific target

5. Rehearse the full path from the actual operator surface you plan to show.
   Right now the Studio frontend only contains a **Teensy** panel. PYNQ Z2 and Akida are not surfaced as equivalent Studio UI flows.

### Teensy: What Needs To Happen

#### Must-fix before calling the Studio flow working

1. Fix the serial-port response contract mismatch.
   `neurocnl/frontend/lib/services/neurochip_client.dart` expects a wrapped response with `response['ports']`, but `Neurochip/neurochip/app/routers/serial.py` currently returns a bare list from `GET /api/neurochip/serial/ports`.
   As written, that can break the Teensy port picker in the real UI path.

2. Verify the actual Neurochip auth/config path used by the frontend.
   `neurocnl/frontend/lib/config/app_config.dart` depends on `NEUROCHIP_BASE_URL` and `NEUROCHIP_API_KEY`. These must be correct on the demo build.

3. Validate the exact end-to-end path from the Studio UI:
   - CNL spec -> `/api/deploy/teensy/network`
   - Neurochip firmware export -> `/api/neurochip/export/teensy`
   - serial port discovery -> `/api/neurochip/serial/ports`
   - flash start/poll -> `/api/neurochip/serial/flash`

4. Confirm the host toolchain is present on the demo machine.
   `Neurochip/neurochip/app/services/flash_service.py` shells out to `pio`.
   That means PlatformIO must be installed and usable from the runtime environment.

5. If post-flash verification will be shown, install `neurodreamhand`.
   `Neurochip/neurochip/app/routers/serial.py` returns 503 for verification if `neurodreamhand` is absent.

#### Strongly recommended

1. Rehearse on a real Teensy 4.1 at least once.
   The simulated flash path is useful, but it should not be the first time the real hardware path is exercised.

2. Prepare a fallback if USB/serial enumeration is flaky.
   Have a pre-generated firmware ZIP and a prerecorded successful flash/verify run available.

3. Keep the demo spec within the validated Teensy subset.
   Feed-forward LIF only, no recurrent connections, no learning rules, no complex topology.

### PYNQ Z2: What Needs To Happen

#### Biggest current gap

There is no equivalent NeuroCNL Studio PYNQ panel in `frontend/lib`.
So if you want a **working demo from the Studio UX**, you must either:

1. build and wire a real PYNQ panel in NeuroCNL, or
2. explicitly demo PYNQ from API/Swagger/scripted operator tooling instead of pretending the Studio already supports it end-to-end

#### Must-do for a working PYNQ demo

1. Decide the honesty level of the demo.
   The support matrix already says PYNQ is **export-only** and that the FINN compilation pipeline is still Phase 2.
   So the demo should stop at:
   - exportability gating
   - artifact generation
   - Neurochip deploy/status/verify
   It should not claim full FINN-generated FPGA compilation inside NeuroCNL.

2. Choose and surface one operator path.
   Options:
   - add a NeuroCNL frontend flow that uses the existing backend capabilities
   - or run the demo through API calls using the existing backend/Neurochip routes

3. Rehearse the actual PYNQ path you plan to show.
   The backend pieces already exist:
   - `neurocnl/backend/app/routers/deploy.py` for `/api/deploy/pynq/network`
   - `neurocnl/neurocnl/handoff/neurochip_pynq_handoff.py` for NeuroCNL -> Neurochip handoff logic
   - `Neurochip/neurochip/app/routers/pynq.py` for `/hardware/pynq/deploy`, `/status`, and `/verify`

4. Make sure the board-side environment is real if you want a real-hardware claim.
   That means:
   - reachable PYNQ host
   - `pynq` library installed there
   - real `.bit` and `.hwh` overlay available at the configured bitstream path
   - network reachability from the demo machine to the Neurochip service

5. If no real board is available, explicitly label the runtime leg as simulator-backed.
   `Neurochip/neurochip/app/services/pynq_backend.py` falls back to `PynqSimulator` when the `pynq` library is not installed.
   That is good for development, but it is not a real board demo.

6. Add or document a known-good verification case.
   `Neurochip/neurochip/tests/test_pynq_sitl_verify.py` shows that `/hardware/pynq/verify` is already structured around default and custom SITL cases.
   The demo should use a fixed verification payload rather than ad-hoc inputs.

#### Strongly recommended

1. Produce one canonical PYNQ demo script with:
   - CNL spec
   - exportability response
   - deploy call
   - status response
   - verify response

2. Keep the topology minimal and feed-forward.
   Avoid any design that risks planner rejection for unsupported topology or learning-rule semantics.

### Akida: What Needs To Happen

#### Biggest current gap

Just like PYNQ, there is no equivalent NeuroCNL Studio Akida panel in `frontend/lib`.
If the goal is a single polished Studio demo for all three targets, Akida still needs a surfaced user flow.

#### Must-do for a working Akida demo

1. Decide whether this is a scaffold demo or a real SDK/device demo.
   The current backend supports both outcomes:
   - `neurocnl` can return `exportable_scaffold` and a `mapped_network`
   - `Neurochip` can package and verify against the Akida backend
   But a real SDK/device demo only counts if the BrainChip stack is actually present.

2. Use a known-good feed-forward topology only.
   `neurocnl/neurocnl/mapping/akida_mapper.py` currently requires a faithful feed-forward topology for the shared Akida mapping layer.

3. Rehearse the exact mapped-network path.
   The best current path is:
   - call `/api/deploy/akida/network` in NeuroCNL
   - take `mapped_network`
   - call `/api/neurochip/akida/deploy/mapped`
   - call `/api/neurochip/akida/status`
   - optionally call `/api/neurochip/akida/verify`

4. If you want a real SDK/device claim, move the demo host off macOS and confirm the SDK.
   The support matrix already documents that the Akida package is not supported on macOS.
   So a real Akida SDK/device demo should be rehearsed on a supported Linux host.

5. Decide whether you are showing Akida1 or Akida2 and keep the script fixed.
   `neurocnl/backend/app/routers/deploy.py` accepts both `akida1` and `akida2`, but the topology/constraint story differs.
   Do not switch variants live without rehearsal.

6. If the SDK is not installed, label the demo honestly as scaffold/package generation only.
   `Neurochip/neurochip/app/services/akida_backend.py` falls back to `AkidaSimulator` when the `akida` library is absent.

#### Strongly recommended

1. Add one small operator-facing wrapper around the Akida mapped deploy path.
   Even a minimal internal tool or temporary panel is better than manually copying JSON live in front of an audience.

2. Keep inference expectations simple.
   Show packaging, status, and verification first; only show live inference if it has already been rehearsed on the exact hardware/SDK host.

### Prioritised Worklist

If the goal is to get to the fastest believable multi-target demo, the order should be:

1. Fix the Teensy serial-port contract mismatch and re-rehearse the Teensy Studio flow.
2. Freeze one known-good demo CNL spec per target.
3. Decide whether PYNQ Z2 and Akida will be:
   API-driven demos,
   temporary internal tooling demos,
   or fully surfaced Studio demos.
4. Rehearse the PYNQ Z2 path on a real board host or explicitly downgrade it to simulator-backed.
5. Rehearse the Akida path on a supported SDK host or explicitly downgrade it to scaffold/package-only.
6. Build a one-page operator runbook with exact endpoints, environment variables, and fallback steps.

### Net Assessment After This Update

To get a **working Teensy demo**, the remaining work is mostly bug-fixing, environment prep, and rehearsal.

To get a **working PYNQ Z2 demo**, the backend capability is present, but the operator-facing flow still needs to be surfaced and rehearsed.

To get a **working Akida demo**, the mapped/scaffold path is present, but the real SDK/device story still depends on supported-host setup and explicit surfacing in the demo flow.

## What I Would Avoid In The Demo

- Any claim that all parser-recognized concepts are equally runtime-faithful on every backend
- Complex `Neurosim` canvases outside the canonical reflex-arc runtime path
- `Neurochip` analysis `/partition` and `/compare` routes
- Any backend path that is explicitly marked approximate, export-only, broken, or unsupported unless you present it as roadmap rather than shipped capability
- Browser E2E or frontend test claims unless Playwright is installed and verified locally first

## Main Risks Before Demo Day

- `Neurosim` and `neurocnl` both have local working-tree changes right now, so the demo should be rehearsed against this exact workspace rather than assumed from submodule SHAs alone.
- `neurocnl` frontend navigation currently disables non-Studio destinations when MuJoCo is unavailable in `frontend/lib/routing/app_router.dart`; that can affect the smoothness of the UI walkthrough if the environment is missing that dependency.
- `neurocnl/frontend/lib/providers/hardware_provider.dart` still contains placeholder sensor polling behavior rather than a real live stream implementation.
- Local browser-driven E2E verification is incomplete because Playwright is not installed in the current `neurocnl` venv.

## Final Verdict

`neurocnl` is **far enough along to support a credible PoC demo now**.

The demo should be positioned as:

- a strong end-to-end PoC centered on CNL authoring, validation, simulation, and constrained deployment handoff

It should **not** be positioned as:

- a fully generalized, uniformly mature, all-backend neuromorphic suite

If you keep the narrative tight and stay on the strongest paths, the demo should hold up.
