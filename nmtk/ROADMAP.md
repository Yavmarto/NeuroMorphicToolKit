# Neuro-space Suite Roadmap
**Updated:** 2026-03-15
**Mission:** Lower the barrier to entry for professionals building neuromorphic products.

**Target users:** Engineers, neuroscientists, hardware designers, and domain specialists who are skilled in one field (e.g., embedded systems, computational neuroscience, signal processing, chip design) but need to work across the full neuromorphic product stack — from biological models to silicon deployment. The suite bridges the gaps between these disciplines so that a hardware engineer doesn't need a neuroscience PhD to design an SNN, and a neuroscientist doesn't need embedded expertise to deploy one.

---

## Current Suite

| App | Purpose | Status |
|---|---|---|
| **neurocnl** | CNL spec language + validator + Nengo code generator + FastAPI backend + Flutter IDE | v0.3.0 — merged & feature-complete |
| **Neuro-Dream-Hand** | SNN prosthetic hand controller with MuJoCo physics, PES learning, hardware export | Phases 1-3 complete, 4-5 software-complete |
| **servo_control** | Teensy firmware for servo actuation | Sketch complete |

---

## ✅ Phase 1 — Complete the Merge (DONE)

All 34 tasks from `Merge_maintain.md` completed:

- [x] Backend integration — 5 prosthetic routers mounted (`/api/prosthetic/*`: simulate, sleep, export, analysis, hardware)
- [x] Frontend integration — go_router + NavigationRail with 4 screens (Studio, Deploy, Hardware, Analysis)
- [x] Maintenance tasks — ruff/mypy, TypedDict, pipeline collapse, request_id middleware, job system, rate limiting, endpoint tests (33 backend tests), SECURITY.md
- [x] Unified Docker deployment — `docker-compose up` with non-root containers, externalized API URL

**Outcome:** One app, one backend, one frontend. The neurocnl IDE can design, simulate, deploy, and analyze SNNs end-to-end.

---

## ✅ Phase 2 — Library Feature Completion (DONE)

All 6 sub-items implemented. 305 core library tests passing.

### 2a. STDP Learning Rules in CNL ✅
BCM, Oja, and PES learning rules with explicit rate/BCM/Oja CNL patterns, generator routing, Layer 1 invariants (learning_rate_positive, learning_rule_valid), assertion templates. 17 tests.

### 2b. Spike Encoding Utilities ✅
`spike_encoding.py` with `rate_encode()`, `temporal_encode()`, `delta_encode()`. 15 tests.

### 2c. Multi-Population Network Topology ✅
Dynamic population graph building in generator, arbitrary neuron names in parser, orphan population detection in Layer 2 validator, backward-compatible aliases. 16 tests.

### 2d. Visualization Tools ✅
`visualization.py` with spike raster, membrane traces, network topology, weight evolution, HTML export. Optional `matplotlib` dependency (`pip install neurocnl[viz]`). 14 tests.

### 2e. Extended CNL Grammar ✅
13 CNL concepts total (up from 8): added lateral inhibition, homeostatic plasticity, neuromodulation, population coding range. Full pipeline for each (parser → invariant → generator → assertion). 25 tests.

### 2f. Export Formats ✅
5 exporters: NeuroML, C header, NengoLoihi, Lava, SpiNNaker + unified `export()` dispatcher. 23 tests.

---

## ✅ Phase 3 — Hardware Demos (DONE)

All 6 portfolio demos implemented with enhanced CNL specs, Python demo scripts, Teensy firmware, and tests. 78 demo tests passing.

| # | Demo | Files | Tests |
|---|---|---|---|
| 1 | ✅ Gripper reflex on Teensy | CNL + run_demo.py + firmware/gripper_reflex.ino | 8 |
| 2 | ✅ Classical conditioning | CNL + run_demo.py + firmware/classical_conditioning.ino | 16 |
| 3 | ✅ EMG prosthetic w/ Ganglion | CNL + run_demo.py + firmware/emg_prosthetic.ino | 13 |
| 4 | ✅ Habituation/sensitization | CNL + run_demo.py + firmware/habituation.ino | 14 |
| 5 | ✅ BCI neurofeedback | CNL + run_demo.py + firmware/bci_neurofeedback.ino | 12 |
| 6 | ✅ Tactile explorer robot | CNL + run_demo.py + firmware/tactile_explorer.ino | 15 |

Each demo: enhanced CNL spec (8-10 lines using STDP, weight bounds), pipeline script (parse→validate→generate→export), Teensy firmware with on-device SNN, and pytest suite. Hardware deployment requires physical components (~€108 total).

