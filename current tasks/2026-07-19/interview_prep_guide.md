# NeuroMorphicToolKit — Interview Prep Guide

Study this once, out loud, before the interview. Every fact below traces to a real file, commit, or doc in the repo — no invented details.

---

## 1. The 30-second pitch

NeuroMorphicToolKit (NMTK) is a native Flutter desktop/mobile app that acts as a thin client over a consolidated Python/FastAPI backend suite ("Backend-as-a-Service") for designing, training, benchmarking, and deploying **spiking neural networks (SNNs)** to real neuromorphic hardware — Intel Loihi, BrainChip Akida, PYNQ-Z2, Teensy microcontrollers, and SynSense Speck.

The core differentiator: a **Controlled Natural Language (CNL) compiler**. Instead of hand-writing a network in a framework, you write plain-English-like constraint statements (`"The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"`), and the compiler lowers that directly to a `nir.NIRGraph` (Neuromorphic Intermediate Representation) — no intermediate simulator network is built. From there the graph can be trained in snnTorch, benchmarked against the NeuroBench standard, and deployed to physical hardware.

**One-liner if pressed further:** "It's a CNL-to-hardware pipeline for spiking neural networks, wrapped in a Flutter app that manages a FastAPI backend suite — think of it as a compiler + IDE + deployment tool for neuromorphic computing."

---

## 2. System map

```
Flutter Launcher (nmtk/neuro_toolkit)
  - GoRouter: ShellRoute -> MainScreen
  - Most module routes redirect into one generic /workspace?moduleId=... route (ToolViewScreen)
  - Riverpod for state (AsyncNotifierProvider / NotifierProvider / FutureProvider.autoDispose)
        |
        v
suite_api (single FastAPI process)
  - One domain router per module: /api/{neurocnl,neurosim,neurochip,neurobench,neurosense,neurohub,jupyter}
  - Each domain is either:
      (a) served in-process (imports the module's own backend package directly), or
      (b) proxied to an isolated worker container via proxy_to_worker()
  - proxy_to_worker() returns a structured 503 (never crashes) if a worker is down/unreachable
        |
        v
Optional isolated workers (only spun up if needed)
  - neurocnl-physics-worker (MuJoCo), neurochip-hw-worker, neurosense-hw-worker,
    neurobench-runner-worker, lava-backend, jupyter-server, snn-mlir-compiler
```

**Why this shape matters:** the backend used to be separate per-module microservices; it was consolidated into one FastAPI monolith with domain routers, while keeping only the genuinely heavy or hardware-dependent work (physics sim, real hardware I/O, long ML training jobs) in separate worker containers. That's a deliberate "monolith for the cheap stuff, isolate the expensive/optional stuff" split — not an accident of growth.

**`modules.json` (`nmtk/neuro_toolkit/assets/modules.json`) is the single source of truth.** It's a flat array of module descriptors — id, port, install strategy, `hasFrontend`, `showInLauncherNav`, hardware runtime metadata (SSH/venv details for PYNQ/Akida pairing), deployment mode support (standalone/docker/kubernetes). Every module's Dart model, launcher nav visibility, and deploy config is driven off this one file. The project's own style guide states explicitly: "never change only one copy" — a change to a module's port/path has to be updated in `modules.json`, the Dart models, compose files, and CI scripts together, in the same commit.

---

## 3. Module tour (know one distinguishing fact per module)

| Module | What it does | One fact to remember |
|---|---|---|
| **neurocnl (NeuroStudio)** | Owns the CNL→IR→NIR compiler; the primary authoring surface | Compiles straight to `nir.NIRGraph` — deliberately does **not** construct an intermediate Nengo network |
| **Neurosim** | Visual graph/canvas workspace for SNN design | Not a standalone launcher entry anymore — its canvas is embedded inside neurocnl/Studio at `/canvas` |
| **Neurochip** | Hardware execution/"Sim-to-Real" layer — flashing, diagnostics for Loihi/Akida/PYNQ/Teensy/Speck | Has no standalone frontend (`showInLauncherNav: false`); its UI is served through neurocnl's shell adapter. Also has an SSRF-hardened allowlist (`NEUROCHIP_AKIDA_ALLOWED_HOSTS`) guarding remote hardware dispatch |
| **Neurobench** | Standardized benchmarking, wraps the external NeuroBench.ai standard | Long-running benchmark jobs are offloaded to a dedicated `neurobench-runner-worker` |
| **Neurosense** | "Sensory Cortex" — converts analog signals (EMG, vision, audio) into spike trains | Real DSP: Butterworth bandpass/notch filtering via scipy (`filter_pipeline.py`) feeding rate/temporal/delta spike encoding with refractory-period enforcement |
| **Neurohub** | Community registry ("GitHub for Spiking Networks") for models/datasets/baselines | The only module with a real relational DB — SQLAlchemy 2.0 typed `Mapped[...]` models + Alembic migrations |
| **Neuro-Dream-Hand** | Thesis-grade reference app: Nengo + MuJoCo adaptive SNN control of a physics-based prosthetic hand | Not a core launcher module — pulled in as a Python dependency by neurocnl for integrated pipelines |
| **nmtk (launcher)** | The Flutter shell app itself | Owns `nmtk/packages/{neurochip_feature,neurosim_feature}` and `launcher_control` |
| **nmtk_ui_core** | Shared Flutter design-system package | Deliberately **state-management-agnostic** — no Riverpod/Provider import allowed inside it, enforced by its own AGENTS.md and ADRs |

