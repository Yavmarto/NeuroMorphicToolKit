# Claude Design Prompt: NeuroMorphicToolKit UI

You are Claude Design, an LLM-enabled UI designer. Design a cohesive, production-quality interface for NeuroMorphicToolKit (NMTK), a desktop-first neuromorphic engineering suite. The interface must feel like an expert engineering workbench, not a marketing site. It should help neuroscientists, embedded engineers, robotics researchers, and software teams move from human-readable SNN specifications to simulation, sensor encoding, hardware deployment, benchmarking, and project coordination.

The goal is to design the app and its submodules as one coherent suite while preserving each module's specialized workflow.

## Product Summary

NeuroMorphicToolKit is a Flutter desktop launcher and control plane for a suite of local neuromorphic engineering modules. The launcher installs, starts, stops, updates, monitors, and embeds module web UIs through local FastAPI services. Modules are heavy scientific tools with Python backends, optional hardware dependencies, and Flutter/web frontends. The launcher should hide most terminal, Docker, Python environment, and port-management complexity from end users.

Think of NMTK as:

- A local "app store" and workspace for neuromorphic tools.
- A control plane for local microservices running on fixed ports.
- A tabbed desktop workbench where modules can be opened side by side.
- A safe workflow layer that makes hardware readiness, exportability, deployability, warnings, and failures explicit.
- A shared visual language for SNN design, simulation, biosignals, hardware targets, benchmark evidence, and project artifacts.

The canonical demo flow is:

1. Launch CNL Studio.
2. Paste or write a valid NeuroCNL specification.
3. Validate it.
4. Run a simulation.
5. Click "Open in NeuroSim".
6. NeuroSim opens with the CNL panel populated and the canvas auto-built.
7. From NeuroSim, optionally deploy the current design to NeuroChip.
8. Optionally benchmark the design in NeuroBench, use real or replayed signals from NeuroSense, and manage project context in NeuroHub.

The user should never need to manually run `pip install`, manage `.env` files, remember ports, or inspect raw compiler logs for normal workflows.

## Audience And Personas

Primary personas:

- Neuroscientist: Knows biological mechanisms and constraints, may not know software infrastructure or hardware deployment.
- Neuromorphic software engineer: Builds SNNs and needs typed validation, simulation, exports, benchmarks, and reproducibility.
- Hardware/embedded engineer: Deploys to Teensy, PYNQ Z2, Akida, Loihi, Lava, SpiNNaker, or other targets and needs constraint analysis, quantization, flashing, runtime verification, and honest readiness states.
- Robotics/prosthetics researcher: Uses Neuro-Dream-Hand to simulate an adaptive SNN prosthetic hand with MuJoCo and Nengo before physical testing.
- Signal/sensor engineer: Uses NeuroSense to acquire EMG, EEG, EOG, ECG, tactile, or event-camera inputs and convert them into spike trains.
- Team lead or reviewer: Needs project status, suite health, benchmark evidence, deployment logs, reports, and cross-module traceability.
- Terminal-first developer: May later use `neurocli`, but the desktop app remains the main GUI front door.

Design for experts under pressure: dense, scannable, trustworthy, and explainable.

## Design Personality

The suite should feel like a scientific instrument and engineering cockpit:

- Calm, precise, and robust.
- Dense but not cluttered.
- Strong information hierarchy with explicit workflow states.
- Clear visual distinction between "valid", "warning", "unsupported", "exportable", "deployable", "running", "degraded", and "failed".
- Domain-specific visualizations: spike rasters, network graphs, waveform traces, latency/power tables, quantization curves, deployment steppers, health bars, run timelines.
- Avoid vague AI magic, glossy marketing composition, and hero-page treatment. The first screen should be the usable launcher dashboard/catalog, not a landing page.
- Do not imply hardware claims that are not verified. For example, "exportable" must not look the same as "deployed and verified on hardware".

Recommended visual direction:

- Desktop-first responsive layouts.
- Navigation rail or sidebar for shell-level movement, with bottom navigation only for narrow layouts.
- Compact cards for repeated items such as modules, projects, targets, results, logs, and artifacts.
- Clear tables where comparison matters.
- Split panes for editor/canvas/result workflows.
- Stepper components for long-running deployment pipelines.
- Code editor styling for CNL with readable syntax highlighting.
- Use color as status language, not decoration.

## Architecture And Runtime Model

NMTK uses a "launcher plus local microservice modules" architecture.