---

## ✅ Phase 4 — Maintenance Automation (DONE)

From `maintenance-improvement.md`. Automate dependency management, security, code quality, and CI/CD gaps before expanding the suite.

### 4a. Dependabot Configuration
Create `.github/dependabot.yml` for weekly Python/Dart/Docker/Actions dependency update PRs. Groups minor/patch updates.

### 4b. Security Scanning
- **pip-audit** in CI for Python dependency vulnerability detection (both projects)
- **Trivy** scan on Docker images before release
- **CodeQL** analysis for Python/JavaScript (weekly + on push to main)

### 4c. Pre-commit Hooks
Create `.pre-commit-config.yaml`: trailing whitespace, ruff lint+format, mypy, markdownlint, detect-secrets. Local enforcement mirrors CI.

### 4d. Codecov Dashboard
Create `codecov.yml` with project target 60%, patch target 70%, per-flag coverage (neurocnl, ndh, flutter). PR diff comments.

### 4e. Conventional Commits & Changelog
- `.commitlintrc.yml` + `commitlint.yml` workflow enforcing `type(scope): description` format
- `cliff.toml` + git-cliff for auto-generated `CHANGELOG.md` on release

### 4f. Version Management
`python-semantic-release` for automated version bumping from conventional commit types (feat→minor, fix→patch, BREAKING→major).

### 4g. Documentation Generation
Sphinx + autodoc + napoleon for auto-generated API docs. Deploy to GitHub Pages via CI.

### 4h. Docker Build Verification
CI job: build both Docker images + `docker compose up` + `curl /health` smoke test. Catches broken Dockerfiles before release.

### 4i. Arduino/PlatformIO CI
`arduino-ci.yml` — compile-check `servo_control/` and `demos/*/firmware/` sketches against Teensy board definition.

### 4j. Branch Protection
Configure via GitHub UI: require CI checks (neurocnl, NDH, flutter, security, commitlint), 1 review, linear history, no force pushes. *(Manual step — not automatable via code.)*

**Delivered:** 7 CI workflows (python_ci, flutter_ci, codeql, commitlint, docs, docker-ci, arduino-ci), Dependabot for 6 ecosystems, pre-commit hooks, codecov config, cliff.toml changelog, semantic-release config, Sphinx docs scaffold. Version bumped to v0.3.0. 383 tests passing.

---

## ✅ Phase 5 — Distribution & Packaging (DONE)

From `user-install-improvement.md`. Download → run → done experience.

### 5a. GitHub Releases + Multi-Platform CI Builds ✅
`release.yml`: 5 backend Nuitka targets (linux/macos x86_64+arm64, windows), 3 Flutter desktop builds, web build, NDH builds. `softprops/action-gh-release` creates release with all artifacts.

### 5b. Docker Image Publishing ✅
`docker-publish.yml`: Multi-arch (`amd64`/`arm64`) push to `ghcr.io` for backend + frontend on tag.

### 5c. PyPI Publishing ✅
`pypi-publish.yml`: Trusted Publishing (OIDC) for `neurocnl` and `neurodreamhand`. No API tokens needed.

### 5d. Desktop App Installers ✅
- `installer/macos/create-dmg.sh` — DMG packaging
- `installer/windows/setup.iss` — Inno Setup script
- `installer/linux/appimage.sh` + `.desktop` + `AppRun` — AppImage packaging

### 5e. Unified Setup Script ✅
`scripts/setup.sh` (macOS/Linux) + `scripts/setup.ps1` (Windows): detect platform, download from GitHub Releases, extract to install dir.

### 5f. First-Run Configuration UX ✅
`server_setup_screen.dart` + `server_config_provider.dart` + `server_config_service.dart`: auto-discover localhost, manual URL, health check, shared_preferences persistence, GoRouter redirect gate, settings gear icon.

**Delivered:** 3 CI workflows (release, docker-publish, pypi-publish), 5 installer scripts, 2 setup scripts, 3 Flutter files (screen + provider + service). 383 tests passing.

---

## Phase 6 — Neuro-space Suite Expansion

New tools for the suite. Each addresses a specific gap in the neuromorphic product development workflow where a professional skilled in one domain (neuroscience, embedded systems, signal processing, chip design) is blocked by unfamiliarity with another.

All apps share the neurocnl core library, FastAPI backend, and Flutter design system.

---