---

## 4. Tech stack cheat sheet

| Layer | Stack |
|---|---|
| Frontend framework | Flutter (Dart SDK ≥3.6, `nmtk_ui_core` needs ≥3.11), native macOS/iOS/Android — **not a web app** |
| State management | Riverpod (`flutter_riverpod ^3.3.1`) with `riverpod_generator`/`freezed` codegen, used consistently suite-wide — no plain `provider` package anywhere |
| Routing | GoRouter `^14.0.0`, single `ShellRoute`, generic `/workspace?moduleId=` pattern + explicit redirects for merged modules |
| Design system | Zeta Flutter (`zeta_flutter`) — raw Material widgets and hardcoded colors banned except two grandfathered files |
| Backend framework | FastAPI (`suite_api`, Python ≥3.11), Pydantic v2 (`>=2.7`), `pydantic-settings`, `slowapi` rate limiting |
| Database | SQLAlchemy 2.0 typed models + Alembic migrations (Neurohub only; other modules use JSON/file-based persistence) |
| ML/neuromorphic stack | `nir` (NIR graph format), `snntorch`, `torch`, optional extras: `nengo-loihi`, `lava-nc`, `sinabs`+`rockpool` (SynSense), `norse`, `akida`/`akida-models`/`cnn2snn` (BrainChip), `mujoco` |
| Testing | `pytest` + `pytest-asyncio` (auto mode) + `pytest-cov` + `hypothesis` (property-based testing) + `mypy --strict`; Flutter: `flutter_test`, `integration_test`, `mocktail` |
| Deployment | Docker Compose (base/dev/prod/webtop variants), Prometheus + Grafana + Loki + Promtail + Alertmanager observability stack baked into `docker-compose.yml` |
| Remote dev deploy | `make docker-ex-m REMOTE_HOST=user@host` — rsyncs uncommitted local changes, rebuilds `suite_api` via `docker compose up --build` remotely, launches the local Flutter macOS app pointed at that host |

---

## 5. Design decisions worth defending

**Backend consolidation: microservices → one FastAPI monolith with domain routers.**
What: the codebase's own health-router comments state "after consolidation the standalone module services no longer exist; all domains run inside suite_api itself." Why: fewer moving parts, one process to deploy/monitor, while genuinely heavy/optional work (physics sim, hardware I/O, long training jobs) still lives in separate worker containers reached through a shared `proxy_to_worker()` helper. Tradeoff: you give up per-module independent scaling/deploy, but for a project this size that complexity wasn't paying for itself — the workers exist exactly where isolation actually matters (crash blast radius, heavy deps, hardware access).

**`nmtk_ui_core` kept state-management-agnostic.**
What: the shared design-system package is not allowed to import Riverpod or Provider — it exposes callback-based APIs only, enforced by its own AGENTS.md and backed by ADRs (`0001-barrel-export-pattern.md`, `0003-zero-state-management-dependency.md`). Why: it's consumed by every module frontend; coupling it to one state-management choice would force every consumer into that choice or fork the package. Tradeoff: some call sites need a thin wrapper to bridge Riverpod state into the widget's callback API, but the design-system package stays reusable and testable in isolation.

**Optional-runtime rule: hardware/ML deps degrade, never crash.**
What: MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker imports are wrapped in `try/except ImportError` and conditionally mounted; if a worker is unreachable, `proxy_to_worker()` returns a structured 503 instead of the whole service crashing. Why: this is a desktop app installed on end-user machines with wildly different hardware available — a missing SDK for hardware you don't own must not take down the rest of the app. Tradeoff: more defensive plumbing throughout the codebase, but it's what makes "works on my machine without a Loihi board" possible at all.

**CNL compiler targets NIR directly, skipping an intermediate Nengo network.**
What: earlier in the project's life the compiler likely built a Nengo network as an intermediate step; now it lowers CNL straight to `nir.NIRGraph`. Why: NIR is the actual interchange format that downstream training (snnTorch) and hardware backends consume — building a Nengo network first was an unnecessary hop. Tradeoff: less reliance on Nengo's own simulation semantics, more of the compiler's own logic to get right, but a cleaner, faster, more portable pipeline.