The desktop launcher lives under `nmtk/neuro_toolkit`. It is a Flutter app using Provider and GoRouter. It has:

- Onboarding.
- Python setup fallback if Python is unavailable.
- Dashboard.
- Module Catalog.
- Workspace with embedded module tabs.
- Settings.
- Dedicated deploy screens for Akida, PYNQ Z2, and Teensy.

The launcher embeds module UIs through WebView when supported. It can also open modules in the system browser. The workspace uses tabs for active modules and polls module `/health` endpoints before showing the embedded UI.

Module lifecycle states:

- Not Installed
- Installing
- Installed
- Starting
- Running
- Stopping
- Error
- Degraded
- Updating

Important launcher integrity rules:

- Distinguish "preflight failed" from "degraded optional capability".
- Optional heavy runtimes such as MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker, and report generation should degrade capabilities rather than break the base launcher, unless a module explicitly requires them.
- Module registry metadata, ports, paths, health checks, and start strategies are important product truth, not implementation noise.
- Launcher-visible startup and install states need understandable user-facing messages.

## Module Registry

The current launcher registry exposes these modules:

| ID | Display Name | Port | Description | Frontend | Notes |
|---|---:|---:|---|---|---|
| `neurocnl` | CNL Studio | 8000 | CNL parser, SNN generator, and simulation engine | Yes | Primary spec authoring and validation tool. Has a local dependency on Neuro-Dream-Hand for prosthetic routes. |
| `Neurosim` | NeuroSim | 8001 | Visual drag-and-drop SNN design canvas | Yes | Receives one-click CNL handoff from NeuroCNL. Can hand off to NeuroChip. |
| `Neurochip` | NeuroChip | 8002 | Hardware deployment and firmware generation | Yes | Hardware constraint, quantization, export, flash, and runtime verification workflows. |
| `Neurobench` | NeuroBench | 8003 | SNN testing and benchmarking workbench | Yes | Benchmarks, baselines, regressions, robustness, reports. |
| `Neurosense` | NeuroSense | 8004 | Biosignal acquisition and spike encoding | Yes | Device discovery, live signals, filtering, encoding, recording, replay. |
| `Neurohub` | NeuroHub | 8005 | Suite dashboard and project orchestrator in current code | Yes | Current code differs from registry-focused spec; see NeuroHub section. |
| `neuro_dream_hand` | NDH Simulator | None | Prosthetic SNN physics simulation | No | CLI/library only. Requires MuJoCo. |

Docker defaults:

- Core profile: NeuroCNL 8000, NeuroSim 8001, NeuroChip 8002.
- Full profile adds NeuroBench 8003, NeuroSense 8004, NeuroHub 8005.
- Optional physics profile exposes `neurocnl-physics` on 8006.
- Monitoring profile includes Prometheus, Loki, Grafana, Promtail, and Alertmanager, but those are operational tools rather than primary end-user modules.

Remote update metadata currently shows newer versions for NeuroCNL, NeuroSim, and Neuro-Dream-Hand, so the UI must support update-available states cleanly.

## Suite-Level Information Architecture

Design the launcher around these top-level surfaces:

1. Dashboard
   - Installed modules.
   - Service status and health.
   - Start, stop, open, update, uninstall actions.
   - Quick deploy buttons: Akida Deploy, PYNQ Deploy, Teensy Deploy.
   - Module warnings, degraded capabilities, and update prompts.

2. Module Catalog
   - All available modules with icon, name, id, description, version, frontend availability, install state, update state, and requirements.
   - Install, retry, update, uninstall actions.
   - MuJoCo-required modules should be visibly disabled or marked if MuJoCo is unavailable.
   - Catalog cards should communicate module purpose and the next action quickly.

3. Workspace
   - Tabbed active modules.
   - Embedded webview or browser fallback.
   - Health polling state while a module starts.
   - Blocked launch state for preflight failure or module error.
   - Open in System Browser.
   - Stop active module.
   - Cross-module navigation: when a module opens another module URL, launch target module if needed and switch tabs.

4. Settings
   - Theme mode.
   - Logging level.
   - Telemetry opt-in and remote reporting endpoint.
   - Local crash logs.
   - Per-module enabled flag and custom port override.

5. Deployment Utilities
   - Akida deploy workflow.
   - PYNQ Z2 deploy workflow.
   - Teensy 4.1 deploy workflow.
   - These are launcher-level shortcuts for hardware paths that also exist inside NeuroCNL/NeuroChip.