### 6a. NeuroSim — Visual Network Design & Simulation Workbench
**Gap addressed:** Hardware engineers and signal processing specialists who understand systems design but don't have the computational neuroscience background to author SNN architectures from scratch.

A drag-and-drop visual workbench for designing, parameterizing, and simulating spiking neural networks — without writing CNL specs or Python code.

**Core features:**
- **Drag-and-drop canvas:** Place neuron populations, draw connections, configure parameters via property panels. No code, no spec syntax to learn.
- **Component library:** Pre-built, validated blocks — LIF population, STDP synapse, spike encoder, reflex arc, CPG oscillator, winner-take-all, lateral inhibition. Each block documents its biological basis and typical use cases, so a hardware engineer understands *why* this topology exists.
- **Real-time simulation preview:** See spike activity update live as you modify the network. Immediate feedback loop — change a time constant, watch the raster plot respond.
- **Bidirectional CNL sync:** The visual graph generates CNL specs automatically. Engineers who later need to version-control or script their designs can work in CNL directly. CNL edits update the graph.
- **Constraint checking:** Real-time Layer 1 validation as you build — the canvas flags biologically invalid parameters (e.g., negative time constants, inhibitory weights on excitatory connections) before you simulate.
- **Parameter sweep mode:** Select a parameter range, run N simulations, compare results in a grid. Useful for tuning without deep neuroscience intuition.
- **Export:** To CNL spec, Nengo Python, NeuroML, C header (for Teensy), network diagram SVG/PNG.

**Technical approach:**
- Flutter frontend with a custom canvas widget for node-edge graph editing
- Graph representation mapped bidirectionally to/from CNL parse trees
- Uses neurocnl backend for validation (`/api/validate`) and simulation (`/api/simulate`)
- Force-directed layout algorithm for auto-arrangement
- Component library defined as JSON manifests — extensible by users

**Target user example:** An embedded systems engineer at a robotics company needs to design a reflex controller for a gripper. They know PID control, they know C firmware, but they've never designed an SNN. They open NeuroSim, drag a "Reflex Arc" template onto the canvas, adjust the gain and time constants in the property panel, simulate it, export a C header, and flash it to their Teensy. No neuroscience PhD needed.

---

### 6b. NeuroChip — Hardware Deployment & Compilation Toolkit
**Gap addressed:** Neuroscience researchers and SNN algorithm developers who can design networks in simulation but have no experience with chip architectures, weight quantization, memory constraints, or firmware toolchains.

A dedicated tool for compiling, constraining, and deploying SNN models to neuromorphic chips and embedded microcontrollers.

**Core features:**
- **Target selector:** Teensy 4.1, Intel Loihi 2, BrainChip Akida, SpiNNaker, BrainScaleS. Each target includes a hardware profile: neuron capacity, supported neuron models, bit-width, on-chip memory, I/O constraints.
- **Automatic constraint analysis:** Load a network, select a target → get a compatibility report. "This network has 5000 neurons with 32-bit weights. Loihi 2 supports it natively. Teensy requires partitioning to 4 sub-networks of ~200 neurons each with 8-bit quantized weights."
- **Weight quantization explorer:** Interactive bit-width vs. accuracy tradeoff curves. Adjust quantization, see accuracy degradation in real time. Compare 4-bit/6-bit/8-bit side by side.
- **Fault tolerance analysis:** Inject dead neurons, stuck-at faults, weight noise — preview how the deployed network behaves under realistic hardware failure modes before committing to silicon.
- **One-click firmware generation:** CNL spec → C header with LIF update loop + weight arrays → compile and flash to Teensy via serial.
- **Loihi compilation pipeline:** CNL spec → Nengo model → NengoLoihi compilation → NxSDK deployment package.
- **Power & latency estimator:** Estimated energy per inference (pJ/spike-op) and worst-case latency based on network topology and target hardware profile. Compare across targets.
- **Deployment log:** Track what model was deployed to which device, when, with what parameters. Reproducibility for hardware testing.

**Technical approach:**
- Extends the neurocnl FastAPI backend with chip-specific compilation routes
- Flutter frontend with hardware-specific configuration panels and comparison views
- Serial communication via backend; WebSerial as stretch goal for browser-direct flashing
- Builds on existing `crossbar_exporter.py`, `loihi_exporter.py`, `teensy_exporter.py`, `fault_injector.py`, `power_profiler.py`
- Hardware profiles defined as JSON manifests — community can contribute profiles for new chips