---

## 6. War stories — pick 3-4 to have ready, told in your own words

### Story A: The 6.3GB log file that never stopped growing
While debugging system-wide memory pressure/freezes, the investigation found `launcher_backend_activity.log` had grown to **6.3GB across 4.9 million lines** — every control-API call appended to it with no cap, no rotation. That much file kept resident by page cache and indexed by Spotlight was a very plausible explanation for the sluggishness. Fix: a self-healing rotation — once the file crosses 5MB, trim it back down to 2MB. **Why it's a good story:** it's a "found a real incident on my own machine, diagnosed the actual mechanism (not just 'restart fixed it'), and built a mechanism so it can't recur" narrative — production-log-hygiene thinking, not a feature.

### Story B: Every module mounting at once on desktop, because of a breakpoint bug
The mobile layout picked its rendering path by window width alone (`isMobile = width < 840`), and the mobile branch used an `IndexedStack` that keeps **every** module mounted and alive simultaneously — each one a full nested MaterialApp + router + provider tree, one of them with a real embedded WebView for Jupyter. The catch: the macOS app's default window size (800×600) is *narrower* than the 840px breakpoint, so **every desktop launch silently took the "mobile" fan-out path** and mounted every module at once. Fixed both sides: corrected the layout logic so only the visible module builds, and raised the macOS default window to 900×650 so it can't fall under the breakpoint again. **Why it's a good story:** it's a genuinely subtle cross-platform bug — the responsive-breakpoint logic was "correct" in isolation, but the platform default window size silently put desktop through the wrong path. Good example of reasoning about interacting assumptions across layers (UI logic + native window config).

### Story C: A poll-overlap fix that wasn't actually complete
First pass fixed `Timer.periodic` pollers (deployment-job polling every 1s, module-refresh every 3s) that fired a new request every tick regardless of whether the previous one had finished, plus a shared HTTP client with no timeout — together, a hung backend could let requests pile up unbounded. Added an in-flight guard and a 10s timeout. On follow-up audit, found the guard was incomplete: it only checked at the timer callsite, not inside the actual polling function itself, so **six separate module actions could still overlap**, and extended timeouts to four more service files that were missed the first time. **Why it's a good story:** shows the discipline of auditing your own fix rather than declaring victory after the first patch — a good answer to "tell me about a time you caught your own mistake."

### Story D: All-zero placeholder weights silently killing training (neurocnl)
A CNL-authored layer without explicit `weight_init` metadata intentionally compiles to an all-zero weight matrix as the compiler's documented default. The codegen step, however, unconditionally wrote that compiled weight array onto the PyTorch layer — overwriting PyTorch's own sane random initialization with exact zeros. Every gradient path multiplied through zero, so the network never learned at all: loss frozen exactly at `ln(num_classes)` (the value for a totally uniform/random output), spike rate stuck at 0.0. The diagnostic signal (a suspiciously exact, unmoving loss value) is what pointed at initialization rather than a training-loop bug. Fix: skip the weight assignment when the compiled weight is all-zero, so PyTorch's default init is left alone. **Why it's a good story:** it's a genuine "two correct pieces of code interact to produce a wrong result" bug — the compiler default was correct, the codegen was correct in the general case, but the specific combination was silently catastrophic. Good ML-debugging methodology talking point (recognizing `ln(num_classes)` as a diagnostic signature).

### Story E (optional, use if asked about ML rigor specifically): The Braille-RNN regression from stacking changes
While replicating a reference Braille-recognition RNN notebook, changing three hyperparameters at once (more epochs, switching Adam→AdamW with weight decay, a harsher LR scheduler) caused accuracy to *regress* from a working 80% down to 67.86%. The regression was explicitly flagged as a process mistake — it broke a previously-established "one variable at a time" discipline. The investigation kept a full chronological accuracy table with root causes for each swing, including one bug traced to bias-construction-order causing RNG-stream drift versus the reference (verified byte-for-byte against reference weight init), and used A/B isolation to confirm `shuffle=True` alone was the harmful change. Also documented, rather than hid, that the reference notebook's claimed 92% accuracy is actually unreachable on current snntorch (1.0.0) due to a breaking API change. **Why it's a good story:** demonstrates rigorous, honest ML-debugging methodology — single-variable isolation, byte-level verification, and transparent documentation of a limitation rather than fudging the numbers.

---

## 7. How to talk about "I used AI agents to build this"

Don't undersell it and don't apologize for it — frame it as the engineering practice it actually is, with evidence:

- **Isolated per-task branches, consolidated deliberately.** The repo has 130+ agent branches following a `agent/issue-N-<topic>` naming convention, each scoped to one issue/feature, periodically reviewed and merged into `dev` rather than committed directly to a shared branch. That's a real branching discipline, not "let the AI commit whatever."
- **Conventions enforced on every change, not just written down.** `AGENTS.md` and `CODING_STYLE_GUIDE.md` encode real constraints (module boundary rules, "never change only one copy" for metadata, optional-runtime degradation rules, banned anti-patterns), and there are dedicated review skills (Flutter and Python) that audit every change against an explicit scored rubric before it lands.
- **CI does real verification, including agent-authored CI.** Workflows exist for cross-module contract tests, a golden-path test, and a Teensy end-to-end hardware pipeline test — these aren't rubber-stamp checks, they exercise real integration surfaces.
- **Your actual job in this workflow:** architecture calls (monolith vs. microservices, where to draw the optional-runtime line), reviewing and directing the agent's output, root-causing the bugs above, and making the judgment calls about what ships. That's the same job a senior engineer does directing a team — the tool changed, the responsibility didn't.

If pushed on "so what did *you* actually write": you can honestly say you made every architectural decision above, diagnosed the war-story bugs (or directed and verified the diagnosis), and are the one who can explain *why* every part of this system is shaped the way it is — which is the bar that matters in review, not raw line count.

---

## 8. Anticipated questions + short model answers

**Q: Why a FastAPI monolith instead of per-module microservices?**
A: It used to be per-module services; we consolidated because most domains are cheap and don't need independent scaling or deployment — one process is simpler to run and monitor. We kept the genuinely heavy/hardware-dependent work (physics sim, real hardware I/O, long training jobs) in separate worker containers reached through a shared proxy helper, so isolation exists exactly where it earns its cost.

**Q: What happens if a user doesn't have the hardware SDK installed (e.g., no PYNQ board)?**
A: Every optional hardware/ML dependency is imported behind a try/except and the router only mounts if the import succeeds; if a request needs a worker that's down or a dependency that's missing, the backend returns a structured error (503) instead of crashing the whole service. The launcher also reports per-module health (`online`/`degraded`/`offline`) so the UI can reflect it.

**Q: What's the hardest bug you (or your agent) fixed, and how did you find it?**
A: (Use Story D or B above — the all-zero-weight training freeze or the macOS breakpoint bug are both strong "two correct things interact badly" answers with a clear diagnostic signal.)

**Q: Why Riverpod instead of Provider or Bloc?**
A: Riverpod is used consistently across every module frontend, with codegen (`riverpod_generator`) for compile-time-safe providers. It also let us keep the shared design-system package (`nmtk_ui_core`) completely state-management-agnostic — it exposes callback-based APIs and never imports Riverpod itself, so the choice of state management doesn't leak into shared UI code.

**Q: How do you keep 9 submodules from drifting out of sync?**
A: `modules.json` is the single declared source of truth for module metadata (ports, install paths, deployment mode); the style guide is explicit that a change to one copy (Dart models, compose files, CI scripts) requires updating all of them in the same commit. Cross-module contract changes also require running the integration test suite before merging.

**Q: Why does the CNL compiler skip building a Nengo network?**
A: NIR is the actual interchange format that downstream training and hardware backends consume, so lowering straight from CNL to NIR removes an unnecessary intermediate step and keeps the pipeline faster and more portable across backends.

**Q: What's a design decision you'd reconsider or do differently?**
A: (Good honest answer, grounded in real repo evidence) Some frontends were pulled in as native Flutter path dependencies while others are compiled and served as static web builds through the backend — that's a mixed embedding strategy that's worth unifying. There's also a known doc/reality drift flagged in the repo itself (e.g., a module listed as consuming the shared design-system package that actually has an empty placeholder directory) — the project deliberately leaves these flagged in place rather than silently smoothing them over, which is honest but is also backlog that should get resolved.

**Q: How do you test something this hardware-dependent?**
A: Property-based testing (hypothesis) alongside standard pytest, `mypy --strict` for type safety, and integration tests that gracefully skip (rather than fail) when a required Docker-orchestrated service isn't reachable — so hardware-dependent paths stay covered without requiring physical hardware to be present in CI.

**Q: What was the actual "sim-to-real" pipeline you're proudest of?**
A: A CNL constraint spec parses and lowers through neurocnl, gets exported by Neurochip to a specific hardware target (e.g., Teensy firmware), with explicit rejection tests for things the target genuinely can't support — oversized networks, recurrent connectivity, spike-timing-dependent plasticity. That's real domain-constraint enforcement, not generic CRUD.

---

*Source: three research passes over the live repo (architecture, code-level patterns, and git history) conducted 2026-07-19. All commit hashes, file paths, and figures above were found directly in the repository at that time — verify against current `git log`/`git show` if any commit has since been rebased or squashed.*