6. Python Setup
   - Appears when Python is unavailable.
   - Should explain the local requirement and guide recovery without feeling like a raw error.

## Cross-Module Workflows

### Workflow A: CNL To Simulation Canvas

User writes a CNL spec in NeuroCNL, validates it, simulates it, and opens it in NeuroSim.

Key UX requirements:

- CNL editor on the left, results on the right.
- Validation must be visible before simulation/deployment actions become prominent.
- "Open in NeuroSim" should be enabled when there is non-empty CNL.
- NeuroSim should show a success banner when it receives CNL and builds the canvas.
- If NeuroSim cannot parse incoming CNL, keep the imported text visible, leave canvas empty, and show a repair path: "Fix CNL and Sync to Canvas".
- Export is optional and should not be required for handoff.

### Workflow B: Visual Canvas To Hardware

User designs or imports an SNN in NeuroSim, validates graph constraints, previews simulation, then opens in NeuroChip.

Key UX requirements:

- Component library, canvas, CNL panel, property panel, and optional preview panel.
- NeuroChip handoff button should be disabled with an explanatory tooltip if validation fails or NeuroChip is unreachable.
- Handoff should preserve graph, stable ids, positions, topology, and parameters.

### Workflow C: Hardware Readiness And Deployment

User loads a network into NeuroChip or a launcher deploy wizard, selects a target, checks constraints, quantizes, exports, flashes/deploys, monitors, and verifies.

Key UX requirements:

- Stepper states for Prepare/Readiness, Scaffold/Export, Deploy/SDK, Monitor, Verify.
- Separate planning-time exportability from runtime deployability.
- Hardware warnings must be prominent, but not indistinguishable from fatal failures.
- Serial/network board discovery should be guided and recoverable.
- Raw compiler/SDK errors should be summarized with human-readable next steps, while technical details remain accessible.

### Workflow D: Biosignal To Spike Train

User connects a biosignal device in NeuroSense, chooses a preset, checks signal quality, views live filtered waveforms, encodes spikes, records/replays sessions, and pipes spikes into simulation/benchmarking.

Key UX requirements:

- Device selector with connection state.
- Preset selector for EMG, EEG, EOG, ECG, tactile, and event data workflows.
- Signal quality indicators per channel.
- Live waveform viewer and spike raster comparison.
- Recording controls with markers.
- Replay controls for recorded sessions.
- Pipeline connector for sending encoded spikes to NeuroCNL/NeuroSim or benchmark flows.

### Workflow E: Benchmark Evidence

User opens NeuroBench, selects a benchmark, runs it against a network, compares against baselines, examines robustness and perturbation curves, compares targets or encoding methods, and produces reports.

Key UX requirements:

- Benchmark catalog sidebar.
- Main result area with metrics, baseline diffs, charts, run history, and report builder.
- Strong support for "did this regress?" decisions.
- Results should be exportable as PDF/HTML/CSV and usable in CI contexts.

### Workflow F: Project And Suite Coordination

User opens NeuroHub current dashboard, sees suite health, projects, activity, assets, workflows, notes, members, and links out to module-specific work.

Key UX requirements:

- Suite health should summarize module availability and failures.
- Projects should link to NeuroSim, NeuroChip, NeuroBench, NeuroSense, and artifacts.
- Activity feed should show what happened across the suite.
- Workflow editor/run surfaces can be simple initially but should make cross-module sequences understandable.

## Module: NeuroCNL / CNL Studio

Purpose:

NeuroCNL is a Controlled Natural Language system for neuromorphic computing. Users write plain-English-like specifications describing SNN behavior. The backend parses them, validates physical invariants, lowers them into typed IR, plans backend support, generates Nengo networks, simulates, exports, and hands off to other modules.

Important truth:

- NeuroCNL parsing is regex/rule based, not LLM based.
- Parser recognition is broader than faithful runtime support.
- Nengo is the primary faithful execution path.
- Other targets may be approximate, partial, unsupported, or export-only.
- Exporting an artifact does not prove real hardware deployment.

Recognized CNL concepts include threshold firing, refractory period, membrane decay, synaptic weight, axonal delay, timing declaration, STDP/BCM/Oja learning, inhibitory connections, population coding, network topology, lateral inhibition, homeostatic plasticity, neuromodulation, population coding range, adaptive spiking, receptor dynamics, short-term plasticity, background noise, spatial connectivity, and timing declarations.

Validation layers:

- Layer 1: physical, contract, and timing checks.
- Layer 2: cross-sentence/spec checks.
- Layer 3: generated pytest assertions.
- Loihi adds hardware-specific validation checks and warnings.

Backend support labels:

- `faithful`: execution closely preserves intended semantics.
- `approximate`: execution/export works with caveats or backend simplifications.
- `unsupported`: current target cannot honestly claim support.
- `parser-recognized`: accepted by the parser but not necessarily executable.

Supported/export targets and caveats:

- Nengo: faithful full simulation.
- Loihi: approximate NengoLoihi script.
- Lava: approximate export script.
- SpiNNaker: approximate PyNN export.
- SpiNNaker2: approximate export only.
- Akida/Akida2: approximate scaffold/handoff with strict unsupported feature caveats.
- Teensy: approximate handoff to NeuroChip, feedforward LIF only.
- PYNQ Z2: approximate export only unless runtime deployment is verified by NeuroChip.
- sinabs/Rockpool/NIR: partial or exchange/export-oriented support.

Current UI surfaces:

- Server setup screen if backend is not configured.
- App shell with Studio, Deploy, Hardware, and Analysis navigation.
- Studio screen:
  - CNL editor.
  - Pipeline bar.
  - Template gallery.
  - Run Simulation.
  - Open in NeuroSim.
  - Open in NeuroChip.
  - Export menu.
  - Results tabs: Parsed Specs, Validation, Network, Simulation, Parameters.
  - Simulation duration slider.
  - Parameter explorer.
  - Network graph view.
  - Simulation dashboard with spike raster and voltage traces.
- Deploy screen:
  - Simulation, learning, and export-oriented prosthetic panels.
  - Teensy, PYNQ, and Akida deploy panels are present in widgets and launcher.
- Hardware screen:
  - Serial port selector.
  - Baud rate.
  - Connect/disconnect.
  - Live sensor data.
  - Emergency stop.
- Analysis screen:
  - Energy profiling.
  - Quantization analysis.
  - Fault injection.

Backend APIs:

- `/api/parse`
- `/api/validate`
- `/api/generate`
- `/api/simulate`
- `/api/templates`
- `/api/export`
- `/api/deploy/teensy/network`
- `/api/deploy/pynq/network`
- `/api/deploy/akida/network`
- `/api/jobs`
- `/api/handoff`
- `/api/prosthetic/*` routes for prosthetic simulation, sleep, export, analysis, and hardware.

Design needs:

- Make writing and debugging CNL approachable without hiding technical rigor.
- Use syntax color and inline parse/validation feedback.
- Explain warnings in context without long prose blocks.
- Make backend support verdicts visually distinct and prominent before export/deploy.
- Preserve the canonical CNL to NeuroSim handoff as a first-class action.
- Never suggest that unsupported or approximate targets are fully production-ready.

## Module: NeuroSim

Purpose:

NeuroSim is a visual drag-and-drop workbench for designing, parameterizing, simulating, and exporting SNNs. It lets users work graphically while preserving bidirectional synchronization with NeuroCNL text.

Target users:

- Hardware engineers and signal processing specialists who understand system design but do not want to write CNL or Python by hand.
- Users receiving CNL from NeuroCNL and wanting a visual graph.

Core concepts:

- Canvas graph with nodes and directed edges.
- Component library with neurons, synapses, encoders, and patterns.
- Property panel for selected node/edge parameters.
- CNL panel for generated/imported specification.
- Real-time validation and backend support banner.
- Simulation preview and parameter sweep.
- Export and project save/load.

Current UI surfaces:

- NeuroSim Workbench canvas screen.
- Drawer navigation to Canvas, Projects, Parameter Sweep, Export Design.
- App bar controls to hide/show:
  - Component Library.
  - Preview.
  - CNL panel.
  - Component Details.
- Deploy to NeuroChip action with disabled tooltip if invalid/unreachable.
- Resizable panels:
  - Component Library.
  - Main canvas.
  - Generated CNL Spec.
  - Component Details.
- Empty canvas state with actions:
  - Paste CNL and Sync.
  - Drag components from the library.
- Optional preview panel with simulation controls and spike raster output.
- Startup banners for imported CNL success/failure.

Backend APIs:

- Components and categories.
- Starter templates.
- Validate graph.
- Generate CNL.
- Parse CNL to graph.
- Preview simulation.
- Simulation WebSocket.
- Parameter sweep and job polling.
- Export formats.
- Project save/load.
- SpiNNaker2 run/results routes.

Design needs:

- Treat the canvas as the primary object, not a decorative diagram.
- Support efficient pan/zoom, node movement, port-to-port connections, selection, multi-select, delete, and undo/redo.
- Preserve stable ids, positions, and parameters.
- Make invalid nodes/edges easy to diagnose.
- Support both visual-first and text-first workflows.
- Provide compact preview visualizations without stealing space from the canvas.

## Module: NeuroChip

Purpose:

NeuroChip is the hardware deployment and compilation toolkit. It analyzes whether a network fits a target, quantizes weights, estimates power/latency, generates deployment packages, flashes or deploys where possible, runs verification, and keeps deployment logs.

Targets and technologies:

- Teensy 4.1.
- PYNQ Z2.
- Akida/Akida2.
- Loihi/Lava.
- SpiNNaker/SpiNNaker2.
- BrainScaleS and other hardware profile targets.
- Serial devices, board-hosted PYNQ runtime, SDK verification, firmware packages, overlay artifacts.

Current UI surfaces:

- Main app with bottom navigation:
  - Analysis.
  - Compare.
  - Gallery.
  - History.
- Analysis:
  - Target selector.
  - Quantization explorer.
  - Power/latency panel.
  - Troubleshooting guide link.
- Compare:
  - Filter chips for selected hardware targets.
  - Target comparison table.
- Gallery:
  - Hardware target grid.
  - Name, manufacturer, description, neuron capacity, select target.
- History:
  - Deployment log table.

Backend APIs:

- `/health`
- Target profiles.
- Constraint analysis and partition suggestions.
- Multi-target comparison.
- Quantization and batch quantization.
- Fault injection.
- Power and latency estimates.
- Exports for Akida, BrainScaleS, SpiNNaker, Teensy, Loihi, Lava, PYNQ, NeuroML.
- Serial ports, flash, flash status, flash verification.
- Deployment log and manifest validation.
- PYNQ deploy/run/status/preflight/verify.
- Akida deploy, mapped deploy, inference, status, verify.
- Lava compile/run/stop.

PYNQ support semantics:

- `EXPORTABLE`: offline planner can quantize and generate overlay artifacts without a board.
- `EXPORTABLE_WITH_WARNINGS`: export works but near thresholds or with warnings.
- `NOT_EXPORTABLE`: deterministic export blocker.
- `DEPLOYABLE`: runtime board is reachable, overlay assets are present, bitstream loaded, DMA/IP core accessible.
- `NOT_DEPLOYABLE`: export may be OK but runtime board/overlay failed.
- The UI must visually distinguish export-ready from deploy-ready states.

Teensy flow:

- CNL input.
- Deployability verdict.
- Firmware export.
- Serial port selection.
- Flash.
- Verify.

Akida flow:

- CNL input.
- Weight bit-width and Akida version.
- Readiness/exportability check via NeuroCNL.
- Generate scaffold package.
- Verify SDK deployability through NeuroChip.
- Optional NeuroBench verification.

Design needs:

- Use comparison tables for hardware choice.
- Use steppers for deploy sequences.
- Use sliders/tables for quantization.
- Always show target constraints in plain language and technical detail.
- Treat flashing/deployment as high-risk actions requiring clear confirmation, progress, and rollback/download alternatives.
- Use logs/history as reproducibility artifacts, not just notifications.

## Module: NeuroBench

Purpose:

NeuroBench evaluates SNN performance across accuracy, latency, power, robustness, regression, encoding strategy, and hardware target tradeoffs. It is also intended to support CI/CD workflows where benchmark regressions can fail builds.

Core workflows:

- Run standard benchmarks such as grip stability, spike classification, reaction latency, wake-word detection, and pattern recognition.
- Define custom benchmarks with JSON manifests, CNL assertions, input datasets, scoring functions, and pass thresholds.
- Compare hardware targets via NeuroChip profiles.
- Compare encoding methods via NeuroSense recordings or synthetic signals.
- Save baselines and diff current runs.
- Run fault sweeps and input perturbation sweeps.
- Generate PDF/HTML reports.

Current UI surfaces:

- GoRouter app with Home, Reports, Robustness routes.
- Benchmark screen:
  - Benchmark catalog sidebar.
  - Main panel for selected benchmark.
  - Run Benchmark button.
  - Results summary.
  - Metric diff table.
  - Robustness curve.
  - Perturbation curve.
  - Target comparison grid.
  - Run history timeline.
  - Report builder.
- Robustness screen placeholder.
- Report screen placeholder with loaded benchmark/baseline counts.
- Regression trends screen placeholder.