**Target user example:** A computational neuroscience postdoc has a working SNN for sensorimotor control in Nengo. Their lab just got access to a Loihi 2 board. They've never touched NxSDK or thought about weight quantization. They load their network into NeuroChip, select "Loihi 2", see that their 32-bit weights need quantization to 8-bit, use the explorer to verify <2% accuracy loss, run fault injection to confirm robustness, and export a deployment package. The toolchain complexity is handled for them.

---

### 6c. NeuroSense — Biosignal Acquisition & Spike Encoding Toolkit
**Gap addressed:** Embedded engineers and chip designers who need real biological input signals for their neuromorphic systems but have no experience with biosignal acquisition, electrode placement, filtering, or neural encoding.

A unified tool for acquiring, processing, spike-encoding, and piping biosignals (EMG, EEG, EOG, ECG) into the Neuro-space pipeline.

**Core features:**
- **Device manager:** Auto-detect and connect to OpenBCI Ganglion/Cyton, Muse, BITalino, and generic serial ADCs. Guided setup with electrode placement diagrams and impedance checks.
- **Live signal viewer:** Real-time multi-channel waveforms with configurable bandpass filters, notch filters (50/60 Hz), and artifact rejection. Each signal type (EMG, EEG, EOG) has sensible filter presets so a non-specialist gets clean data immediately.
- **Spike encoding dashboard:** Side-by-side view: raw analog signal → filtered signal → spike train. Three encoding methods (rate, temporal, delta modulation) with real-time parameter tuning. The user sees exactly how their encoding choices affect spike output.
- **Application presets:** Pre-configured acquisition + encoding pipelines for common use cases:
  - "EMG for prosthetic control" — 20-450 Hz bandpass, envelope extraction, rate encoding
  - "EEG alpha band for BCI" — 8-13 Hz bandpass, power spectral density, threshold encoding
  - "EOG for gaze tracking" — DC-coupled, delta modulation
  - "Tactile sensor array" — multi-channel delta encoding for event-driven touch
- **Recording & session management:** Record sessions with event annotations ("subject flexed wrist at t=3.2s"), save as HDF5 or CSV, replay into neurocnl pipeline for offline development.
- **Signal quality dashboard:** Per-channel SNR, impedance trends, noise floor. Helps non-specialists identify bad electrodes or environmental interference.
- **Direct pipeline integration:** One-click route live or recorded data into `/api/simulate` as spike-encoded input. The encoded spike train becomes the input to whatever SNN is loaded in the Studio.

**Technical approach:**
- Backend wraps BrainFlow SDK (already planned in `brainflow_adapter.py`)
- Spike encoding reuses the `spike_encoding.py` module from Phase 2b
- Flutter frontend with real-time charting (reuses `SensorTimeSeriesChart` pattern)
- WebSocket streaming for live data from backend to frontend
- Can run headless on Raspberry Pi for portable/wearable biosignal capture rigs

**Target user example:** A chip design engineer at a neuromorphic startup needs to test their new ASIC with real EMG input. They know digital design and Verilog, but they've never placed an electrode or filtered a biosignal. They connect an OpenBCI Ganglion, select "EMG for prosthetic control" preset, verify signal quality on the dashboard, and pipe the spike-encoded output directly into NeuroChip for deployment testing. The biosignal expertise is embedded in the presets.

---

### 6d. NeuroBench — Test & Benchmarking Workbench
**Gap addressed:** Teams building neuromorphic products who need to systematically test, benchmark, and compare SNN designs across different hardware targets, encoding strategies, and network configurations — but lack standardized tooling to do so.

A testing and benchmarking workbench for evaluating SNN performance across the full stack: algorithm accuracy, hardware efficiency, robustness, and real-world signal fidelity.

**Core features:**
- **Benchmark suite runner:** Run standardized neuromorphic benchmarks against any neurocnl-generated network. Built-in benchmark tasks: grip stability, spike classification accuracy, reaction latency, wake-word detection, pattern recognition. Results normalized for cross-comparison.
- **Cross-target comparison:** Run the same network on Nengo (CPU simulation), Teensy (embedded), Loihi 2 (neuromorphic chip) — compare accuracy, latency, energy, and spike fidelity side by side. Answers: "How much do I lose by going from float32 simulation to 8-bit hardware?"
- **Encoding strategy comparison:** Same input signal, multiple encoding methods (rate, temporal, delta) — which encoding preserves the most task-relevant information for this specific network? Visual comparison with accuracy metrics.
- **Regression testing:** Save benchmark results as baselines. After modifying a network or changing hardware parameters, re-run and get a diff: "Quantization from 8-bit to 4-bit degraded grip accuracy by 3.2%, improved power by 41%."
- **Robustness profiling:** Sweep across noise levels, fault injection rates, and input perturbations. Generate robustness curves: "Network maintains >90% accuracy up to 15% dead neurons."
- **Report generation:** Export benchmark results as PDF or HTML reports with charts, tables, and methodology description. Useful for design reviews, publications, and internal documentation.
- **Custom benchmark definition:** Define new benchmarks as CNL assertion suites + input datasets. Share benchmarks across teams via NeuroHub.

**Technical approach:**
- Backend orchestrates benchmark runs via neurocnl pipeline + existing analysis modules (`fault_injector.py`, `power_profiler.py`, crossbar export for quantization analysis)
- Benchmark definitions stored as JSON manifests (task, input spec, assertions, scoring function)
- Flutter frontend with comparison dashboards, chart grids, and report builder
- Integrates with NeuroChip for cross-target comparison and NeuroSense for real-signal benchmarks
- CI/CD integration: run benchmarks as part of a pipeline, fail on regression

**Target user example:** A product team at a medical device company is evaluating whether to deploy their prosthetic controller on Loihi 2 or Akida. They load their network into NeuroBench, run the grip stability benchmark on both targets, compare latency/power/accuracy, run fault injection to check robustness requirements for medical certification, and export a comparison report for their design review meeting.

---

### 6e. NeuroHub — Project Sharing & Reference Architecture Platform
**Gap addressed:** Fragmentation across the neuromorphic field — teams solving the same problems independently because there's no shared repository of working designs, reference architectures, or validated configurations.

A platform where professionals share, discover, and fork neuromorphic project configurations — CNL specs, hardware configs, benchmark results, and deployment profiles.

**Core features:**
- **Reference architecture library:** Curated, validated starting points for common neuromorphic applications: prosthetic reflex controller, CPG locomotion, adaptive gripper, BCI speller, wake-word detector, sensory preprocessing. Each reference includes CNL spec, hardware BOM, benchmark results, deployment profile, and design rationale.
- **Project sharing:** Publish any Neuro-space project (spec + config + results) with one click. Version-controlled via Git. Fork into your own workspace.
- **Hardware configuration registry:** Shared database of tested hardware configurations: "OpenBCI Ganglion + Teensy 4.1 at 115200 baud, FSR 402 on pin A0, validated latency: 2.3ms round-trip." Saves teams from rediscovering the same integration details.
- **Benchmark leaderboard:** Compare community results on standard NeuroBench tasks. Filter by hardware target, network size, power budget. See what's state-of-the-art for a given constraint set.
- **Design pattern catalog:** Documented SNN design patterns with CNL implementations: lateral inhibition for contrast enhancement, winner-take-all for classification, CPG for rhythmic motor control, STDP for online adaptation. Each pattern includes when to use it, known limitations, and parameter tuning guidance.
- **Team workspaces:** Private project spaces for companies. Share internally, publish externally when ready.
- **Integration:** Open any shared project directly in NeuroSim (visual editor), neurocnl Studio (CNL editor), or NeuroChip (deployment). Fork → modify → benchmark → publish improvements.

**Technical approach:**
- Flutter web frontend with project browser, search, and embedded preview widgets
- FastAPI + PostgreSQL backend for project metadata, user accounts, and access control
- Project content stored as Git repos (GitHub/GitLab integration or self-hosted)
- neurocnl specs rendered in-browser via embedded Studio widget
- Benchmark results stored as structured JSON, indexed for filtering and comparison

**Target user example:** A startup building a neuromorphic audio processor needs a wake-word detection circuit. Instead of designing from scratch, they search NeuroHub for "wake-word", find a validated reference architecture with CNL spec, Loihi 2 deployment profile, and benchmark results showing 94% accuracy at 0.3 mW. They fork it, adapt the vocabulary, re-benchmark in NeuroBench, and deploy via NeuroChip. Weeks of design work replaced by hours of adaptation.

---

## Phase 7 — Hardware Validation (Neuro-Dream-Hand)

Requires physical hardware (Teensy 4.0, OpenBCI Ganglion, optionally Loihi 2). Software is complete; these tasks need hands-on lab work.

- [ ] Validate serial driver on physical Teensy 4.0
- [ ] Measure real round-trip latency and sensor noise
- [ ] Validate EMG streaming with physical Ganglion board
- [ ] Validate EMG encoder with live voluntary contraction
- [ ] Quantify sim-to-real gap (MuJoCo vs. physical testbed)
- [ ] Measure actual on-chip power on Loihi 2 or Akida (requires chip access)
- [ ] Compile and run on Intel Loihi 2 (requires NxSDK)