Backend APIs:

- Benchmarks list/detail/create.
- Run benchmark, poll job, result, cancel.
- SynSense, SpiNNaker2, and PYNQ benchmark routes.
- Compare baselines/results and export comparison.
- Target and encoding comparison.
- Fault sweep.
- Perturbation sweep.
- Baselines list/save.
- Results list/detail.
- Regression trends.
- Report generation.

Design needs:

- Make the primary question obvious: did the network pass, improve, regress, or trade accuracy for power/latency?
- Put benchmark selection, configuration, run status, current result, baseline diff, and history in one scannable workflow.
- Charts should support evidence, not decoration.
- Reports should feel like design review artifacts.
- CI-oriented outputs should be discoverable but not dominate the GUI.

## Module: NeuroSense

Purpose:

NeuroSense acquires, filters, spike-encodes, records, replays, and exports biosignals and event streams. It provides biological or sensor-realistic input for SNN simulation and benchmarking.

Signal domains:

- EMG.
- EEG.
- EOG.
- ECG.
- Tactile.
- Event camera / Prophesee.
- PYNQ sensor stream.
- Generic serial ADC.

Target devices and integrations:

- OpenBCI Ganglion.
- OpenBCI Cyton.
- Muse 2/S.
- BITalino.
- Generic serial ADC.
- Prophesee event source.
- PYNQ streaming source.
- NIR import/export.
- BrainFlow, scipy filtering, HDF5 storage, WebSocket streaming.

Current UI surfaces:

- Main app with bottom navigation:
  - Monitor.
  - Config.
  - Pipeline.
- Signal Monitor:
  - Signal quality bar.
  - Live signal viewer.
  - Recording controls.
  - Spike encoding panel.
  - Replay controls.
- Device Configuration:
  - Device selector.
  - Preset selector.
- Filter Pipeline:
  - Pipeline connector.

Backend APIs:

- Device scan/connect/disconnect/impedance.
- Presets list/detail/create.
- WebSocket streams for raw, filtered, and spike data.
- Batch encoding.
- Recording start/stop/marker.
- Sessions list/detail/download/replay/stop.
- Signal quality.
- Export.
- NIR import.
- Prophesee devices and streaming.
- PYNQ devices and streaming.

Design needs:

- Signal quality must be readable at a glance.
- Show raw, filtered, and encoded signals as related views.
- Presets should make expert filtering/encoding choices approachable.
- Recording and replay should look reliable and timestamped.
- Pipeline connection should make destination, latency, and data format explicit.
- Use live visualization layouts that remain legible with 4 to 8 channels.

## Module: NeuroHub

Important product ambiguity:

There are two NeuroHub concepts in the repository.

1. Current implemented module:
   - Launcher manifest calls NeuroHub "Suite dashboard and project orchestrator" on port 8005.
   - Current backend routes include auth, dashboard, projects, milestones, assets, workflows, activity, health, config, members, and notes.
   - Current frontend screens include login, dashboard, project detail, new project, asset library, live test, settings, workflow editor, workflow run, and widgets for activity feed, suite health, project cards, milestones, members, notes, bundle export, and config.

2. Registry specification:
   - README/spec describe Neurohub as a community registry for SNN models, datasets, hardware profiles, CNL spec templates, encoding presets, and benchmark baselines.
   - The spec says project orchestration should be a separate NeuroDash module, but there is no top-level NeuroDash module in this checkout.

Design recommendation:

- For the current app, design NeuroHub as "Suite Dashboard / Project Hub" because that matches the code and launcher manifest.
- Also include a future or secondary "Registry" concept if useful, but label it clearly as a community artifact registry rather than the current orchestration dashboard.
- Do not conflate project workflows with public model registry features unless the product owner explicitly merges the concepts.

Current NeuroHub suite dashboard UI:

- Login gate.
- Dashboard:
  - Suite health bar.
  - Project grid.
  - New Project action.
  - Recent Activity feed.
  - Onboarding tour.
  - Refresh and settings actions.
- Project detail:
  - Project name, owner, status, description, tags.
  - Links to open related NeuroSim or NeuroChip context.
  - Project id, created/updated times.
  - Members list.
- Other screens:
  - Asset library.
  - Live test.
  - Settings.
  - Workflow editor.
  - Workflow run.
  - Notes, milestones, member management, bundle export.

Potential registry UI from the spec:

- Search and filter artifacts by type, hardware target, neuron model, task, license, NeuroBench score.
- Artifact cards with owner/slug, type, hardware target, task, score, stars, downloads, last updated.
- Artifact detail/model card with overview, architecture, training data, hardware targets, performance, limitations, license, citation, files, versions, scores, discussions.
- Stable URI scheme: `neurohub://{type}/{owner}/{slug}@{version}`.
- In-app "Browse Neurohub" panel embedded in modules with Import and Publish actions.

Design needs:

- Current dashboard should feel like project operations: health, work, activity, ownership, reproducibility.
- Registry should feel like searchable scientific artifacts: metadata, versioning, trust, benchmark evidence, provenance.
- If both are shown, separate them through navigation and naming.

## Module: Neuro-Dream-Hand / NDH Simulator

Purpose:

Neuro-Dream-Hand is a Python library and CLI-only module for adaptive neuromorphic prosthetic hand control. It uses Nengo SNNs and MuJoCo physics to test a robotic hand controller before physical hardware deployment.

Key ideas:

- Physics-accurate prosthetic/gripper simulation.
- Closed-loop SNN control.
- Slip detection from proprioceptive feedback.
- Reflexive grip-force boost.
- Online continual learning with PES.
- Sleep/offline replay to consolidate learning.
- Drop tests, hyperparameter sweeps, and multi-day wake/sleep experiments.
- Weight quantization analysis for Loihi/Akida-style hardware.
- Crossbar export to HDF5.
- Fault injection.
- Energy profiling.
- Serial bridge and EMG/tactile ingestion code paths are implemented with mocks and await real hardware validation.

Current launcher representation:

- Module name: NDH Simulator.
- No frontend.
- No port.
- Requires MuJoCo.
- Install strategy: pip.
- Start strategy: none.

Design needs:

- In the launcher/catalog, make it clear this is a CLI/library simulator rather than an embedded web UI.
- Show MuJoCo requirement and unavailable state clearly.
- Future UI could visualize:
  - Simulation video/output.
  - Object height, slip velocity, reflex boost, weight evolution.
  - Sleep training loss.
  - Day-by-day improvement.
  - Quantization degradation.
  - Fault injection outcomes.
  - Hardware readiness gaps.

Do not present real hardware claims as complete; current physical hardware validation is still pending.

## Shared UI Core

`nmtk_ui_core` is the shared Flutter UI package. It should be treated as the design system foundation.

It currently exposes:

- App themes and theme variants.
- Deployment models for Teensy, PYNQ, and Akida.
- Energy report, quantization report, sensor frame models.
- Buttons.
- Energy bar chart.
- Pipeline stepper.
- PYNQ deploy status card.
- Akida support state card.
- Quantization table.
- Sparkline chart.
- Navigation rail.

Important design-system principles:

- Keep components state-management agnostic.
- Shared widgets should be self-contained and typed.
- Do not hide network calls or module-specific services inside shared widgets.
- Use shared widgets for repeated domain concepts such as pipeline steppers, deployment support cards, charts, status badges, and navigation.

## NeuroCLI

`neurocli` is planning-only in this checkout. It is intended to become the scriptable companion to the desktop launcher.

Likely future purpose:

- Project scaffolding.
- `neuro new --framework lava --target loihi2 --task kws`.
- Template bundles for supported frameworks and targets.
- Lifecycle commands that mirror the launcher manifest and module ids.
- CI/scriptable workflows.

Design impact:

- No UI is needed today.
- The GUI should not imply a shipped CLI exists.
- The suite should leave conceptual room for exporting commands or showing equivalent CLI snippets later.

## Status And Truthfulness Rules

Hardware and backend capabilities vary. The UI must be honest.

Use these status categories consistently:

- Valid: spec/graph passes required checks.
- Warning: can proceed, but caveats apply.
- Unsupported: cannot honestly claim support for this target/path.
- Approximate: export or execution exists, but semantics are simplified.
- Exportable: files can be generated offline.
- Deployable: real runtime/hardware verification succeeded.
- Degraded optional capability: base service runs but an optional feature is unavailable.
- Preflight failed: startup or required dependency is blocked.
- Error: action failed and needs recovery.

Examples:

- PYNQ exportable is not the same as PYNQ deployable.
- Akida scaffold exportability is not proof the BrainChip SDK can deploy in the current environment.
- NeuroCNL exporting a Teensy artifact is not the same as flashing and verifying real hardware.
- Missing MuJoCo should block or degrade physics/prosthetic paths, not the entire suite.
- Missing BrainFlow should degrade live biosignal acquisition, not necessarily offline session replay.