---

## Phase 8 — Research Directions

Longer-term explorations from `neurocnl/ROADMAP.md`:

1. **Spec Verification** — Formal proof (Z3 SMT solver) that a CNL spec satisfies Layer 1 invariants for all inputs
2. **Spec Synthesis** — Given desired behavior, automatically generate the CNL spec (invert the pipeline)
3. **Cross-Hardware Validation** — Same spec on Nengo (CPU), NengoLoihi, and Teensy — verify equivalent behavior
4. **Biological Validation** — Compare outputs against published electrophysiology data

---

## Suite Architecture Overview

```
                [neurocnl core library]
                /    |    \         \
        NeuroSim   neurocnl   NeuroBench
       (visual      Studio    (test &
        design)    (CNL IDE)   benchmark)
                \    |    /
            [neurocnl FastAPI backend]
                /         \
    NeuroChip          NeuroSense
   (hardware           (biosignal
    deployment)         acquisition)
                \    /
          [Physical Hardware]
       Teensy / Loihi / Ganglion
                   |
               NeuroHub
          (sharing & reference
           architectures)
```

All apps share:
- **neurocnl core library** for CNL parsing, validation, and Nengo generation
- **neurocnl FastAPI backend** for simulation, export, and hardware communication
- **Flutter design system** for consistent UI across the suite
- **Nengo** as the universal SNN simulation engine

---

## Prioritized Build Order for Suite Expansion (Phase 6)

| Priority | App | Effort | Why This Order | Depends On |
|---|---|---|---|---|
| 1 | **NeuroSim** (visual design) | Large | Largest professional user base — every engineer needs to design networks regardless of their specialty | Phase 2a (STDP ✅), 2c (multi-pop ✅) |
| 2 | **NeuroChip** (hardware deploy) | Medium | Directly unblocks the sim-to-hardware gap that stalls most neuromorphic projects | Phase 2f (exporters ✅), Phase 3 (demos ✅) |
| 3 | **NeuroBench** (test & benchmark) | Medium | Teams need to evaluate and compare before committing to hardware — critical for product decisions | Phase 1 (merge ✅), NeuroChip |
| 4 | **NeuroSense** (biosignals) | Medium | Required for any bio-interfacing product; high value for medical/prosthetics/BCI companies | Phase 2b (spike encoding ✅), Phase 3 (#3 EMG ✅) |
| 5 | **NeuroHub** (sharing platform) | Large | Multiplier effect — but needs the other tools to exist first so there's something worth sharing | All other apps functional |

---

## Summary Timeline

```
DONE        Phase 1: Merge + Maintenance ✅
            |
DONE        Phase 2: Library feature completion ✅ (STDP, spike encoding, multi-pop, viz, grammar, export)
            |
DONE        Phase 3: Hardware demos ✅ (gripper, conditioning, EMG, habituation, BCI, tactile)
            |
DONE        Phase 4: Maintenance automation ✅ (Dependabot, security, pre-commit, codecov, changelog, docs, Docker CI, Arduino CI)
            |
DONE        Phase 5: Distribution & packaging ✅ (GitHub Releases, Docker GHCR, PyPI, installers, setup scripts, first-run UX)
            |
NOW         Phase 6: Neuro-space Suite Expansion
            |
LATER       Phase 6: Suite expansion
              6a. NeuroSim (visual network design — start first, broadest impact)
              6b. NeuroChip (hardware deployment)
              6c. NeuroBench (testing & benchmarking)
              6d. NeuroSense (biosignal toolkit)
              6e. NeuroHub (sharing & reference architectures)
            |
HARDWARE    Phase 7: Hardware validation (requires physical Teensy + Ganglion + optionally Loihi 2)
            |
FUTURE      Phase 8: Research directions (formal verification, spec synthesis)
```

---

## References

- `neurocnl/ROADMAP.md` — Library-specific feature roadmap
- `neurocnl/PORTFOLIO_ROADMAP.md` — Portfolio-ordered build sequence (11 priorities)
- `Neuro-Dream-Hand/THESIS_ROADMAP.md` — Thesis project phases (5 phases)
- `Merge_maintain.md` — Unified merge + maintenance execution plan (34 tasks, all complete)
- `maintenance-improvement.md` — Maintenance automation spec (Phase 4 source)
- `user-install-improvement.md` — Distribution & packaging spec (Phase 5 source)