## Required Visualizations

The design should cover these visualization types:

- SNN graph/canvas with populations, connections, ports, edge types, warnings.
- CNL editor with parse/validation feedback.
- Parse results table.
- Validation status panels.
- Backend support banners.
- Spike raster plots.
- Membrane voltage traces.
- Live raw/filtered biosignal waveforms.
- Spike encoding comparison panels.
- Signal quality indicators.
- Energy bar charts.
- Quantization curves and tables.
- Fault robustness curves with confidence bands.
- Perturbation curves.
- Target comparison tables.
- Benchmark metric diff tables.
- Run history timeline.
- Deployment pipeline steppers.
- Health/service status bar.
- Activity feed.
- Project/asset cards.

## Screen-Level Deliverables To Produce

Produce a design proposal that includes:

1. Launcher dashboard.
2. Module catalog.
3. Module workspace with tabs and WebView/browser fallback states.
4. Settings with module configuration.
5. NeuroCNL Studio primary screen.
6. NeuroCNL deploy/analysis/hardware supporting screens.
7. NeuroSim canvas workbench.
8. NeuroChip hardware analysis/deployment experience.
9. NeuroBench benchmark workbench.
10. NeuroSense signal monitor/config/pipeline experience.
11. NeuroHub suite dashboard/project experience.
12. Optional NeuroHub registry panel as a future/secondary concept.
13. NDH Simulator catalog/detail state for a CLI-only MuJoCo-dependent module.
14. Shared status, badge, chart, table, stepper, and empty/error-state components.

For each major screen, include:

- Primary user goal.
- Layout structure.
- Navigation model.
- Key controls.
- Required states.
- Error/recovery states.
- Data visualizations.
- Cross-module actions.

## Copy And Terminology Guidelines

Use precise engineering copy:

- "Validate spec", not "AI checks it".
- "Open in NeuroSim", not "Send to magic canvas".
- "Exportable", "Deployable", "Verified", "Approximate", and "Unsupported" must retain their specific meanings.
- "Simulation complete" is different from "hardware verified".
- "Backend unreachable" should include recovery action.
- "Degraded optional capability" should name the missing optional dependency or hardware path.

Avoid:

- Overpromising production hardware support.
- Vague claims like "fully autonomous AI design".
- Long tutorial text inside primary work surfaces.
- Marketing hero sections.
- Decorative visuals that hide data density.

## Suggested Navigation Model

Launcher:

- Dashboard
- Catalog
- Workspace
- Settings
- Deploy utilities reachable from Dashboard and possibly a Hardware menu

Module workspace tabs:

- Each running module gets a tab.
- Active tab embeds module UI when ready.
- Tab can be closed without necessarily uninstalling module.
- Stop action is distinct from close-tab action.

Inside modules:

- NeuroCNL: Studio, Deploy, Hardware, Analysis, Server Settings.
- NeuroSim: Canvas, Projects, Parameter Sweep, Export.
- NeuroChip: Analysis, Compare, Gallery, History.
- NeuroBench: Benchmarks, Robustness, Reports, Trends/History.
- NeuroSense: Monitor, Config, Pipeline.
- NeuroHub current: Dashboard, Projects, Assets, Workflows, Activity, Settings.

## Responsive Behavior

Desktop is primary. The app should still adapt to narrower windows:

- Wide desktop: navigation rail plus split panes.
- Medium desktop: collapsible panels, resizable panes.
- Narrow/mobile: bottom navigation, stacked panes, tabs, and modal property sheets.
- Avoid text clipping in buttons, badges, cards, and tables.
- Preserve graph/canvas usability with minimum canvas width and hideable side panels.

## Accessibility And Safety

The UI must support:

- Keyboard navigation for editor, buttons, tabs, and steppers.
- Tooltips for icon-only actions.
- Clear focus states.
- Color plus text/icon status, not color alone.
- Confirmation for risky hardware actions such as flashing or deploying to a connected board.
- Emergency stop in hardware screens where live device control exists.
- Human-readable error summaries with optional technical details.

## Final Design Objective

Create a unified design system and screen architecture that makes NMTK feel like one coherent suite, while respecting that each module is a specialized engineering app. The design should make a user feel in control of a complex local neuromorphic toolchain: they can see what is installed, what is running, what is valid, what is approximate, what can be exported, what is genuinely deployed, and what evidence supports a design decision.
