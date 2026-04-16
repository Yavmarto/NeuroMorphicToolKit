I’m going to inspect the repository structure and key documentation, then check your `open-brain` memory for any thesis-relevant context before drafting the thesis brief into a markdown file.
UpdateTodos: 4 items


**Files Read:**

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/AGENTS.md**
```
# NeuroMorphicToolKit Agent Router

This checkout contains the suite control plane plus the individual product modules. Default to one writable top-level module per task; if a change crosses a contract boundary, read both modules' `AGENTS.md` files and both sides' spec or ADR docs before writing.

Read before edit:
- Before writing code anywhere in this repo, read `CODING_STYLE_GUIDE.md`.
- If editing `neurocnl/**`, read `neurocnl/AGENTS.md`.
- If editing `Neurosim/**`, read `Neurosim/AGENTS.md`.
- If editing `Neurochip/**`, read `Neurochip/AGENTS.md`.
- If editing `Neurobench/**`, read `Neurobench/AGENTS.md`.
- If editing `Neuro-Dream-Hand/**`, read `Neuro-Dream-Hand/AGENTS.md`.
- If editing `Neurosense/**`, read `Neurosense/AGENTS.md`.
- If editing `Neurohub/**`, read `Neurohub/AGENTS.md`.
- If editing `nmtk/**`, read `nmtk/AGENTS.md`.
- If editing `nmtk_ui_core/**`, read `nmtk_ui_core/AGENTS.md`.
- If editing `neurocli/**`, read `neurocli/AGENTS.md`.
- If editing root-owned `docs/**`, `scripts/**`, `tests/**`, `monitoring/**`, or root config files, stay in the root repo and read the owning module `AGENTS.md` for every contract you touch.
- If editing more than one top-level module, name the write set explicitly and run the owning checks plus `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py`.

Launcher and control-plane guardrails:
- For changes under `nmtk/**`, root launcher manifests such as `nmtk/neuro_toolkit/assets/modules.json`, `nmtk/neuro_toolkit/assets/remote_modules.json`, and root compose files, `scripts/**`, or root `tests/**` that affect launcher behavior, module lifecycle behavior, or suite-visible startup semantics, run `python3 scripts/launcher_control_service.py --doctor --json`.
- Use `bash scripts/run_launcher_guardrails.sh` as the canonical local enforcement wrapper for launcher and control-plane work. Use `bash scripts/run_launcher_guardrails.sh --with-integration` when the change alters module contracts or suite-visible startup behavior.
- Treat launcher doctor `fatalCount > 0` as a blocker unless the task is explicitly to diagnose or fix that failure.
- Launcher work is not complete until launcher doctor and launcher unit coverage pass.
- Report launcher doctor outcomes explicitly as either `preflight failed` or `degraded optional capability`; do not collapse both into a generic startup error.
- Keep launcher UI state changes, module manifest changes, and launcher verification updates in the same change when they describe the same behavior. If a launcher-visible state transition depends on manifest metadata, update both surfaces together.
- If `nmtk/neuro_toolkit/assets/modules.json` changes, update the launcher Dart models, launcher tests, and any consuming helper scripts in the same change.
- Do not introduce a new install or startup strategy without doctor or preflight coverage.

```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/CODING_STYLE_GUIDE.md**
```
# NeuroMorphicToolKit Coding Style Guide

This guide only covers cross-repo defaults that are not already enforced by the nearest module config. The authority order is: nearest `AGENTS.md`, then module config files such as `pyproject.toml`, `pubspec.yaml`, `analysis_options.yaml`, and `.pre-commit-config.yaml`, then this document.

## Audited module map

- `neurocnl`: Python + Dart. See `neurocnl/pyproject.toml`, `neurocnl/frontend/pubspec.yaml`, `neurocnl/frontend/analysis_options.yaml`, `neurocnl/.pre-commit-config.yaml`.
- `Neurosim`: Python + Dart. See `Neurosim/pyproject.toml`, `Neurosim/frontend/pubspec.yaml`, `Neurosim/frontend/analysis_options.yaml`, `Neurosim/.pre-commit-config.yaml`.
- `Neurochip`: Python + Dart. See `Neurochip/pyproject.toml`, `Neurochip/frontend/pubspec.yaml`, `Neurochip/frontend/analysis_options.yaml`.
- `Neurobench`: Python + Dart. See `Neurobench/neurobench/pyproject.toml`, `Neurobench/frontend/pubspec.yaml`, `Neurobench/frontend/analysis_options.yaml`.
- `Neuro-Dream-Hand`: Python. See `Neuro-Dream-Hand/pyproject.toml`.
- `Neurosense`: Python + Dart. See `Neurosense/pyproject.toml`, `Neurosense/frontend/pubspec.yaml`, `Neurosense/frontend/analysis_options.yaml`, `Neurosense/.pre-commit-config.yaml`.
- `Neurohub`: Python + Dart. See `Neurohub/pyproject.toml`, `Neurohub/frontend/pubspec.yaml`, `Neurohub/frontend/analysis_options.yaml`, `Neurohub/.pre-commit-config.yaml`.
- `nmtk`: Dart + Python helpers. See `nmtk/neuro_toolkit/pubspec.yaml`, `nmtk/neuro_toolkit/analysis_options.yaml`.
- `nmtk_ui_core`: Dart. See `nmtk_ui_core/pubspec.yaml`, `nmtk_ui_core/analysis_options.yaml`.
- `neurocli`: Markdown-only planning at present; if implementation starts, it must share launcher manifest semantics from `nmtk/neuro_toolkit/assets/modules.json`.

## Cross-repo defaults

- Treat each top-level module as an owned boundary. Do not change a contract, manifest, export payload, or public route shape in one module without reading the consumer or producer module and updating both test surfaces.
- Keep module metadata synchronized across `nmtk/neuro_toolkit/assets/modules.json`, launcher Dart models, root compose files, and CI or helper scripts. Never change only one copy of a module id, port, install path, or uvicorn target.
- Keep optional runtimes optional. Do not move MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker, or report-generation dependencies into unconditional startup paths.
- Root `tests/` exist for suite contracts and launcher-control behavior. New unit or feature tests belong in the owning module unless the behavior is intentionally cross-module.
- Root `scripts/` are orchestration wrappers. Product logic belongs in the owning module package, not in an ad-hoc root script.
- Accepted ADRs are append-only decision records. Add a new ADR to supersede an old decision instead of rewriting the old file in place.
- `docs/archive/**` is historical record. Do not rewrite old audits to match current state; add a new dated document instead.

## Validation defaults

- Run the owning module's local checks from its own config first.
- Also run `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py` when a suite-visible contract or integration boundary changes.

## Launcher and runtime integrity

- `AGENTS.md` defines the required workflow steps. This style guide defines the quality bar the resulting change must satisfy. For launcher and runtime work, both documents apply together.
- Environment integrity is a code-quality concern, not just an operational concern. Startup paths must fail early, actionably, and deterministically when required dependencies or manifests are invalid.
- Keep launcher runtime semantics typed and synchronized across the manifest, Dart models, launcher state, helper scripts, and verification surfaces. If a launcher field changes in one surface, update the other consumers in the same change.
- Optional runtimes must remain optional at import and startup time. Missing MuJoCo, BrainFlow, PYNQ, Akida, Lava, SpiNNaker, or report-generation dependencies must degrade capability reporting rather than crash the base service unless the manifest explicitly marks them required.
- Operator-facing launcher diagnostics should use structured logging and machine-readable reporting rather than ad-hoc `print()` output where the code path is part of the supported orchestration surface.
- Launcher and control-plane changes should include a readiness check, currently `python3 scripts/launcher_control_service.py --doctor --json`, plus launcher test coverage for new install, startup, preflight, or manifest behavior.
- Suite-visible launcher changes still require the root integration checks in addition to owning tests; launcher-only changes without contract impact can stop at launcher-local verification, but they must say that explicitly in the change summary.

```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/README.md**
```
# NeuroMorphicToolkit (NMTK)

> **Unifying Neuromorphic Engineering, Neuroscience, and Software Development.**

Welcome to the **NeuroMorphicToolkit (NMTK)**—the central hub designed to bridge the gap between disciplines in the neuromorphic computing field. Whether you are a neuroscientist designing biological invariants, a software engineer building spiking neural networks, or a hardware roboticist deploying to edge devices, NMTK provides a unified, low-barrier entry point to streamline your R&D workflows.

The toolkit centralizes several specialized applications into a single, cohesive platform.

---

## 🎯 The Vision & Problem Statement

Neuromorphic computing is inherently multidisciplinary.
*   **Neuroscientists** understand the biological mechanisms but may lack the software engineering background for complex pipelines.
*   **Software Developers** know how to build robust systems but struggle with the biological constraints (invariants) and specialized hardware.
*   **Hardware Engineers** build the physical neuromorphic chips and robots but need accessible interfaces and compilers to test their designs.

**The Solution:** The NeuroMorphicToolkit app serves as the single entry point. Instead of juggling a dozen fragmented repositories, users install one native toolkit application. From this app, professionals can browse, download, and launch specialized modules tailored to their immediate needs, completely hiding the complex setup, dependency management, and interoperability issues.

---

## 🧩 The Submodule Ecosystem (The Apps)

NMTK orchestrates the following specialized modules, which can be dynamically downloaded into the main toolkit:

1.  **[NeuroCNL](./neurocnl) (Conceptual Neuromorphic Language)**
    *   *Purpose:* Translates plain-English specifications into verified Spiking Neural Networks (SNNs).
    *   *Best for:* Fast prototyping, ensuring biological constraints, and exporting to various hardware (Loihi, Lava, SpiNNaker).
2.  **[Neurosim](./Neurosim)**
    *   *Purpose:* A robust simulation environment to test neuromorphic models before physical deployment.
    *   *Best for:* Software testing, model validation, and parameter tuning.
3.  **[Neurosense](./Neurosense)**
    *   *Purpose:* Sensory processing and encoding. Converts traditional data modalities (vision, audio, touch) into spike trains.
    *   *Best for:* Preparing datasets for SNNs and integrating sensors.
4.  **[Neurochip](./Neurochip)**
    *   *Purpose:* Interfacing directly with neuromorphic hardware backends.
    *   *Best for:* Hardware engineers and low-level deployment orchestration.
5.  **[Neurobench](./Neurobench)**
    *   *Purpose:* Standardized benchmarking and testing of neuromorphic models and hardware configurations.
    *   *Best for:* Evaluating performance, latency, and energy efficiency.
6.  **[Neurohub](./Neurohub)**
    *   *Purpose:* Community registry for sharing and discovering pre-trained SNN models, neuromorphic datasets, hardware profiles, NeuroCNL spec templates, encoding presets, and benchmark baselines.
    *   *Best for:* Researchers publishing work, engineers looking for a starting point, and anyone who wants to reuse community-validated artefacts across the suite.
7.  **[NeuroDash](./NeuroDash)**
    *   *Purpose:* Central orchestration dashboard for managing cross-app projects, pipelines, milestones, and team collaboration across the full suite.
    *   *Best for:* Team leads and project managers coordinating work across multiple Neuro-space apps.
8.  **[Neuro-Dream-Hand](./Neuro-Dream-Hand)**
    *   *Purpose:* Applied hardware robotics and edge integration (e.g., controlling a robotic hand via SNNs and Teensy microcontrollers).
    *   *Best for:* Applied robotics, edge AI, and end-to-end physical demonstrations.

### 📊 Current Module Status (March 2026)

| Module | Status | Backend | Frontend | Tests | Docker | CI |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **NeuroCNL** | 97% | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Neurosim** | 80% | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| **Neurosense** | 85% | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| **Neurohub** | 0% | ❌ | ❌ | ❌ | ❌ | ❌ |
| **NeuroDash** | 80% | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| **Neurochip** | 90% | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Neurobench** | 70% | ⚠️ | ⚠️ | ✅ | ✅ | ✅ |
| **Neuro-Dream-Hand** | 95% | ✅ | N/A | ✅ | N/A | ✅ |
| **NMTK Launcher** | 85% | ✅ | ✅ | ✅ | N/A | ❌ |

---

## 🚀 Architecture & Deployment Strategy

To achieve the goal of a single deployable desktop app with self-hosted downloadable modules (macOS, Windows, Linux), we employ a **"Launcher + Micro-Service Container"** architecture.

### 1. The Core Desktop App: NMTK Flutter Client (`neuro_toolkit` + `nmtk`)
The main repository (`neuro_toolkit`) is a desktop Flutter application.
*   **Unified Dashboard:** Acts as an "App Store" and launcher for the user. It manages user profiles, general settings, and global state.
*   **Self-Hosted Desktop Delivery:** Compiles natively to Windows, macOS, and Linux to provide a robust, self-hosted environment.
*   **Module Manager:** Handles downloading, version control, and storage of the submodules locally.

### 2. Module Delivery System (Local Orchestration)
Because the sub-apps require heavy Python environments, Docker containers, and complex scientific libraries, deploying them as simple plugins isn't feasible. Instead, NMTK uses a local micro-service orchestration approach:

*   **Process Orchestration (Docker / Virtual Environments)**
    *   When a user clicks "Install Neurobench", the Flutter app downloads the `Neurobench` module package (which contains its `docker-compose.yml`, Python backend, and compiled frontend assets).
    *   The NMTK desktop app acts as a local daemon manager. It spins up the necessary Docker containers (or isolated Python `venv`s via the `nmtk/installer` scripts) directly on the host machine in the background.
    *   The UI of the submodule is presented seamlessly inside the Flutter desktop app using a **Web View** (pointing to the module's localized frontend ports) or native Flutter UI communicating via a local REST/gRPC API.

### 3. Workflow Example
1.  A hardware engineer opens the NMTK app (Flutter).
2.  They navigate to the "Module Hub" and download **NeuroCNL** and **Neuro-Dream-Hand**.
3.  Behind the scenes, NMTK pulls the Docker containers/dependencies and starts the local backend servers for these modules.
4.  The engineer clicks "Open NeuroCNL". The Flutter app opens a new tab displaying the NeuroCNL interface natively. They write an English spec.
5.  They switch to the "Neuro-Dream-Hand" tab, pass the generated model from NeuroCNL, and click "Deploy to Hardware".
6.  Everything happens seamlessly without the engineer ever opening a terminal, managing a `.env` file, or running a `pip install`.

---

## 📚 Documentation

For users and developers:
-   **[User Guide: Installation](./docs/user/installation.md)** — Getting started with NMTK.
-   **[User Guide: Troubleshooting](./docs/user/troubleshooting.md)** — Solutions for common startup issues.
-   **[Developer Setup Guide](./SETUP_GUIDE.md)** — Running the full suite from source.
-   **[Production Playbook](./docs/PRODUCTION_PLAYBOOK.md)** — Deployment and operational guide.

---

## 🛠 Getting Started

### Quick Start (Developers)

1.  **Clone the Repository**:
    ```bash
    git clone --recurse-submodules https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git
    cd NeuroMorphicToolKit
    ```

2.  **Run the Desktop Launcher**:
    ```bash
    cd nmtk/neuro_toolkit
    flutter pub get
    flutter run -d macos  # or windows/linux
    ```

3.  **Start Backends (Docker)**:
    ```bash
    docker compose up --build
    ```

4.  **Verify Services**:
    ```bash
    bash scripts/validate_docker_compose.sh
    bash scripts/demo_smoke_test.sh
    ```

For detailed module-specific development, explore the subdirectories (e.g., `neurocnl/`, `Neurosim/`) which contain their own `README.md` files.

```



I’ve loaded the repo’s top-level rules and style guide and started mapping the suite architecture from the root docs. Next I’m checking your `open-brain` memory for thesis-relevant context, then I’ll dig into module-level docs to ground the thesis framing in concrete capabilities.
MarkAsCompleted: 1 items
MCP tool call completed: [CallToolResult { content: [Annotated { raw: Text(RawTextContent { text: "Found 10 thought(s):\n\n--- Result 1 (64.3% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, neuroscience, software development\n\nThe current repository, NeuroMorphicToolKit, is a multi-module workspace that combines a Flutter launcher/control plane with neuromorphic product modules including neurocnl, Neurosim, Neurosense, Neurochip, Neurobench, Neurohub, and Neuro-Dream-Hand.\n\n--- Result 2 (61.8% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: robotics, prosthetics, simulation\nActions: Validate physical performance of Neuro-Dream-Hand\n\nIn NeuroMorphicToolKit, Neuro-Dream-Hand is the applied robotics and prosthetic-control module with mature simulation capabilities and hardware-phase software that is unit-tested against mocks but still awaiting physical validation.\n\n--- Result 3 (61.7% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: hardware deployment, NeuroMorphicToolKit, workflow\n\nThe hardware deployment roadmap in NeuroMorphicToolKit is organized as a toolkit-level flow rather than a NeuroCNL-only flow: NeuroCNL authors and validates, Neurochip deploys, Neuro-Dream-Hand optionally verifies runtime, Neurobench optionally benchmarks, and NMTK orchestrates the user experience.\n\n--- Result 4 (59.5% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, Neurochip, deployment\n\nIn NeuroMorphicToolKit, Neurochip is the hardware and deployment-facing module responsible for packaging, compile and flash, and low-level deployment behavior rather than broad product orchestration.\n\n--- Result 5 (59.1% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, neurocli, automation\n\nIn NeuroMorphicToolKit, neurocli is still planning-stage and appears intended to become the scriptable CLI front door for scaffolding and automation-heavy toolkit workflows.\n\n--- Result 6 (58.0% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, Neurohub, community registry\n\nIn NeuroMorphicToolKit, Neurohub is a read and write community registry for models, datasets, hardware profiles, NeuroCNL templates, encoding presets, and benchmark baselines; other modules call Neurohub, but Neurohub does not depend on them for runtime.\n\n--- Result 7 (57.7% match) ---\nCaptured: 4/13/2026\nType: reference\nTopics: NeuroMorphicToolKit, neurocnl, controlled natural language\n\nIn NeuroMorphicToolKit, neurocnl is the controlled natural language module that parses plain-English neuromorphic specifications, validates them against invariants, simulates them, and supports multiple hardware or export backends with varying support levels.\n\n--- Result 8 (57.2% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, architecture, observability\n\nNeuroMorphicToolKit uses a mixed-stack architecture with Python backends, Flutter and Dart frontends, Docker Compose for local orchestration, and a shared observability stack under monitoring/.\n\n--- Result 9 (56.6% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, infrastructure, tooling\n\nThe NeuroMorphicToolKit root workspace also contains shared infrastructure and tooling modules including nmtk, nmtk_ui_core, neurocli, docs, monitoring, root tests, and root orchestration scripts.\n\n--- Result 10 (55.4% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, Neurosense, EMG\n\nIn NeuroMorphicToolKit, Neurosense is currently narrowed around a credibility-first workflow of 2-channel forearm EMG to filter to spike encoding to record to replay, with a canonical HDF5 session artifact as the main validated output.", meta: None }), annotations: None }], structured_content: None, is_error: Some(false), meta: None }]

MCP tool call completed: [CallToolResult { content: [Annotated { raw: Text(RawTextContent { text: "No thoughts found matching \"JKU Linz Applied AI master's program thesis background Yoshimar research goals\".", meta: None }), annotations: None }], structured_content: None, is_error: Some(false), meta: None }]

`open-brain` has useful stored context about the repo architecture and module roles, but I haven’t found any memory yet about your thesis preferences or JKU-specific plans. I’m now pulling module-level docs and project metadata so the markdown can recommend thesis angles that are actually supported by the current codebase.


**File Glob Results:**

- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/Auto agentic workflows (Jules)/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neuro-dream-hand/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurocnl/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neuro-dream-hand/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurocnl/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/monitoring/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocli/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocli/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/pubspec.yaml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/pubspec.yaml**



**Command Executed:**
```bash
ls -1 /Users/yoshimartodihardjo/NeuroMorphicToolKit
```

**Output:**
```
AGENTS.md
Antigravity-CDD-PBT.md
Auto agentic workflows (Jules)
CHANGELOG.md
CLAUDE.md
CODING_STYLE_GUIDE.md
CONTRIBUTING.md
DEMO_WALKTHROUGH.md
LINUX_SETUP.md
LOCAL_WORKFLOW_TESTING.md
Makefile
Neuro-Dream-Hand
Neurobench
Neurochip
Neurohub
Neurosense
Neurosim
README.md
SECURITY.md
SETUP_GUIDE.md
UI migration.md
docker-compose.dev.yml
docker-compose.prod.yml
docker-compose.yml
docs
fix-all.sh
generate_tasks.py
issues
issues-archive
monitoring
neurocli
neurocnl
neurodocs
nmtk
nmtk_ui_core
open-brain-import.md
pitches
projects.db
publish_issues.sh
pull-all.sh
push-all.sh
scripts
test-workflows.sh
test_integration_plan_PYNQ_Z2.md
tests
workflow-errors
```



**File Glob Results:**

- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/README.md**


I’ve confirmed the workspace contains the expected top-level modules, but several modules don’t expose a simple top-level `README.md`, so I’m switching to directory inspection and targeted file reads to understand what each part is mature enough to support as a thesis.

**Command Executed:**
```bash
for d in /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosim /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurobench /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurohub /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neuro-Dream-Hand; do printf '\n== %s ==\n' "$d"; ls -1 "$d"; done
```

**Output:**
```

== /Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl ==
AGENTS.md
CHANGELOG.md
CODING_STYLE_GUIDE.md
COMPARISON.md
Makefile
PORTFOLIO_ROADMAP.md
README.md
ROADMAP.md
SECURITY.md
SECURITY_REVIEW.md
TODO.md
UI migration.md
agent_execution_guide.md
backend
cnl_expansion_plan.md
cnl_explained.md
cnl_hardware_semantics_plan.md
debug_screenshot.png
debug_studio.png
debug_studio_2.png
debug_studio_ls.png
demos
docker-compose.dev.yml
docker-compose.yml
docs
example_nengo_model.py
example_tester.py
examples
fix_types.patch
frontend
frontend_tester.dart
issues
issues-archive
jobs.db
jules-roadmap.md
mkdocs.yml
neurocnl
neuromorphic_spec_plan.md
project_knowledge_base.md
pyproject.toml
recent_commits.patch
scripts
simulation_report.json
sonnet-explains-cnl.md
test.py
test_nengo_io.py
tests
unimplemented_stubs.md
update_grammar.patch
update_grammar.py
venv

== /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosim ==
AGENTS.md
CHANGELOG.md
CODE_REVIEW.md
CODING_STYLE_GUIDE.md
Dockerfile
Makefile
PROGRESS.md
README.md
SECURITY.md
SECURITY_REVIEW.md
UI migration.md
build
docker-compose.yml
docs
frontend
issues
issues-archive
large_graph.json
neurosim
neurosim.egg-info
neurosim_spec.md
projects.db
pyproject.toml
ruff_all_types.txt
ruff_debug.toml
ruff_errors.txt
ruff_errors_all.txt
ruff_everything.txt
ruff_full.txt
server.log
venv
verify-contracts-local.sh

== /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense ==
AGENTS.md
CHANGELOG.md
CODING_STYLE_GUIDE.md
DEMO_WALKTHROUGH.md
Dockerfile
Dockerfile.frontend
Makefile
README.md
SECURITY.md
UI migration.md
backend.log
docker-compose.yml
docs
fix_tests.patch
frontend
identify_tech_debt.sh
integration_test.py
issues
issues-archive
issues-next
neurobench
neurocnl
neurosense
neurosense.egg-info
neurosense_spec.md
plan.md
pyproject.toml
recordings
recordings_smoke_test
server_output.log
test_dm.py
uvicorn.log
verify-contracts-local.sh
verify_troubleshooting.py

== /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip ==
AGENTS.md
CODING_STYLE_GUIDE.md
Dockerfile
HARDWARE_TESTING.md
Makefile
NEUROCHIP_TESTING_GUIDE.md
PLAN.md
README.md
UI migration.md
docker-compose.yml
docs
frontend
issues
issues-archive
neurochip
neurochip_spec.md
poetry.lock
poetry.toml
pyproject.toml
verify-contracts-local.sh

== /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurobench ==
AGENTS.md
CHANGELOG.md
CODING_STYLE_GUIDE.md
Dockerfile
Makefile
PLAN.md
README.md
SECURITY.md
UI migration.md
data
docker-compose.yml
docs
frontend
issues
issues-archive
neurobench
neurobench.sqlite
neurobench_functional_testing_guide.md
neurobench_spec.md

== /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurohub ==
AGENTS.md
CHANGELOG.md
CODING_STYLE_GUIDE.md
Dockerfile
Makefile
README.md
SECURITY.md
UI migration.md
alembic.ini
docker-compose.yml
docs
frontend
issues
issues-archive
mypy_no_plugin.ini
neurohub
neurohub.db
neurohub.egg-info
neurohub_spec.md
patch_ci.py
patch_mypy.py
patch_precommit.py
plan.md
pyproject.toml
run_dbg8.py
scripts
shared_assets
test_alembic_migrations.db
test_coverage_results.txt
uv.lock
verify-contracts-local.sh

== /Users/yoshimartodihardjo/NeuroMorphicToolKit/Neuro-Dream-Hand ==
AGENTS.md
CHANGELOG.md
CITATION.cff
CODING_STYLE_GUIDE.md
Dockerfile
GPU_RECOMMENDATION.md
GUARDRAILS.md
LANDSCAPE.md
LICENSE
MAINTAINERS_GUIDE.md
MANIFEST.in
MYPY_BUDGET.md
Makefile
README.md
RUNNING.md
SECURITY.md
SPEC.md
THESIS_ROADMAP.md
cnl-docs
cnl-specs
demo.ipynb
docker-compose.yml
docs
environment.yml
examples
fix_ci.py
issues
issues-archive
mkdocs.yml
neurodreamhand
output
patch_integration.py
plan.md
pyproject.toml
requirements.in
requirements.txt
run_pipeline.sh
scripts
site
teensy_tutorial.md
test_docs.py
tests
```



**Files Read:**

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/README.md**
```
# neurocnl

[![CI](https://github.com/Completed-Spoon-6/neurocnl/actions/workflows/ci.yml/badge.svg)](https://github.com/Completed-Spoon-6/neurocnl/actions/workflows/ci.yml)

**Controlled Natural Language (CNL) specifications for neuromorphic computing.**

Write plain-English sentences describing spiking neural network behavior. neurocnl parses them, validates against physical invariants, and generates executable [Nengo](https://www.nengo.ai/) simulations, with optional export or deploy paths for Loihi, Lava, SpiNNaker, SpiNNaker2, Akida, PYNQ Z2, sinabs, Teensy 4.1, and NIR. Backend fidelity and deployment readiness vary by target — see [docs/support_matrix.md](docs/support_matrix.md).

## Why neurocnl?

Neuromorphic hardware is powerful but hard to program. neurocnl bridges the gap between **what a neuroscientist writes** and **what a chip executes**:

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than 20ms
```

↓ parses to structured specs ↓ validates against physics ↓ generates Nengo network ↓ runs simulation

`neurocnl` currently uses these fidelity terms consistently across the project:

- `parser-recognized`: the sentence family is accepted by `neurocnl.cnl.cnl_parser`
- `faithful`: execution closely preserves the intended semantics
- `approximate`: execution or export works, but semantics rely on heuristics or backend-specific simplifications
- `unsupported`: the project cannot honestly claim runtime or backend support yet

For per-backend detail, see [docs/support_matrix.md](docs/support_matrix.md).

## Installation

```bash
# Core (Nengo backend only — fastest install)
pip install .

# With Loihi emulator support
pip install ".[loihi]"

# With visualization (matplotlib)
pip install ".[viz]"

# Development (linters, type-checkers, docs)
pip install ".[dev]"
```

### Optional hardware extras

| Extra | Installs | Target |
|-------|----------|--------|
| `loihi` | `nengo-loihi` | Intel Loihi (emulated or real) |
| `viz` | `matplotlib` | Spike plots / debug visualization |
| `neuroml` | `lxml` | NeuroML v2 export |
| `export` | `lxml` | Same as `neuroml` |
| `lava` | `lava-nc` | Intel Lava framework |
| `spinnaker` | `pyNN` | SpiNNaker (Manchester) |
| `spinnaker2` | `py-spinnaker2` (GitLab git URL) | SpiNNaker2 / SpiNNcloud |
| `rockpool` | `rockpool` | SynSense Rockpool |
| `synsense` | `sinabs`, `torch`, `rockpool` | SynSense Speck / DYNAP-CNN |
| `dev` | pytest, ruff, mypy, mkdocs, … | Development tooling |

> **`spinnaker2` note:** Installs `py-spinnaker2` from a GitLab git URL. Requires internet
> access and cannot be installed in offline/PyPI-only environments. The `allow-direct-references`
> flag is already set in `pyproject.toml`.

> **`neurodreamhand` note:** Not a pyproject.toml extra — it is not on PyPI. Install
> separately for prosthetic/handoff routes. The package degrades gracefully with
> `DreamHandNotAvailableError` when absent.

## Quick Start

### Python API

```python
from neurocnl import parse, validate, generate

# 1. Parse a CNL sentence
spec = parse("The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0")

# 2. Validate against physical invariants
params = {
    "threshold": 1.0,
    "resting_potential": 0.0,
    "refractory_period": 0.002,
    "tau": 0.02,
    "reset_potential": 0.0,
    "current_voltage": 0.5,
}
report = validate([spec], params)
assert report["overall"] is True

# 3. Generate a Nengo network
net = generate([spec], params)

# 4. Simulate
import nengo
with nengo.Simulator(net) as sim:
    sim.run(1.0)
```

### CLI

```bash
# Run the full pipeline (parse → validate → generate → simulate)
neurocnl examples/slip_reflex.cnl

# Use the Loihi emulator backend
neurocnl examples/emg_gripper.cnl --backend loihi

# Coloured table report
neurocnl examples/slip_reflex.cnl --format table

# Validate multiple specs without simulation
neurocnl --validate-only examples/*.cnl

# Verbose / quiet modes
neurocnl examples/slip_reflex.cnl -v   # DEBUG logging
neurocnl examples/slip_reflex.cnl -q   # suppress info
```

## CNL Grammar

`neurocnl` currently recognizes 19 CNL sentence families in the parser:

| # | Parser-Recognized Concept | Example |
|---|---------------------------|---------|
| 1 | **Threshold Firing** | `The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0` |
| 2 | **Refractory Period** | `The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds` |
| 3 | **Membrane Decay** | `The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds` |
| 4 | **Synaptic Weight** | `The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0` |
| 5 | **Axonal Delay** | `A synapse MUST have a transmission delay of 5ms` |
| 6 | **STDP / BCM / Oja Learning** | `The connection from sensory neuron to motor neuron MUST adapt WITH BCM learning rate of 0.001` |
| 7 | **Inhibitory Connection** | `The connection from interneuron to motor neuron MUST be inhibitory` |
| 8 | **Population Coding** | `The sensory population MUST encode input using 100 neurons` |
| 9 | **Network Topology** | `The network MUST contain an inhibitory interneuron population of 30 neurons` |
| 10 | **Lateral Inhibition** | `The sensory neuron MUST inhibit neighboring neurons WITHIN radius of 2` |
| 11 | **Homeostatic Plasticity** | `The sensory neuron MUST maintain average firing rate of 10 Hz` |
| 12 | **Neuromodulation** | `Dopamine MUST modulate synaptic weight BY factor of 1.5` |
| 13 | **Population Coding Range** | `The population MUST encode stimulus orientation WITH 360 degree range` |
| 14 | **Adaptive Spiking** | `The sensory neuron MUST exhibit firing adaptation WITH time constant of 0.2 seconds` |
| 15 | **Receptor Dynamics** | `The connection from sensory neuron to motor neuron MUST use NMDA receptor dynamics` |
| 16 | **Short-Term Plasticity** | `A synapse MUST exhibit short-term depression WITH recovery time of 0.1 seconds` |
| 17 | **Background Noise** | `The motor population MUST receive background noise WITH variance of 0.1` |
| 18 | **Spatial Connectivity** | `The visual population MUST connect to motor population WITH distance-dependent probability` |
| 19 | **Timing Declaration** | `The network MUST operate WITH timestep of 1 ms` |

See [cnl_grammar.md](neurocnl/cnl/cnl_grammar.md) for the full grammar reference.

Parser recognition is broader than execution fidelity. The core reflex-arc and multi-population concepts are the most faithful in the current Nengo pipeline. Some newer sentence families are still approximated in generation and should be treated as prototyping features rather than production-ready deployment guarantees.

## Validation Layers

- **Layer 1** — Physical invariants (threshold > resting potential, refractory > 0, etc.)
- **Layer 1 Loihi** — Hardware constraints (weight quantization, core limits, delay range)
- **Layer 3** — Auto-generated pytest assertions from specs

Backend fidelity varies by target. Nengo simulation is the primary execution path today; hardware exporters improve portability, but exporter availability does not by itself imply faithful or production-ready deployment on every target.

The Studio/backend validation flow now exposes backend support explicitly:

- `backend_support.verdict`: `faithful`, `approximate`, or `unsupported`
- `backend_support.warnings`: timing, mapping, or hardware-limit notes that do not necessarily invalidate the spec
- `generator_fidelity.annotations`: concept-level notes describing whether advanced generator behavior is direct, approximate, or placeholder

In practice, `faithful` is strongest on the core Nengo path, `approximate` means the tool can proceed with caveats, and `unsupported` means the current target cannot be honestly claimed as supported.

## Demo Specs

Four ready-to-run demo specifications in `examples/`:

| Demo | Spec | Key Feature |
|------|------|-------------|
| EMG Adaptive Gripper | `emg_gripper.cnl` | STDP learning |
| Tactile Slip Reflex | `slip_reflex.cnl` | Axonal delays |
| EEG Attention Monitor | `eeg_attention.cnl` | Rate coding |
| Audio Wake-Word | `audio_wakeword.cnl` | Delays + STDP |

Run all simulations with synthetic inputs:

```bash
python examples/05_demo_simulations.py
```

## Project Structure

```
neurocnl/
├── cnl/           # CNL parser + grammar docs
├── layers/        # Physical invariant validators
├── generation/    # Nengo network + assertion generators
├── simulation/    # Pipeline runner (CLI entry point)
└── utils.py       # Shared utilities
examples/          # Demo specs + simulation scripts
```

## Development

```bash
pip install ".[dev]"
pytest
```
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosim/README.md**
```
# Neurosim

## Local development

Example backend startup:

```bash
uvicorn neurosim.app.main:app --reload --port 8001
```

Run Python tooling from the `Neurosim/` repository root so `pyproject.toml`
is used as the single source of truth for Ruff and mypy.

You can also override the backend base URL:

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:8001
```
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/README.md**
```
# NeuroSense

NeuroSense is being narrowed around one credibility-first workflow:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

This repository does contain broader experiments, but the workflow above is the
default reference for current claims, docs, and recorded-session artifacts.

## Flagship Workflow

- Default preset: `emg_prosthetic`
- Default future physical validation target: `OpenBCI Cyton`
- Current validated path: canonical HDF5 session artifact plus replay/export
  coverage backed by deterministic fixture and synthetic-path tests
- Primary artifact: versioned HDF5 session containing raw, filtered, timestamps,
  markers, spike batches, channel labels, encoding metadata, and hardware
  provenance

Start with:

- [Flagship workflow](docs/flagship_workflow.md)
- [Session artifact contract](docs/session_artifact_contract.md)
- [Cyton acceptance prep runbook](docs/cyton_acceptance_runbook.md)
- [Benchmark baselines](docs/benchmarks.md)
- [Toolkit handoff guide](docs/integration_guide_neurosense_to_toolkit.md)
- [Connecting a device](docs/user_guide_connecting_device.md)

## Support Levels

| Path | Support level | Notes |
| --- | --- | --- |
| Canonical session artifact, replay, export | `validated` | Covered by checked-in fixture and automated tests. |
| Synthetic BrainFlow acquisition path | `validated` | Used to exercise recording/replay behavior without hardware. |
| OpenBCI Cyton forearm EMG path | `experimental` | Default real-board target, but not yet physically validated end to end. |
| OpenBCI Ganglion, Muse, BITalino discovery/connectivity paths | `experimental` | Present in code surface, not yet validated as the flagship workflow. |
| PYNQ ingestion path | `prototype` | Design/integration work exists; do not treat as hardware-ready. |
| Prophesee event-camera path | `prototype` | Integration plan and code exist; not equivalent to the flagship EMG path. |

## Credibility Notes

- No physical board has been validated in this slice.
- Fixture-backed flagship benchmark baselines now exist for artifact load,
  filtering, encoding, and replay throughput. Real-board benchmark evidence is
  still pending the first no-mock Cyton acceptance run.
- NeuroCNL and Neurobench now have canonical artifact handoff entrypoints; see
  the integration guide for the current file-based workflow and its scope.

## Development

NeuroSense uses [mypy](http://mypy-lang.org/) for static type checking. The core
package (`neurosense/`) is maintained with a strict zero-error baseline.

```bash
python3 -m mypy neurosense/
```
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/README.md**
```
# Neurochip

## Production Deployment

### Container Hardening
The production Docker image is built using a multi-stage process and runs as a non-root user for enhanced security. Resource limits are configured in `docker-compose.yml` to ensure system stability.

### Hardware Access
To flash firmware to hardware (e.g., Teensy 4.1) from within the container, you must pass through the serial device.

#### Docker CLI
```bash
docker run --device=/dev/ttyACM0:/dev/ttyACM0 neurochip-prod
```

#### Docker Compose
Add the following to your `docker-compose.yml`:
```yaml
services:
  backend:
    devices:
      - "/dev/ttyACM0:/dev/ttyACM0"
```
*Note: The exact device path may vary (e.g., `/dev/ttyUSB0`).*
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurobench/README.md**
```
# Neurobench

Repository for Neuro Bench, part of the NeuroMorphic Tool Kit
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurohub/README.md**
```
# Neurohub

Neurohub is the community registry for the neuromorphic computing field — a searchable platform for sharing and discovering pre-trained SNN models, neuromorphic datasets, hardware profiles, NeuroCNL spec templates, encoding presets, and benchmark baselines.

Think HuggingFace Hub, but built for spike-based computing.

## Documentation

- [Spec](neurohub_spec.md): Full feature specification, data models, API reference, and frontend design.
- [User Guide](docs/neurohub/user_guide.md): Uploading, searching, and importing artefacts.
- [Developer Guide](docs/neurohub/developer_guide.md): Extending the registry and integrating NMTK modules.
- [API Reference](docs/neurohub/api_reference.md): Comprehensive REST API documentation.
- [CLI Reference](docs/neurohub/cli_reference.md): `neurohub push`, `pull`, `search` commands.

## Artefact Types

| Type | Description |
|---|---|
| **SNN Models** | Pre-trained spiking neural networks with weights, architecture, and hardware target |
| **Datasets** | Neuromorphic datasets — event streams (.aedat), EMG, EEG, spike recordings |
| **Hardware Profiles** | Device specs and quantisation configs for Loihi 2, SpiNNaker 2, Akida, and more |
| **CNL Spec Templates** | Reusable NeuroCNL specifications for common tasks |
| **Encoding Presets** | NeuroSense spike encoding configurations for specific sensor modalities |
| **Benchmark Baselines** | Reference NeuroBench result sets with methodology notes |

## Features

- **Search & Filter**: Full-text search with filters for hardware target, neuron model, task, licence, and NeuroBench score.
- **Model Cards**: Structured documentation for every artefact — architecture, training data, performance, limitations, citation.
- **Versioning**: Semantic versioning with stable URIs (`neurohub://models/owner/slug@version`).
- **NeuroBench Integration**: Community-contributed benchmark scores per hardware target, surfaced directly on model cards.
- **NMTK In-App Panel**: Browse and import artefacts directly from NeuroSim, NeuroCNL, NeuroSense, and NeuroChip without leaving the app.
- **Organisations**: Publish artefacts under lab or team namespaces.
- **CLI**: `neurohub push / pull / search` for terminal-based workflows.

## Quick Start

```bash
# Install the CLI
pip install neurohub-cli

# Search for an EMG model targeting Loihi 2
neurohub search "EMG gesture" --type snn_model --hardware loihi2

# Download a model
neurohub pull neurohub://models/intel-ncl/loihi2-gesture-classifier@latest

# Publish your own model
neurohub login
neurohub push ./my_model/ --type snn_model
```

## Relationship to Other NMTK Modules

Neurohub is a **read/write community store** — it has no runtime dependency on other NMTK services. NMTK modules call Neurohub's API to import artefacts; Neurohub never calls theirs. This keeps it independently deployable and usable outside the full NMTK suite.

> **Note:** The suite orchestration and project management layer is **NeuroDash** (`/NeuroDash`), a separate module. Neurohub is exclusively the community registry.
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neuro-Dream-Hand/README.md**
```
# The Neuro-Dream Hand: Neuromorphic Control & Continual Learning


![Python](https://img.shields.io/badge/Python-3.11-blue?logo=python&logoColor=white)
![Nengo](https://img.shields.io/badge/Nengo-SNN_Simulator-green)
![MuJoCo](https://img.shields.io/badge/MuJoCo-Physics_Engine-orange)
![License](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)
[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/Completed-Spoon-6/jku-thesis-dream-hand-nengo-mujoco/blob/main/demo.ipynb)

**A neuromorphic simulation framework for testing adaptive SNN control policies for prosthetic hand control, using Nengo and MuJoCo.**

This repository contains the code and implementation for the "Dreaming Prosthetic" thesis project. It demonstrates how biologically inspired neural networks can control a physics-based robotic hand, learn from reflexes in real-time, and consolidate memory during "sleep" phases.

---

## ⚡ Quick Start for Recruiters / Reviewers

**Want to see it in action without installing anything?**

Click the **[Open In Colab](https://colab.research.google.com/github/Completed-Spoon-6/jku-thesis-dream-hand-nengo-mujoco/blob/main/demo.ipynb)** badge above to launch a cloud instance. The notebook will:
1.  Install the package and MuJoCo physics engine.
2.  Run the **Online Continual Learning** simulation.
3.  Display the result video directly in your browser.

---

## Project Status

This project is in active development. The simulation phases (1–3) are complete and tested. Software for the hardware phases (4–5) has been written and unit-tested against mocks, but has not yet been validated on physical hardware.

| Area | Status |
| :--- | :--- |
| Nengo SNN control (LIF neurons) | Complete |
| MuJoCo physics co-simulation | Complete |
| PES learning — offline sleep training | Complete |
| Online Continual Learning (OCL) | Complete |
| Multi-day wake/sleep consolidation experiments | Complete |
| Drop test benchmarks and hyperparameter sweeps | Complete |
| Weight quantization analysis (4–8 bit, Loihi 2/Akida) | Complete |
| Crossbar weight export to HDF5 | Complete — tested with mocked HDF5 I/O |
| Fault injection (dead neurons, stuck-at, noise) | Complete — three injection modes, seeded RNG |
| Energy profiling (pJ/SOP) | Complete — CPU-estimated, not on-chip measured |
| Serial bridge to physical actuator (Teensy 4.0) | Code complete — tested with mocked serial port, awaiting real hardware |
| Force/tactile sensor ingestion (FSR/load cell) | Code complete — calibration script ready, awaiting real hardware |
| EMG ingestion (OpenBCI Ganglion via BrainFlow) | Code complete — tested with mocked BrainFlow, awaiting real hardware |
| EMG-to-spike encoder | Code complete — bandpass→envelope→normalize pipeline tested |
| Neuromorphic chip deployment (Loihi 2 via nengo-loihi) | Code complete — requires Intel Loihi 2 SDK and hardware access |

> **Simulated efficiency note:** Because the SNN runs on a standard CPU via Nengo, the energy-efficiency claims of neuromorphic hardware (Joules-per-spike) are not physically realized. The quantization analysis models what weight resolution a chip would require, but does not measure actual on-chip power.

See [`STATUS.md`](STATUS.md) for a detailed assessment of the library's current maturity, what it succeeds at, and what remains to be done for production readiness. See [`SPEC.md`](SPEC.md) for the full engineering specification covering the hardware phases.

---

## Project Overview

The goal of this project is to explore adaptive neuromorphic control for assistive robotic devices, using a physics-accurate simulation as a validation environment before committing to physical hardware.

Using the [Nengo](https://www.nengo.ai/) neural simulator and the [MuJoCo](https://mujoco.org/) physics engine, the current simulation implements a closed-loop control system that:
1.  **Detects Slips:** Uses proprioceptive feedback (z-axis velocity) to detect when a grasped object is slipping.
2.  **Reflexively Reacts:** A spinal-cord-like reflex circuit boosts grip force immediately upon slip detection.
3.  **Learns Online:** Uses the **Prescribed Error Sensitivity (PES)** learning rule to adapt synaptic weights in real-time, reducing future slips.
4.  **Consolidates Memory:** Mimics biological sleep by replaying successful grasp trajectories to reinforce learning offline.

### What is and is not demonstrated

The following claims are supported by the current code:

- An SNN running PES online learning can maintain grip under random force perturbations in simulation, achieving >95% survival rate after <5 s of interaction.
- A sleep/wake consolidation cycle progressively reduces stopping distance over 30 simulated days.
- Weight quantization to 4-bit degrades control stability in a measurable, sweep-able way.

The following claims require the hardware phases described in [`SPEC.md`](SPEC.md) before they can be evaluated:

- Native sensor fusion of real EMG intent and physical tactile feedback.
- Latency of the neuromorphic control loop under real I/O constraints.
- Energy-per-inference on a neuromorphic chip.
- Sim-to-real gap between MuJoCo and a physical 1-DOF testbed.

---

## 🛠️ Installation

This project requires **Python 3.11+**. We recommend using `conda` for environment management.

```bash
# 1. Clone the repository
git clone https://github.com/Completed-Spoon-6/Neuro-Dream-Hand
cd jku-thesis-dream-hand-nengo-mujoco

# 2. Create the environment
conda env create -f environment.yml

# 3. Activate the environment
conda activate nengo-mujoco

# 4. Install the neurodreamhand package (editable mode)
pip install -e .
```

### The `neurodreamhand` Package

The core logic is packaged as `neurodreamhand` — a pip-installable Python library:

```
neurodreamhand/
├── core/          # MuJoCo bridges (PinchBridge, TripodBridge), reflex agent & CNL integration
├── learning/      # PES sleep training, online continual learning, memory buffer
├── hardware/      # Weight quantization (complete); crossbar export & fault injection (stubs)
├── analytics/     # Publication plot generation (complete); power profiling (stub)
└── experiments/   # Drop tests, τ sweeps, multi-day validation runner, config

cnl-specs/
├── reflex_arc.cnl # Layer 2 behavioral spec for the spiking PD reflex controller
└── sleep_arc.cnl  # Layer 2 behavioral spec for the sleep/dream replay network
```

After `pip install -e .`, three CLI tools are available:

```bash
neurodreamhand-sweep   # Factorial experiment sweep (days × neurons × seeds)
neurodreamhand-plot    # Generate publication figures from CSV results
neurodreamhand-quantize # Hardware-aware INT-N weight quantization sweep
```

You can also import directly:

```python
from neurodreamhand.core.mujoco_env import PinchBridge, simulate_drop
from neurodreamhand.core.reflex_agent import run_reflex
from neurodreamhand.learning.sleep_pes import run_sleep
from neurodreamhand.learning.ocl_engine import run_online_learning
from neurodreamhand.hardware.quantization import quantize_weights
```

### Dependencies
- `nengo`: For building and running Spiking Neural Networks.
- `neurocnl`: For compiling Controlled Natural Language specs into validated Nengo networks (3-layer architecture).
- `mujoco`: For physics simulation.
- `numpy`, `scipy`, `matplotlib`: For numerical processing and analysis.
- `mediapy`, `ffmpeg`: For rendering and saving video simulations.

---

## 🧬 CNL Behavioral Specifications (3-Layer Architecture)

Neuron-level parameters (LIF time constants, thresholds, synaptic weights) are defined in **Controlled Natural Language** (`.cnl`) files and compiled via the [`neurocnl`](https://pypi.org/project/neurocnl/) library. This implements the project's 3-layer architecture:

| Layer | Role | Example |
| :--- | :--- | :--- |
| **Layer 1 — Physical Invariants** | Non-negotiable biological laws (NeuroML) | τ > 0, threshold > resting potential |
| **Layer 2 — Behavioral Spec** | Human-readable CNL source of truth | `The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0` |
| **Layer 3 — Validation Assertions** | Auto-generated pytest tests | Verifies spike timing, refractory compliance, weight propagation |

### CNL Spec Files

```
cnl-specs/
├── reflex_arc.cnl   # Reflex controller neuron params (Kp=15.0, τ_rc=0.02, τ_ref=0.002)
└── sleep_arc.cnl    # Sleep replay network params (weight=1.0, same LIF config)
```

### Compiling and Validating Specs

```bash
# Validate a spec against Layer 1 invariants + generate Layer 3 assertions
python scripts/compile_cnl.py cnl-specs/reflex_arc.cnl
```

### Static Analysis (Strict Typing)

The core library enforces strict type checking using `mypy`. This is checked in CI and can be run locally:

```bash
# Run strict mypy check on all core packages
python3 -m mypy --strict neurodreamhand/core/ neurodreamhand/experiments/ neurodreamhand/hardware/ neurodreamhand/learning/ neurodreamhand/contracts/
```

We maintain a zero-error budget for these packages to prevent API drift. See `MYPY_BUDGET.md` for details.

### Using CNL Specs in Controllers

Controllers accept an optional `cnl_spec_path` parameter. When provided, neuron parameters are loaded from the validated CNL spec instead of using hardcoded defaults:

```python
from neurodreamhand.core.reflex_agent import SNNController

# CNL-driven: params loaded from validated spec
ctrl = SNNController(cnl_spec_path="cnl-specs/reflex_arc.cnl")

# Equivalent to the hardcoded default:
ctrl = SNNController(kp=15.0, tau_fast=0.02)
```

---

## 📖 Usage Guide

The project is structured as a step-by-step tutorial, evolving from basic physics to advanced learning.

| Script | Description |
| :--- | :--- |
| `step1_hello_physics.py` | **Hello World:** Drops a box on a plane to verify MuJoCo physics. |
| `step2_gripper.py` | **The Bridge:** Implements the Nengo-MuJoCo interface for a 2-finger gripper. |
| `step3_reflex.py` | **Reflex Arc:** Persistent grip force + reactive boost when slip is detected. |
| `step4_drop_test.py` | **Benchmarks:** Forces an object to slip to measure stopping distance (pre-learning). |
| `step5_sleep.py` | **Offline Learning:** Replays recorded sensor data to train the SNN "while sleeping". |
| `step6_validation.py` | **Verification:** Compares "Day 1" (naive) vs "Day 2" (learned) performance. |
| `step7_online_learning.py` | **Online Learning:** Real-time adaptation (OCL) with continuous perturbations. |
| `step8_ocl_sweep.py` | **Analysis:** Large-scale hyperparameter sweep to map the stability zones of the learning rule. |
| `step9_quantization.py` | **Hardware Analysis:** Sweeps INT-N weight quantization (4–8 bit) to model degradation on neuromorphic chips. |

### Interactive Colab Examples

Several standalone notebooks demonstrate neuroprosthetic scenarios. Click the badges to run them directly in the browser.

| Scenario | Description | Colab Link |
| :--- | :--- | :--- |
| **Fragile Grasp** | The SNN must apply just enough force to counteract gravity without exceeding a strict "crush threshold". | [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/Completed-Spoon-6/jku-thesis-dream-hand-nengo-mujoco/blob/main/examples/example_fragile_grasp.ipynb) |
| **Noisy Sensors** | Simulates severe Gaussian noise injected into the slip velocity sensor. Population coding naturally filters this noise. | [![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/Completed-Spoon-6/jku-thesis-dream-hand-nengo-mujoco/blob/main/examples/example_noisy_sensors.ipynb) |
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neuro-Dream-Hand/THESIS_ROADMAP.md**
```
# Thesis Roadmap: The Dreaming Prosthetic

## 1. Environment Setup (Complete)
- [x] **Task 1.1:** Setup Python environment (Install `nengo`, `mujoco`, `numpy`, `matplotlib`).
- [x] **Task 1.2:** Create `step1_hello_physics.py` (Basic MuJoCo box drop).
- [x] **Task 1.3:** Create `step2_gripper.py` (Nengo + MuJoCo Bridge with Video Export).
- [x] **Task 1.4:** Verify Video Output (Ensure `ffmpeg` and `mediapy` work).

## 2. Phase 1: The Reflex Hand (Complete)
- [x] **Task 2.1:** Implement `SlipDetector` in MuJoCo bridge (extract `qvel` z-axis).
- [x] **Task 2.2:** Build Nengo "Reflex Circuit" (Input: Slip -> Output: Grip Boost).
- [x] **Task 2.3:** Run "Drop Test" (Force object to slip, measure stopping distance).
- [x] **Task 2.4:** Tune Synaptic Filter ($\tau$) for stability.

## 3. Phase 2: The Dreaming Hand (Complete)
- [x] **Task 3.1:** Create `MemoryBuffer` class to save (Slip, Grip, Error) tuples.
- [x] **Task 3.2:** Implement "Sleep Mode" (disconnect MuJoCo, replay Buffer).
- [x] **Task 3.3:** Apply `nengo.PES()` learning rule during sleep.
- [x] **Task 3.4:** Validation: Compare "Day 1" vs "Day 2" performance.

## 4. Phase 3: Online Continual Learning (Complete)
- [x] **Task 4.1:** Implement `OnlineLearner` — active PES during physics simulation.
- [x] **Task 4.2:** Implement perturbation schedule with random force injections.
- [x] **Task 4.3:** Hyperparameter sweep over `learning_rate × error_scale` (`step8`).
- [x] **Task 4.4:** Weight quantization analysis (4–8 bit INT-N) for Loihi 2 / Akida (`step9`).
- [x] **Task 4.5:** Multi-day factorial sweep (30 days × 5000 neurons × seeds).

## 5. Phase 4: Hardware-in-the-Loop Validation (Software Complete, Hardware Pending)
- [x] **Task 5.1:** Write Teensy 4.0 serial driver (`serial_bridge.py`) — code complete, mock-tested.
- [ ] **Task 5.1b:** Validate serial driver on physical Teensy 4.0 hardware.
- [x] **Task 5.2:** Write FSR sensor characterization and HITL latency scripts — code complete.
- [ ] **Task 5.2b:** Measure real round-trip latency and sensor noise on physical hardware.
- [x] **Task 5.3:** Write OpenBCI Ganglion EMG streamer (`emg_streamer.py`) — code complete, mock-tested.
- [ ] **Task 5.3b:** Validate EMG streaming with physical Ganglion board.
- [x] **Task 5.4:** Build EMG spike encoder (`emg_encoder.py`) — bandpass→envelope→normalize pipeline tested.
- [ ] **Task 5.4b:** Validate encoder with live EMG during voluntary contraction.
- [x] **Task 5.5:** Quantify sim-to-real gap: compare drop-test survival rates in simulation vs. physical testbed.

## 6. Phase 5: Neuromorphic Hardware Deployment (Software Complete, Chip Access Pending)
- [x] **Task 6.1:** Implement `crossbar_exporter.py` — conductance mapping and HDF5 export tested.
- [x] **Task 6.2:** Implement `fault_injector.py` — dead-neuron, stuck-at, and Gaussian noise injection tested.
- [x] **Task 6.3:** Implement `power_profiler.py` — CPU-estimated pJ/SOP from spike counts.
- [ ] **Task 6.3b:** Measure actual on-chip power on Loihi 2 or Akida hardware.
- [x] **Task 6.4:** Write Loihi 2 exporter (`loihi_exporter.py`) — code complete, awaiting SDK access.
- [ ] **Task 6.4b:** Compile and run on Intel Loihi 2 hardware (requires NxSDK).
- [ ] **Task 6.5:** Benchmark on-chip latency and energy against the MuJoCo simulation baseline.
```





**Grep Results:**

- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/.understand-anything/knowledge-graph.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/teensy-studio-deployment-plan.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/02-Apr-2026-status-Jules.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurocnl/generated-issues/01-neurocnl-extract-grammar-invariant-and-export-contracts-from-the-spec-plan.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/spinncloud_systems_pitch.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/CODE_HEALTH_ANALYSIS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/toolkit-deployment-rollout.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/docs/index.rst**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/24march-opus.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/29-Mar-2026-status-Claude.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/scripts/publish_github_issues.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues-archive/sent-00-readme-toolkit-deployment-rollout.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocli/issues-archive/22mar1_project_scaffolder.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/SPEC.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neuro-dream-hand/properties/test_hitl_properties.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/08-Apr-2026-status-Codex.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/scripts/verify-contracts-local.sh**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/.github/workflows/contract-verification.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocli/docs/ADR-claude/0004-headless-ci-integration.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/.github/workflows/contract-verification.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/generate_tasks.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/docs/ADR-Gemini/0001-initial-architecture.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/open-brain-import.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/prophesee_pitch.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/QUICK_START_GUIDE.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/innaterra_pitch.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/inrc_project_proposal.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Release readiness/TEENSY_RELEASE_READINESS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/akida-studio-deployment-plan.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/01-Apr-2026-status-Codex.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/.github/workflows/ci.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/scripts/create-github-issues.sh**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurobench/generated-issues/01-neurobench-extract-benchmark-suite-and-regression-contracts-from-the-spec.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neuro-dream-hand/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/.github/PULL_REQUEST_TEMPLATE.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/.github/ISSUE_TEMPLATE/contract-migration.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/README_EXPLORATION_RESULTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/Auto agentic workflows (Jules)/performance-improver.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/issues-archive/008-beta-cross-module-integration-tests.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/.github/ISSUE_TEMPLATE/feature-with-contracts.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Release readiness/PYNQ_RELEASE_READINESS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurocnl/module.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Gemini-dev-pipeline/cdd_validation.sh**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/docs/ADR-Gemini/0002-daemon-module-orchestration.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/assets/modules.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/ADR-claude/0003-rate-limiting-slowapi.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/START_HERE.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurosense/module.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurobench/generated-issues/02-neurobench-add-property-tests-for-benchmark-stability-and-regression-detection.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/08-Apr-2026-neurocnl-neurochip-ndh-pipeline-analysis.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/Merge_maintain.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/ADR-claude/0006-property-based-testing-hypothesis.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Gemini-dev-pipeline/generate_cdd_pbt_issues.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurochip/generated-issues/02-neurochip-add-property-tests-for-deployment-and-quantization-invariants.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/test_integration_plan_PYNQ_Z2.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/.gitignore**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/11-Apr-2026-status-Codex.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/CI_OVERVIEW.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/.github/PULL_REQUEST_TEMPLATE.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurohub/module.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/services/akida_deploy_service.dart**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/overall_pitch_plan.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/synsense_speck_pitch.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/CONTRIBUTING.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurosense/generated-issues/02-neurosense-add-property-tests-for-recording-and-encoding-invariants.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/.github/PULL_REQUEST_TEMPLATE.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurohub/generated-issues/02-neurohub-add-property-tests-for-workflow-dag-and-bundle-integrity.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-CDD-PBT.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/test_integration_plans/test_integration_plan_Sense_Speck.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurocnl/GUARDRAILS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/01-Apr-2026-status-Jules.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/tests/load/locustfile.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neuro-dream-hand/AGENTS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurodocs/issues-archive/22mar1_interactive_docs_browser.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/ADR-claude/0012-self-hosted-ci-runners.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neurocnl_complete_reference.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/jules/JULES_WORKSPACE_GUIDE.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/copilot-CDD-PBT.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurocnl/generated-issues/02-neurocnl-add-property-tests-for-grammar-and-invariant-preservation.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocli/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/intel_labs_pitch.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/docs/ADR-claude/0002-material-design-3-theming.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/ROADMAP.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurohub/contracts/orchestration_contracts.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/issues-archive/008-beta-cross-module-integration-tests.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurochip/properties/test_deployment_properties.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/02-Apr-2026-status-Claude.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/SECURITY.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurocnl/contracts/hardware_export.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/scripts/ci/lib.sh**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/CODE_REVIEW.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/NEUROCNL_EXPLORATION_SUMMARY.txt**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurosim/generated-issues/02-neurosim-add-property-tests-for-canvas-and-simulation-invariants.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/maintenance-improvement.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/.github/ISSUE_TEMPLATE/contract-migration.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/inrc_access_plan_and_drafts.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_ui_core/docs/ADR-claude/0004-domain-specific-widget-library.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/.github/ISSUE_TEMPLATE/feature-with-contracts.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurobench/module.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurochip/module.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/test/akida_deploy_screen_test.dart**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neuro-dream-hand/module.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/Antigravity-CDD-PBT.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/pynq-z2-studio-deployment-plan.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/scripts/verify-contracts-local.sh**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurocnl/properties/test_physics_properties.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/08-Apr-2026-status-Claude.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/requirements-verify.txt**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/revised_pitches_v4.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/tests/integration/test_cross_module.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Release readiness/AKIDA_RELEASE_READINESS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/24march-Jules.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/26march-status.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neurosim/module.json**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/brainchip_pitch.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurobench/contracts/benchmark_contracts.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues/neurosense-research-credibility-rollout.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/.github/ISSUE_TEMPLATE/contract-migration.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/31-Mar-2026-status-Antigravity.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/PYNQ_SUPPORT_SEMANTICS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/revised_pitches_v3.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurocnl/GUARDRAILS.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/README.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues-archive/22-opus-akida-final-integration-review.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/user/installation.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/archive/08-Apr-2026-module-poc-dependency-analysis-Codex.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/neurosense/properties/test_encoding_properties.py**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/issues-archive/21-sonnet-akida-toolkit-ui-and-benchmark-hooks.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/providers/akida_deploy_provider.dart**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/unified-dev-pipeline/neuro-dream-hand/generated-issues/02-neuro-dream-hand-add-property-tests-for-physical-and-hardware-invariants.md**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/Opus-dev-pipeline/.github/workflows/contract-verification.yml**
- **/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/ADR-claude/0015-container-security-hardening.md**




**Files Read:**

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosim/neurosim_spec.md**
```
# NeuroSim — Visual Network Design & Simulation Workbench
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

---

## Overview

NeuroSim is a visual drag-and-drop workbench for designing, parameterizing, and simulating spiking neural networks. It generates neurocnl CNL specs from a graphical canvas, eliminating the need to write spec syntax or Python code. It targets hardware engineers, signal processing specialists, and other professionals who understand systems design but lack computational neuroscience background.

---

## Repository

`neuro-space/NeuroSim` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neurocnl` Python package (pip install) — for CNL parsing, validation, Nengo generation
- `neurocnl` FastAPI backend — consumed via HTTP for simulation and validation
- `neuro-flutter-ui` shared Flutter design system package

---

## User Stories

### Design

**NS-D1 · Place neuron populations on canvas**
As a hardware engineer designing a reflex controller,
I want to drag a "LIF Population" block from the component library onto the canvas,
so that I can visually compose my network without learning CNL syntax.

Acceptance criteria:
- Component library sidebar lists all available blocks grouped by category (Neurons, Synapses, Encoders, Patterns)
- Dragging a block onto the canvas creates a node with default parameters
- Node displays: name, neuron count, neuron model (LIF), and key parameters (threshold, tau_rc, tau_ref)
- Node is selectable, movable, and deletable
- Undo/redo works for all canvas operations

**NS-D2 · Connect populations**
As an engineer building a sensory-motor pathway,
I want to draw a connection from one population to another by clicking an output port and dragging to an input port,
so that I can define the network topology visually.

Acceptance criteria:
- Connections render as directed edges between nodes
- Clicking a connection opens a property panel with: synapse type, weight, learning rule (none/STDP/PES), delay
- Connections validate against Layer 1 invariants in real time (e.g., inhibitory weight must be negative)
- Invalid connections show a warning icon with explanation tooltip
- Multiple connections between the same pair are supported (different synapse types)

**NS-D3 · Configure parameters via property panel**
As an engineer tuning a network,
I want to click any node or connection and edit its parameters in a side panel,
so that I can adjust the network without memorizing parameter names or valid ranges.

Acceptance criteria:
- Property panel shows all configurable parameters with labels, current values, units, and valid ranges
- Parameters have sensible defaults derived from neurocnl Layer 1 invariants
- Out-of-range values show inline validation errors with explanation (e.g., "tau_rc must be > 0. This is the membrane time constant — it controls how quickly voltage decays.")
- Changes apply immediately and update the canvas visualization
- Parameter descriptions include brief functional explanation (what this parameter does in plain engineering terms)

**NS-D4 · Use template starter circuits**
As an engineer unfamiliar with SNN architecture patterns,
I want to start from a pre-built template (reflex arc, CPG oscillator, winner-take-all, lateral inhibition),
so that I can learn by modifying a working design rather than building from scratch.

Acceptance criteria:
- Template gallery shows available templates with: name, thumbnail, description, intended use case
- Selecting a template populates the canvas with the full circuit
- Each template includes parameter annotations explaining design choices
- Templates are versioned and map to specific neurocnl CNL spec versions
- User can save modified templates as custom templates

**NS-D5 · Bidirectional CNL synchronization**
As an engineer who wants to version-control my designs,
I want the canvas to generate a CNL spec in real time, and edits to the CNL to update the canvas,
so that I can work visually or textually as needed.

Acceptance criteria:
- A split-view mode shows the canvas on the left and the generated CNL spec on the right
- Every canvas change immediately updates the CNL text
- Editing the CNL text and pressing "Sync" updates the canvas
- Parse errors in manually edited CNL are highlighted inline with error messages
- The generated CNL is clean, readable, and follows neurocnl style conventions

### Simulation

**NS-S1 · Real-time simulation preview**
As an engineer iterating on a design,
I want to see spike activity update live as I modify the network,
so that I get immediate feedback on how parameter changes affect behavior.

Acceptance criteria:
- A "Preview" panel shows a spike raster plot for all populations
- Preview updates within 2 seconds of any parameter change
- Preview runs a short simulation (default 500ms) via the neurocnl backend `/api/simulate`
- Preview can be paused, resumed, and duration-adjusted
- Simulation status indicator shows: idle / running / error

**NS-S2 · Parameter sweep mode**
As an engineer tuning without deep neuroscience intuition,
I want to select a parameter, define a range, run N simulations, and compare results in a grid,
so that I can find good parameter values empirically.

Acceptance criteria:
- Right-click any parameter → "Sweep this parameter"
- Configure: start value, end value, step count (max 20)
- Results displayed as a grid of spike raster thumbnails, sortable by any output metric
- Clicking a grid cell loads that parameter set onto the canvas
- Sweep runs as a batch job via backend; progress bar shown

**NS-S3 · Full simulation run**
As an engineer validating a design before export,
I want to run a longer simulation with configurable duration and input signals,
so that I can verify the network behaves correctly under realistic conditions.

Acceptance criteria:
- "Run Simulation" button opens a config dialog: duration (ms), input signal type (constant, ramp, step, noise, custom CSV), seed
- Simulation submitted as a background job to the backend
- Results displayed in a dedicated simulation results panel: spike raster, membrane voltage traces, output signals
- Results can be exported as CSV or PNG
- Simulation history is preserved for the session (compare multiple runs)

### Export

**NS-E1 · Export to multiple formats**
As an engineer ready to deploy,
I want to export my design to CNL spec, Nengo Python, C header, NeuroML, or SVG diagram,
so that I can hand off to downstream tools (NeuroChip, firmware build, documentation).

Acceptance criteria:
- Export menu offers: CNL Spec (.cnl), Nengo Python (.py), C Header (.h), NeuroML (.xml), Diagram (SVG/PNG)
- Each export format produces valid, usable output (e.g., C header compiles, Nengo script runs)
- Export includes metadata comments: source NeuroSim version, timestamp, network parameters
- CNL export is the canonical format; all others are derived from it

**NS-E2 · Open in NeuroChip**
As an engineer ready to deploy to hardware,
I want to send my design directly to NeuroChip for compilation and deployment,
so that I don't need to export/import manually.

Acceptance criteria:
- "Deploy to NeuroChip" button available when NeuroChip backend is reachable
- Sends the current CNL spec + network parameters to NeuroChip's API
- Opens NeuroChip in a new tab/window with the design pre-loaded
- If NeuroChip is not available, button is grayed out with tooltip explaining how to start it

### Collaboration

**NS-C1 · Save and load projects**
As an engineer working on a design over multiple sessions,
I want to save my canvas state as a project file and reload it later,
so that I can resume work.

Acceptance criteria:
- Save produces a `.neurosim` JSON file containing: canvas layout, all node/edge parameters, CNL spec, metadata
- Load restores the full canvas state
- Auto-save every 60 seconds to browser local storage (web) or file system (desktop)
- Recent projects list on the home screen

**NS-C2 · Share via URL**
As an engineer collaborating with a colleague,
I want to share my design via a URL,
so that they can open it in their browser without file transfer.

Acceptance criteria:
- "Share" button generates a URL with the project encoded (base64 in query param for small projects, backend-stored for large)
- Opening the URL loads the full canvas state
- Shared projects are read-only by default; recipient can fork to edit

---

## Backend Spec

### API Endpoints

All NeuroSim-specific endpoints live under `/api/neurosim/`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/neurosim/components` | List all available component blocks with parameter schemas |
| GET | `/api/neurosim/templates` | List all starter circuit templates |
| GET | `/api/neurosim/templates/{id}` | Get a specific template (canvas layout + CNL spec) |
| POST | `/api/neurosim/validate` | Validate a canvas graph against Layer 1 invariants |
| POST | `/api/neurosim/generate-cnl` | Convert a canvas graph to a CNL spec |
| POST | `/api/neurosim/parse-cnl` | Convert a CNL spec to a canvas graph (reverse direction) |
| POST | `/api/neurosim/preview` | Run a short simulation for real-time preview (≤500ms sim time) |
| POST | `/api/neurosim/sweep` | Run a parameter sweep (batch of simulations) |
| POST | `/api/neurosim/export/{format}` | Export the network to the specified format |
| POST | `/api/neurosim/projects` | Save a project |
| GET | `/api/neurosim/projects/{id}` | Load a project |
| GET | `/api/neurosim/projects` | List saved projects |

### Data Models

**ComponentBlock**
```python
class ComponentBlock(BaseModel):
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/neurosense_spec.md**
```
# NeuroSense — Biosignal Acquisition & Spike Encoding Toolkit
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

---

## Overview

NeuroSense is a unified tool for acquiring, processing, spike-encoding, and piping biosignals (EMG, EEG, EOG, ECG) into the Neuro-space pipeline. It targets embedded engineers and chip designers who need real biological input signals for their neuromorphic systems but have no experience with biosignal acquisition, electrode placement, filtering, or neural encoding.

---

## Repository

`neuro-space/NeuroSense` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neurocnl` Python package — for spike encoding utilities and pipeline integration
- `brainflow` Python package — for device communication
- `neuro-flutter-ui` shared Flutter design system package

---

## User Stories

### Device Management

**NSe-DM1 · Auto-detect connected devices**
As a chip designer who has never used biosignal hardware,
I want the app to auto-detect my connected OpenBCI Ganglion,
so that I don't need to know serial port names or device protocols.

Acceptance criteria:
- On startup and on "Refresh", scan for supported devices via BrainFlow discovery
- Show detected devices with: name, type (Ganglion/Cyton/Muse/BITalino), serial port, connection status
- Supported devices: OpenBCI Ganglion, OpenBCI Cyton, Muse 2/S, BITalino, generic serial ADC
- "Connect" button establishes the connection; "Disconnect" cleanly releases it
- Connection errors show human-readable messages (e.g., "Ganglion not found — is Bluetooth enabled?")

**NSe-DM2 · Guided electrode setup**
As a non-specialist setting up EMG electrodes for the first time,
I want step-by-step placement instructions with diagrams,
so that I get usable signals without studying anatomy.

Acceptance criteria:
- After connecting a device and selecting a signal type (EMG/EEG/EOG), show a setup wizard
- Wizard includes: electrode placement diagram (body diagram with marked positions), step-by-step text instructions, impedance check
- Impedance check shows per-channel values with green/yellow/red indicators
- "Verify" button runs a quick signal quality check and confirms the setup is working
- Presets available: "Forearm EMG (2-channel)", "Occipital EEG (O1/O2)", "Horizontal EOG"

### Signal Acquisition & Viewing

**NSe-SA1 · Live multi-channel signal viewer**
As an engineer verifying signal quality,
I want to see real-time waveforms for all channels with configurable filters,
so that I can confirm I'm getting clean data before feeding it into my SNN.

Acceptance criteria:
- Scrolling waveform display for up to 8 channels simultaneously
- Configurable per-channel: bandpass filter (cutoff frequencies), notch filter (50 Hz or 60 Hz), gain
- Each signal type has a sensible default filter preset (e.g., EMG: 20-450 Hz bandpass + 50 Hz notch)
- Time axis configurable: 1s, 5s, 10s, 30s window
- Amplitude axis auto-scales or manual range
- Pause/resume without losing data
- Latency from acquisition to display < 50ms

**NSe-SA2 · Signal quality dashboard**
As a non-specialist troubleshooting poor signals,
I want per-channel quality indicators that tell me what's wrong,
so that I can fix electrode issues without signal processing expertise.

Acceptance criteria:
- Per-channel indicators: SNR (dB), noise floor (µV RMS), impedance (kΩ), power line interference level
- Color coding: green (good), yellow (marginal), red (unusable)
- Actionable suggestions for red channels: "High noise on Ch2 — check electrode contact" or "60 Hz interference detected — enable notch filter"
- Quality dashboard updates in real time during acquisition

### Spike Encoding

**NSe-SE1 · Real-time spike encoding with visual comparison**
As an engineer who understands digital signals but not neural encoding,
I want to see my analog biosignal converted to spikes in real time with three encoding methods side by side,
so that I can understand and choose the right encoding for my application.

Acceptance criteria:
- Three-panel view: raw filtered signal → rate-encoded spikes → temporal-encoded spikes → delta-encoded spikes
- Each panel shows the spike train as a raster and the analog signal as an overlay
- Encoding parameters are adjustable per method (e.g., rate encoding: max rate Hz; delta: threshold µV)
- Tooltip on each encoding method: one-paragraph explanation of when to use it
- Spike rate counter per channel per encoding method

**NSe-SE2 · Application presets for common use cases**
As an engineer who doesn't want to manually configure encoding,
I want to select a preset like "EMG for prosthetic control" and get a complete acquisition + encoding pipeline,
so that I can start getting spike-encoded data in under a minute.

Acceptance criteria:
- Presets available:
  - "EMG for prosthetic control" — 20-450 Hz bandpass, envelope extraction, rate encoding at 200 Hz max
  - "EEG alpha band for BCI" — 8-13 Hz bandpass, PSD, threshold encoding
  - "EOG for gaze tracking" — DC-coupled, delta modulation at 5 µV threshold
  - "Tactile sensor array" — multi-channel delta encoding, 10 µV threshold
- Selecting a preset configures: device channel mapping, filters, encoding method, encoding parameters
- Presets are editable — user can modify and save as custom presets
- Preset metadata includes: description, intended application, recommended electrode placement

### Recording & Playback

**NSe-R1 · Record sessions with event annotations**
As an engineer building a training dataset for my SNN,
I want to record biosignal sessions with timestamped event markers,
so that I can replay specific segments into my pipeline.

Acceptance criteria:
- "Record" button starts capturing raw + encoded data to disk
- Event marker button (or keyboard shortcut) inserts a timestamped annotation (e.g., "subject flexed wrist")
- Recording saves: raw analog data, filtered data, spike-encoded data, event markers, device config, filter settings
- File formats: HDF5 (primary, structured), CSV (interop)
- Recording metadata: timestamp, duration, device, preset, subject ID (optional)
- Maximum recording duration: limited only by disk space

**NSe-R2 · Replay recorded sessions into the pipeline**
As an engineer doing offline SNN development,
I want to replay a recorded session as if it were live data,
so that I can iterate on my SNN without needing a live subject every time.

Acceptance criteria:
- Load a saved HDF5 session → replay button plays it back at real-time speed (or configurable 0.5x–10x)
- Replay outputs appear in the same live viewer as real acquisition
- Replay can be piped directly to `/api/simulate` as spike-encoded input
- Seek bar allows jumping to specific timestamps or event markers
- Multiple sessions can be concatenated for longer replay sequences

### Pipeline Integration

**NSe-PI1 · Direct pipeline integration with neurocnl**
As an engineer testing my SNN with real biosignal input,
I want to route live or replayed spike-encoded data directly into the neurocnl simulation pipeline,
so that I can see my network respond to real biological signals.

Acceptance criteria:
- "Connect to Pipeline" button establishes a WebSocket connection to the neurocnl backend
- Spike-encoded data streams as input to whichever SNN is currently loaded in the Studio or NeuroSim
- Simulation results (motor output, spike raster) are displayed alongside the input signal
- Latency from biosignal acquisition to simulation output < 100ms for real-time applications
- Works with both live acquisition and session replay

**NSe-PI2 · Export spike-encoded data for offline use**
As an engineer sharing data with colleagues,
I want to export spike-encoded data in formats compatible with other tools,
so that it can be used independently of NeuroSense.

Acceptance criteria:
- Export formats: HDF5 (spike times + channel IDs), CSV (timestamp, channel, spike), Nengo input format (Python pickle), AEDAT (for compatibility with neuromorphic datasets)
- Export can be full session or a time-windowed segment
- Export includes metadata: encoding method, parameters, source signal type, sampling rate

---

## Backend Spec

### API Endpoints

All NeuroSense-specific endpoints live under `/api/neurosense/`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/neurosense/devices` | Scan and list available biosignal devices |
| POST | `/api/neurosense/devices/{id}/connect` | Connect to a specific device |
| POST | `/api/neurosense/devices/{id}/disconnect` | Disconnect from a device |
| GET | `/api/neurosense/devices/{id}/impedance` | Run impedance check |
| GET | `/api/neurosense/presets` | List available application presets |
| GET | `/api/neurosense/presets/{id}` | Get a specific preset configuration |
| POST | `/api/neurosense/presets` | Save a custom preset |
| WS | `/api/neurosense/stream/raw` | WebSocket: stream raw analog data from device |
| WS | `/api/neurosense/stream/filtered` | WebSocket: stream filtered analog data |
| WS | `/api/neurosense/stream/spikes` | WebSocket: stream spike-encoded data |
| POST | `/api/neurosense/encode` | Encode a batch of analog data to spikes (offline) |
| POST | `/api/neurosense/recording/start` | Start recording a session |
| POST | `/api/neurosense/recording/stop` | Stop recording, return session metadata |
| POST | `/api/neurosense/recording/marker` | Insert an event marker into the active recording |
| GET | `/api/neurosense/sessions` | List recorded sessions |
| GET | `/api/neurosense/sessions/{id}` | Get session metadata |
| GET | `/api/neurosense/sessions/{id}/download` | Download session data (HDF5) |
| POST | `/api/neurosense/sessions/{id}/replay` | Start replaying a session |
| POST | `/api/neurosense/sessions/{id}/replay/stop` | Stop replay |
| GET | `/api/neurosense/quality` | Get current signal quality metrics for connected device |
| POST | `/api/neurosense/export` | Export spike-encoded data in specified format |

### Data Models

**DeviceInfo**
```python
class DeviceInfo(BaseModel):
    id: str                              # Unique device identifier
    name: str                            # e.g., "OpenBCI Ganglion"
    type: str                            # e.g., "ganglion", "cyton", "muse"
    serial_port: str | None              # e.g., "/dev/ttyACM0"
    channels: int                        # Number of analog channels
    sampling_rate_hz: int                # Native sampling rate
    connected: bool
    battery_pct: int | None              # If available
```

**AcquisitionPreset**
```python
class AcquisitionPreset(BaseModel):
    id: str                              # e.g., "emg_prosthetic"
    name: str                            # e.g., "EMG for Prosthetic Control"
    signal_type: str                     # "emg", "eeg", "eog", "ecg", "tactile"
    description: str
    electrode_placement: str             # Markdown with placement instructions
    electrode_diagram: str               # Path to diagram image
    channel_mapping: dict[int, str]      # e.g., {0: "flexor", 1: "extensor"}
    filter_config: FilterConfig
    encoding_config: EncodingConfig
    recommended_device: str              # e.g., "ganglion"
```

```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/neurochip_spec.md**
```
# NeuroChip — Hardware Deployment & Compilation Toolkit
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

---

## Overview

NeuroChip is a dedicated tool for compiling, constraining, and deploying SNN models to neuromorphic chips and embedded microcontrollers. It targets neuroscience researchers and SNN algorithm developers who can design networks in simulation but have no experience with chip architectures, weight quantization, memory constraints, or firmware toolchains.

---

## Repository

`neuro-space/NeuroChip` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neurocnl` Python package — for CNL parsing, validation, Nengo generation
- `neurodreamhand` Python package — for crossbar export, fault injection, power profiling
- `neuro-flutter-ui` shared Flutter design system package

---

## User Stories

### Target Selection

**NC-T1 · Browse hardware targets**
As a neuroscience researcher unfamiliar with chip architectures,
I want to browse available hardware targets with plain-language descriptions of their capabilities and constraints,
so that I can make an informed deployment decision without reading chip datasheets.

Acceptance criteria:
- Target gallery shows cards for each supported platform: Teensy 4.1, Intel Loihi 2, BrainChip Akida, SpiNNaker, BrainScaleS
- Each card displays: name, photo/icon, neuron capacity, supported neuron models, weight bit-width, on-chip memory, I/O count, power envelope, cost/access notes
- Cards are filterable by: neuron capacity, bit-width, availability (open vs. restricted access)
- Selecting a target loads its hardware profile for constraint analysis

**NC-T2 · Compare targets side by side**
As a product team lead evaluating deployment options,
I want to compare two or more hardware targets on the same network,
so that I can see tradeoffs (capacity, power, latency, quantization loss) at a glance.

Acceptance criteria:
- Multi-select targets → comparison table auto-populates
- Comparison columns: neuron capacity fit, weight quantization required, estimated power, estimated latency, compatibility warnings
- Rows highlight where a target fails constraints (e.g., "Network exceeds neuron capacity — requires partitioning")
- Export comparison as PDF or CSV

### Constraint Analysis

**NC-C1 · Automatic compatibility report**
As a researcher loading my Nengo model,
I want to see an immediate compatibility report for my selected target,
so that I know what needs to change before deployment.

Acceptance criteria:
- Load a network (via CNL spec, Nengo export, or direct from NeuroSim)
- Report shows: neuron count vs. target capacity, weight bit-width vs. target bit-width, memory usage estimate, unsupported features (if any)
- Each constraint is green (pass), yellow (requires modification), or red (incompatible)
- Yellow items link to the relevant tool (e.g., "Weights are 32-bit → open Quantization Explorer")

**NC-C2 · Network partitioning suggestions**
As an engineer deploying a large network to a small target,
I want automatic partitioning suggestions when my network exceeds the target's neuron capacity,
so that I don't have to manually split the network.

Acceptance criteria:
- When neuron count exceeds target capacity, suggest partition strategies: by population, by function, by connectivity clusters
- Show partition diagram with: sub-network boundaries, inter-partition communication overhead, estimated latency impact
- User can accept a suggestion or manually adjust partition boundaries
- Partitioned network exports as multiple deployment packages

### Quantization

**NC-Q1 · Interactive weight quantization explorer**
As a researcher who has never quantized weights,
I want to interactively adjust bit-width and see accuracy impact in real time,
so that I can find the best tradeoff without understanding quantization theory.

Acceptance criteria:
- Slider for bit-width: 2, 4, 6, 8, 16, 32 bits
- Live chart: accuracy metric vs. bit-width curve
- Side-by-side spike raster: original (float32) vs. quantized at selected bit-width
- Accuracy metric is task-specific (e.g., grip stability for prosthetic, classification accuracy for pattern recognition)
- Summary text: "8-bit quantization: 1.2% accuracy loss, 4x memory reduction"

**NC-Q2 · Batch quantization comparison**
As an engineer optimizing for power/area,
I want to run all quantization levels at once and compare in a table,
so that I can present options to my team.

Acceptance criteria:
- "Run All" button runs simulations at 4-bit, 6-bit, 8-bit, 16-bit
- Results table: bit-width, accuracy, memory size, estimated power, spike fidelity score
- Export table as CSV or include in PDF report
- Highlight the Pareto-optimal choices

### Fault Tolerance

**NC-F1 · Fault injection analysis**
As an engineer designing for reliability,
I want to inject hardware faults (dead neurons, stuck-at values, weight noise) and see how my network degrades,
so that I can verify robustness before committing to silicon.

Acceptance criteria:
- Fault types: dead neuron (random N%), stuck-at-zero, stuck-at-max, Gaussian weight noise (configurable sigma)
- Sweep fault rate from 0% to 30% in configurable steps
- Output: robustness curve (accuracy vs. fault rate) with confidence intervals
- Threshold line: "Network maintains >90% accuracy up to X% dead neurons"
- Compare robustness across quantization levels

### Firmware Generation & Deployment

**NC-FW1 · One-click Teensy firmware generation**
As a researcher who has never written C firmware,
I want to click one button to generate compilable Teensy firmware from my validated network,
so that I can deploy to hardware without learning embedded development.

Acceptance criteria:
- "Generate Firmware" button produces a complete Arduino/PlatformIO project: `.ino` file, `network_params.h`, `lif_engine.h`, `README.md`
- Generated code compiles without errors in Arduino IDE or PlatformIO
- `network_params.h` contains all weights, thresholds, time constants as C arrays
- `lif_engine.h` contains the LIF update loop matching the network topology
- README explains: how to compile, how to flash, pin mappings for sensors/actuators

**NC-FW2 · Flash to Teensy via serial**
As an engineer with a Teensy connected via USB,
I want to compile and flash the generated firmware directly from NeuroChip,
so that I don't need to switch to another IDE.

Acceptance criteria:
- Serial port auto-detection shows available Teensy devices
- "Compile & Flash" button triggers PlatformIO build + upload via backend
- Progress indicator: compiling → uploading → verifying → done
- Error messages are human-readable (not raw compiler output)
- Fallback: download the project as a .zip for manual compilation

**NC-FW3 · Loihi 2 deployment package**
As a lab with Loihi 2 access,
I want to generate a complete NxSDK deployment package,
so that I can run my network on Loihi without learning the NxSDK API from scratch.

Acceptance criteria:
- "Export for Loihi 2" generates: NxSDK Python script, crossbar HDF5 file, configuration JSON, README
- Script handles: board allocation, network compilation, spike probe setup, run execution
- HDF5 file contains quantized weights in Loihi crossbar format
- README documents: prerequisites (NxSDK version, board access), how to run, expected output

### Power & Latency Estimation

**NC-P1 · Pre-deployment power estimate**
As a product designer with a power budget,
I want to see estimated energy per inference before deploying,
so that I can verify my network fits within the product's power envelope.

Acceptance criteria:
- Power estimate based on: spike count per inference, target's pJ/spike-op, network topology
- Display: total energy (pJ), per-population breakdown, comparison to target's power envelope
- Warning if estimated power exceeds target's typical operating range
- Estimates are clearly labeled as "estimated — measure on real hardware for production"

**NC-P2 · Latency estimate**
As a real-time systems engineer,
I want worst-case latency estimates for my network on each target,
so that I can verify timing constraints.

Acceptance criteria:
- Latency estimate based on: network depth (longest path in timesteps), target's clock speed, inter-core communication overhead
- Display: best-case, typical, worst-case latency in microseconds
- Comparison across targets in the comparison view

### Deployment Tracking

**NC-DT1 · Deployment log**
As a team managing multiple hardware prototypes,
I want to see a log of what model was deployed to which device, when, and with what parameters,
so that I can reproduce any deployment.

Acceptance criteria:
- Log entry records: timestamp, network CNL spec hash, target, quantization settings, firmware version, serial port/device ID
- Log is searchable and filterable
- Clicking a log entry shows full deployment details and lets you re-deploy the same configuration
- Export log as CSV

---

## Backend Spec

### API Endpoints

All NeuroChip-specific endpoints live under `/api/neurochip/`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/neurochip/targets` | List all hardware target profiles |
| GET | `/api/neurochip/targets/{id}` | Get a specific hardware profile |
| POST | `/api/neurochip/analyze` | Run constraint analysis (network + target → compatibility report) |
| POST | `/api/neurochip/partition` | Suggest network partitioning for a target |
| POST | `/api/neurochip/quantize` | Run quantization analysis at specified bit-widths |
| POST | `/api/neurochip/quantize/batch` | Run all quantization levels and return comparison |
| POST | `/api/neurochip/faults` | Run fault injection sweep |
| POST | `/api/neurochip/estimate/power` | Estimate power consumption for network + target |
| POST | `/api/neurochip/estimate/latency` | Estimate latency for network + target |
| POST | `/api/neurochip/export/teensy` | Generate Teensy firmware project |
| POST | `/api/neurochip/export/loihi` | Generate Loihi 2 NxSDK deployment package |
| POST | `/api/neurochip/export/lava` | Generate Intel Lava deployment script |
| POST | `/api/neurochip/export/neuroml` | Export to NeuroML format |
| GET | `/api/neurochip/serial/ports` | List available serial ports |
| POST | `/api/neurochip/serial/flash` | Compile and flash firmware to connected Teensy |
| GET | `/api/neurochip/serial/flash/{job_id}` | Poll flash job status |
| GET | `/api/neurochip/deployments` | List deployment log entries |
| POST | `/api/neurochip/deployments` | Record a deployment |
| POST | `/api/neurochip/compare` | Compare multiple targets for the same network |

### Data Models

**HardwareProfile**
```python
class HardwareProfile(BaseModel):
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurobench/neurobench_spec.md**
```
# NeuroBench — Test & Benchmarking Workbench
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

---

## Overview

NeuroBench is a testing and benchmarking workbench for evaluating SNN performance across the full stack: algorithm accuracy, hardware efficiency, robustness, and real-world signal fidelity. It targets product teams building neuromorphic systems who need to systematically compare designs, validate robustness, and produce evidence for design reviews and certification.

---

## Repository

`neuro-space/NeuroBench` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neurocnl` Python package — for CNL parsing, validation, simulation
- `neurodreamhand` Python package — for fault injection, power profiling, quantization analysis
- `neuro-flutter-ui` shared Flutter design system package
- Optionally integrates with NeuroChip (cross-target comparison) and NeuroSense (real-signal benchmarks)

---

## User Stories

### Benchmark Execution

**NB-B1 · Run a standard benchmark**
As an engineer evaluating a network design,
I want to select a standard benchmark (e.g., grip stability, spike classification) and run it against my network,
so that I get a normalized performance score I can compare to other designs.

Acceptance criteria:
- Benchmark catalog lists available benchmarks with: name, description, task type, input format, scoring metric
- Built-in benchmarks: grip stability (prosthetic), spike classification accuracy, reaction latency, wake-word detection, pattern recognition
- "Run" button submits the benchmark as a background job
- Results display: score, breakdown by sub-metric, comparison to known baselines (if available)
- Benchmark parameters are configurable (e.g., simulation duration, number of trials, noise level)

**NB-B2 · Run benchmarks in CI/CD**
As a DevOps engineer integrating SNN testing into our build pipeline,
I want to trigger benchmarks via CLI or HTTP and fail the build on regression,
so that performance degradation is caught before deployment.

Acceptance criteria:
- CLI tool: `neurobench run <benchmark_id> --network <spec.cnl> --baseline <baseline.json> --fail-on-regression`
- HTTP API: `POST /api/neurobench/run` with the same parameters
- Exit code 1 (or HTTP 422) if any metric regresses beyond the configured threshold
- JSON output with all metrics, suitable for CI artifact storage
- Baseline file is a previous benchmark result JSON that defines the "pass" thresholds

**NB-B3 · Define custom benchmarks**
As a team with domain-specific requirements,
I want to define custom benchmarks using CNL assertion suites and input datasets,
so that I can test against our product's specific acceptance criteria.

Acceptance criteria:
- Benchmark definition format: JSON manifest with fields: name, description, input_spec (CNL or data file), assertions (CNL assertion suite), scoring_function, pass_threshold
- Custom benchmarks appear in the catalog alongside built-ins
- Benchmarks can reference NeuroSense recordings as input data
- Custom benchmarks are sharable via NeuroHub

### Cross-Target Comparison

**NB-CT1 · Compare the same network across hardware targets**
As a product team deciding between Loihi 2 and Akida,
I want to run the same benchmark on both targets and see accuracy, latency, power, and spike fidelity side by side,
so that I can make a data-driven deployment decision.

Acceptance criteria:
- Select network + benchmark + multiple targets (from NeuroChip's hardware profiles)
- For each target: apply target-specific quantization, run benchmark, collect metrics
- Comparison table: rows = targets, columns = accuracy, latency (est.), power (est.), memory usage, spike fidelity, quantization loss
- Highlight Pareto-optimal targets
- Export comparison as PDF or CSV

**NB-CT2 · Quantify simulation-to-hardware gap**
As an engineer validating that my simulation results hold on real hardware,
I want to compare benchmark results from Nengo simulation vs. a connected Teensy running the same network,
so that I can quantify the sim-to-real gap.

Acceptance criteria:
- Requires NeuroChip + physical hardware connected
- Run benchmark on Nengo (CPU), then flash to Teensy via NeuroChip, run same benchmark with real I/O
- Compare: accuracy, timing, spike counts, output waveforms
- Gap report: per-metric delta, percentage deviation, visual overlay of simulation vs. hardware output
- Flag metrics where hardware deviates > configurable threshold (default 5%)

### Encoding Strategy Comparison

**NB-ES1 · Compare spike encoding methods on the same task**
As an engineer choosing an encoding strategy,
I want to run the same network with rate, temporal, and delta encoding and see which preserves the most task-relevant information,
so that I pick the right encoding without trial-and-error.

Acceptance criteria:
- Select network + input signal (from NeuroSense recording or synthetic)
- Run benchmark with each encoding method, same parameters otherwise
- Comparison view: encoding method, accuracy score, spike rate (spikes/s), information efficiency (bits/spike), computation cost
- Recommendation text: "For this task and input type, delta encoding achieves the best accuracy/efficiency tradeoff"

### Regression Testing

**NB-R1 · Save and diff against baselines**
As an engineer iterating on a network,
I want to save a benchmark result as a baseline and get a diff when I re-run after changes,
so that I know exactly what improved or degraded.

Acceptance criteria:
- "Save as Baseline" button on any benchmark result
- Re-running the same benchmark shows a diff panel: metric, baseline value, current value, delta, delta %
- Color-coded: green = improved, red = regressed, gray = unchanged (within noise threshold)
- Configurable noise threshold per metric (default: 1%)
- Baseline history: track multiple baselines over time, see trend charts

**NB-R2 · Regression alerts**
As a team lead,
I want to be notified when a benchmark regresses beyond a threshold,
so that regressions are caught early.

Acceptance criteria:
- Per-benchmark configurable thresholds (e.g., "fail if accuracy drops > 2%", "warn if power increases > 10%")
- CLI mode returns non-zero exit code on threshold violation
- HTTP mode returns structured error response with violating metrics
- Optional: webhook notification (Slack, email) on regression

### Robustness Profiling

**NB-RP1 · Fault sweep robustness curve**
As an engineer designing for hardware reliability,
I want to sweep across fault injection rates and see a robustness curve,
so that I know the failure point of my network before deployment.

Acceptance criteria:
- Configure: fault type (dead neuron, stuck-at, weight noise), sweep range (0%-30%), step count
- Output: robustness curve (accuracy vs. fault rate) with confidence intervals (N=5 seeds per point)
- Summary: "Network maintains >90% accuracy up to 12% dead neurons"
- Compare robustness curves across different quantization levels or network variants

**NB-RP2 · Input perturbation sweep**
As an engineer validating noise tolerance,
I want to sweep input noise levels and see how performance degrades,
so that I know how sensitive my network is to noisy sensor data.

Acceptance criteria:
- Configure: noise type (Gaussian, salt-and-pepper, signal dropout), range, steps
- Output: performance vs. noise level curve
- Works with synthetic inputs or real recorded signals (via NeuroSense)

### Reporting

**NB-RE1 · Generate benchmark report**
As an engineer presenting to a design review,
I want to export a comprehensive benchmark report as PDF or HTML,
so that I can share results with stakeholders who don't use the tool.

Acceptance criteria:
- Report includes: network description, benchmark methodology, all metrics with charts, comparison tables, robustness curves, conclusion
- Charts are publication-quality (high DPI, clean typography)
- Report is auto-generated from benchmark results — no manual formatting needed
- Configurable sections: include/exclude comparison, robustness, encoding analysis
- Company logo and header customizable

---

## Backend Spec

### API Endpoints

All NeuroBench-specific endpoints live under `/api/neurobench/`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/neurobench/benchmarks` | List available benchmarks (built-in + custom) |
| GET | `/api/neurobench/benchmarks/{id}` | Get benchmark definition and metadata |
| POST | `/api/neurobench/benchmarks` | Create a custom benchmark definition |
| POST | `/api/neurobench/run` | Run a benchmark (returns job ID) |
| GET | `/api/neurobench/run/{job_id}` | Poll benchmark job status and results |
| POST | `/api/neurobench/compare/targets` | Run cross-target comparison |
| POST | `/api/neurobench/compare/encoding` | Run encoding strategy comparison |
| POST | `/api/neurobench/faults/sweep` | Run fault injection sweep |
| POST | `/api/neurobench/perturbation/sweep` | Run input perturbation sweep |
| GET | `/api/neurobench/baselines` | List saved baselines |
| POST | `/api/neurobench/baselines` | Save a benchmark result as baseline |
| POST | `/api/neurobench/diff` | Diff current result against a baseline |
| GET | `/api/neurobench/results` | List all benchmark results (filterable) |
| GET | `/api/neurobench/results/{id}` | Get a specific result |
| POST | `/api/neurobench/report` | Generate a benchmark report (PDF/HTML) |

### Data Models

**BenchmarkDefinition**
```python
class BenchmarkDefinition(BaseModel):
    id: str                              # e.g., "grip_stability"
    name: str                            # e.g., "Grip Stability"
    description: str
    task_type: str                       # "control", "classification", "detection", "latency"
    input_spec: InputSpec                # How to generate or source input data
    assertions: list[str]                # CNL assertion strings
    scoring: ScoringConfig
    default_params: dict[str, Any]       # Default benchmark parameters
    builtin: bool                        # True for built-in, False for custom

class InputSpec(BaseModel):
    type: Literal["synthetic", "recording", "custom"]
    synthetic_config: dict | None = None   # Signal generator parameters
    recording_session_id: str | None = None  # NeuroSense session ID
    data_path: str | None = None           # Path to input data file

class ScoringConfig(BaseModel):
    primary_metric: str                  # e.g., "accuracy", "stopping_distance", "latency_ms"
    secondary_metrics: list[str]         # Additional metrics to track
    higher_is_better: bool               # For the primary metric
    pass_threshold: float                # Minimum acceptable value
```

**BenchmarkResult**
```python
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurohub/neurohub_spec.md**
```
# Neurohub — Neuromorphic Model & Dataset Registry
**Version:** 0.1.0 (spec draft)
**Created:** 2026-04-03

---

## Overview

Neurohub is the community registry for the neuromorphic computing field — a central, searchable platform for sharing and discovering pre-trained SNN models, neuromorphic datasets, hardware profiles, NeuroCNL specs, encoding presets, and benchmark baselines. It fills the same role HuggingFace Hub fills for conventional deep learning, but built from the ground up for the constraints and conventions of spike-based computing.

Neurohub is **not** a project manager or orchestration layer — that is NeuroDash. Neurohub is a **public community artefact store** that integrates with every NMTK module as its upstream source of reusable components.

---

## Repository

`neuro-space/Neurohub` — independent repo within the Neuro-space GitHub organisation.

**Integrations (consumers of Neurohub artefacts):**
- **NeuroCNL** — import shared CNL spec templates from the registry
- **NeuroSim** — load pre-trained SNN models for simulation
- **NeuroSense** — pull community encoding presets and spike datasets
- **NeuroChip** — fetch hardware profiles for known target devices
- **NeuroBench** — pull community benchmark baselines; publish benchmark scores back to a model's registry card

---

## Artefact Types

| Type | Description | Primary Consumer |
|---|---|---|
| `snn_model` | Pre-trained SNN weights + architecture definition | NeuroSim, NeuroChip |
| `dataset` | Neuromorphic datasets (event streams, spike recordings, EMG, DVS) | NeuroSense, NeuroSim |
| `hardware_profile` | Target device specifications and quantisation configs | NeuroChip |
| `cnl_spec` | Reusable NeuroCNL specification templates | NeuroCNL |
| `encoding_preset` | Spike encoding configurations for sensor modalities | NeuroSense |
| `benchmark_baseline` | Reference benchmark result sets with methodology notes | NeuroBench |

---

## User Stories

### Discovery & Search

**NH-S1 · Browse and search the registry**
As a neuroscientist looking for a starting point,
I want to search the registry for SNN models trained on EMG data targeting Loihi 2,
so that I can start from a community baseline instead of building from scratch.

Acceptance criteria:
- Full-text search across name, description, tags, and model card content
- Filter by: artefact type, hardware target, neuron model, task category, licence, minimum NeuroBench score
- Sort by: most downloaded, most starred, recently updated, NeuroBench score
- Results show: name, type, author/org, hardware target, task, NeuroBench score (if available), download count, stars, last updated
- Search is fast (<500ms) via indexed backend

**NH-S2 · Artefact detail page (Model Card)**
As an engineer evaluating whether to use a community model,
I want to read a structured model card that describes the architecture, training data, hardware targets, and known limitations,
so that I can make an informed decision before downloading.

Acceptance criteria:
- Model card sections: Overview, Architecture, Training Data, Hardware Targets, Performance (NeuroBench scores), Limitations, Licence, Citation
- Model card rendered from a `MODEL_CARD.md` file included in the artefact package
- NeuroBench scores displayed as a table: task, score, hardware, date, submitted by
- Download button with file size and format info
- "Open in NeuroSim" / "Open in NeuroCNL" / "Open in NeuroSense" deep-link buttons that route the artefact directly into the relevant NMTK module

**NH-S3 · Hardware-aware filtering**
As a hardware engineer deploying to Akida,
I want to filter models by hardware target,
so that I only see models that have been validated on my device.

Acceptance criteria:
- Hardware target is a structured field, not free text: values from a curated list (Loihi 2, SpiNNaker 2, Akida 1000, BrainScaleS-2, Generic/Software)
- A model can declare multiple supported targets
- Filter is available on search, browse, and tag pages

### Upload & Publishing

**NH-U1 · Upload an artefact**
As a researcher publishing a trained model,
I want to upload my model weights, architecture file, and model card in one flow,
so that the community can discover and reuse my work.

Acceptance criteria:
- Upload wizard: select artefact type → fill structured metadata → upload files → preview model card → publish
- Required metadata per type: see Metadata Schema section below
- Model card file (`.md`) validated for required sections before publish
- Artefact files accepted as a `.neurohub` archive (ZIP) or as individual file upload
- Max file size: 10 GB for datasets, 2 GB for models, 50 MB for specs/presets/profiles
- Upload via web UI or CLI (`neurohub push`)

**NH-U2 · Version an artefact**
As a researcher releasing an improved model,
I want to publish a new version of my existing registry entry without breaking existing users,
so that downstream projects can pin to a specific version.

Acceptance criteria:
- Versions follow semantic versioning (`major.minor.patch`)
- Each version has its own files, model card, and metadata
- "Latest" tag always points to the highest published version
- NMTK modules can pin to a specific version: `neurohub://models/emg-reflex-controller@1.2.0`
- Old versions remain downloadable indefinitely
- Release notes field per version (supports Markdown)

**NH-U3 · Organisations and namespaced artefacts**
As a research lab publishing multiple models,
I want to publish under our lab's organisation name,
so that our artefacts are clearly attributed and grouped.

Acceptance criteria:
- Artefacts addressed as `{owner}/{slug}` — e.g., `intel-ncl/loihi2-gesture-classifier`
- Owners can be individual users or organisations
- Organisation admins can manage members and transfer artefact ownership
- Organisation profile page lists all published artefacts

### Community Features

**NH-C1 · Star and bookmark artefacts**
As a researcher tracking useful community resources,
I want to star artefacts I find valuable and maintain a personal bookmarks list,
so that I can find them again quickly.

Acceptance criteria:
- Star button on every artefact card and detail page; star count visible publicly
- "My Stars" page in user profile lists all starred artefacts
- Stars are public (others can see what a user has starred)

**NH-C2 · Discussions**
As an engineer who found a bug in a community model,
I want to open a discussion thread on the artefact's page,
so that I can report it and get guidance from the author.

Acceptance criteria:
- Discussion tab on each artefact page
- Threaded comments, Markdown supported
- Author can mark a thread as resolved
- Author receives notification on new discussion posts

**NH-C3 · NeuroBench score submission**
As an engineer who benchmarked a community model on my hardware,
I want to submit my NeuroBench results to the model's registry card,
so that the community has real-world performance data across multiple hardware targets.

Acceptance criteria:
- "Submit Benchmark Result" button on model detail pages
- Submission form: hardware target, NeuroBench task, score, methodology notes, link to full result (optional)
- Submitted scores go through a brief moderation queue (author can approve or flag)
- Scores display as a community-contributed table: hardware, task, score, submitted by, date

### NMTK Integration

**NH-I1 · Browse registry from within NMTK modules**
As an engineer working in NeuroSim,
I want to browse and load models from Neurohub directly from within the app,
so that I don't have to switch context to a browser and manually import files.

Acceptance criteria:
- "Browse Neurohub" panel available in NeuroSim, NeuroCNL, NeuroSense, and NeuroChip
- Panel shows search + filter identical to the web UI
- "Import" button downloads and loads the artefact directly into the active project
- NMTK modules cache downloaded artefacts locally to avoid repeated downloads

**NH-I2 · Publish from within NMTK modules**
As an engineer who just finished training a model in NeuroSim,
I want to publish it to Neurohub directly from the NeuroSim interface,
so that sharing requires no manual file export or browser navigation.

Acceptance criteria:
- "Publish to Neurohub" button in NeuroSim (and NeuroCNL, NeuroSense)
- Pre-fills structured metadata from the app's project context (hardware target, neuron model, task)
- Opens model card editor with a template
- Handles authentication via NMTK's shared session token

**NH-I3 · NeuroBench auto-publish**
As an engineer who ran a benchmark in NeuroBench,
I want to automatically submit the result to the source model's Neurohub card,
so that benchmark scores propagate to the registry without manual steps.

Acceptance criteria:
- If the model loaded in NeuroBench originated from Neurohub (tracked by `neurohub_uri`), a "Publish to Neurohub" button appears on the result screen
- One-click submission pre-fills all benchmark metadata from the run
- Confirmation dialog shows the data being submitted before sending

---

## Metadata Schema

### SNN Model
```python
class SNNModelMetadata(BaseModel):
    name: str
    slug: str                                    # URL-safe identifier
    description: str
    task: str                                    # e.g., "gesture_classification", "emg_decoding"
    neuron_model: Literal["LIF", "ALIF", "Izhikevich", "HH", "custom"]
    synapse_model: str                           # e.g., "static", "STDP", "STP"
    hardware_targets: list[HardwareTarget]
    training_framework: str                      # e.g., "Norse", "SpikingJelly", "Lava", "Brian2"
    training_dataset: str | None                 # Neurohub dataset URI or free text
    input_encoding: str                          # e.g., "rate_coding", "temporal_coding", "TTFS"
    network_size: NetworkSize
    licence: str                                 # SPDX identifier e.g. "Apache-2.0", "CC-BY-4.0"
    tags: list[str]
    paper_url: str | None
    code_url: str | None

class HardwareTarget(BaseModel):
    device: Literal["loihi2", "spinnaker2", "akida1000", "brainscales2", "generic"]
    validated: bool                              # True = author has tested on this hardware
    quantisation_bits: int | None                # e.g., 4, 8
    notes: str | None

class NetworkSize(BaseModel):
    neurons: int
    synapses: int
    layers: int
    parameters: int | None
```
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/SPEC.md**
```
# NeuroToolkit App Specification

## Overview
NeuroToolkit is a centralized, modular hub built in Flutter that allows users to easily manage, install, and run various neuromorphic engineering sub-modules. Instead of forcing users to download and configure a monolithic repository, the app provides a lightweight core where users can browse available tools (e.g., `Neuro-Dream-Hand`, `neurocnl`, `nmtk`) and selectively "install" what they need.

## Goals
- **Modularity:** Users download only the tools they require.
- **Ease of Use:** Provide a simple graphical interface to manage complex Python dependencies and CLI tools.
- **Discoverability:** Serve as a catalog for related neuromorphic projects.

## Architecture
1. **Frontend (Flutter):**
   - **Dashboard:** Overview of installed tools and system status.
   - **Module Marketplace:** A catalog view showing available tools with descriptions, statuses (Not Installed, Installed, Update Available), and an "Install" button.
   - **Tool Runners:** Dedicated GUI wrappers for each installed tool to execute commands (e.g., running a simulation in `Neuro-Dream-Hand` or compiling a spec in `neurocnl`).
2. **Backend/Local Integration:**
   - **Module Manager:** Handles cloning Git repositories or downloading packages.
   - **Environment Manager:** Provisions isolated Python environments (via `venv` or `conda`) for each tool to prevent dependency conflicts.
   - **Process Execution:** Uses Dart's `Process.run` to execute underlying Python scripts and stream stdout/stderr back to the Flutter UI.

## Modules Included
1. **Neuro-Dream-Hand:** Neuromorphic simulation framework for prosthetic hand control.
2. **neurocnl:** Controlled Natural Language specifications compiler for neuromorphic computing.
3. **nmtk:** Neuromorphic Toolkit hub for various utilities.

## Phase 1 Implementation (Current Scope)
- Build the Flutter UI shell (Navigation, Dashboard, Module Catalog).
- Implement state management for module statuses (Uninstalled, Installing, Installed).
- Provide a mock installation process (simulating a download and setup phase with progress indicators).
- Set up a generic "Tool View" for launched modules.
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/pitches/inrc_project_proposal.md**
```
# INRC Project Proposal: Validating NMTK's Automated SNN Toolchain on Loihi 2

## 1. Project Overview
The NeuroMorphicToolKit (NMTK) is an open-source, cross-platform framework designed to unify the neuromorphic computing ecosystem. It serves as a bridge for neuroscientists and software engineers to design, build, and deploy Spiking Neural Networks (SNNs) to hardware edge devices without requiring extensive hardware-specific knowledge.

Within this toolkit, the **NeuroCNL** (Conceptual Neuromorphic Language) module allows users to define biological network architectures which are then systematically parsed and converted via our internal compiler into backend hardware representations.

## 2. Progress Checklist & Current Status
Our team has achieved the following milestones, preparing us directly for hardware integration:
- **Built and Tested an SNN:** Designed and trained an SNN controller for an applied robotics use case (the Neuro-Dream-Hand project).
- **Implemented Model in Lava:** We created the `LoihiExporter`, a native compilation layer that translates NeuroCNL graph objects directly into Lava's `LIF` and `Dense` processes.
- **Evaluated in Simulation:** We built a local deployment pipeline (`step13_loihi_deployment.py`) that exports the SNN targeting the CPU simulator using `Loihi2SimCfg`. This successfully executes the auto-generated code and generates baseline estimates for latency and energy metrics.

## 3. Need and Benefit of Requested System (INRC Cloud Access)
While our local simulation handles functional validation and software-level equivalence, we require access to the **Neuromorphic Research Cloud (vLab)** for the following critical evaluations:

1. **Hardware-Specific Routing & Mapping Constraints:** We need to validate that the automated network topologies generated by our `LoihiExporter` align with the physical limitations of the Loihi 2 architecture. We must ensure the auto-generated code does not cause routing congestion or memory bottlenecks when compiled down to the physical silicon using `Loihi2HwCfg`.
2. **Accurate Hardware Benchmarking (vs. PYNQ Z2):** While we have simulated CPU baselines, we also have an existing edge deployment pipeline targeting the **PYNQ Z2 FPGA** board (running 8-bit quantized SNN overlays). We need INRC access to conduct a direct comparative benchmark—evaluating Loihi 2’s latency, throughput, and energy efficiency against our current PYNQ Z2 edge setup for the same SNN controller.
3. **Closed-Loop Edge Robotics (Teensy 4.1):** Our SNN models do not run in a vacuum; they control a physical robotic hand. In our current architecture, a **Teensy 4.1** microcontroller acts as the physical bridge, ingesting sensory data and commanding servos. We need INRC access to validate the closed-loop communication pipeline between a live Loihi 2 board and our Teensy 4.1 interface hardware to ensure the SNN's real-time control latency constraints are met.
4. **Continuous Integration Pipeline:** Direct cloud access will allow us to incorporate real-world deployment checks into our framework's development lifecycle, ensuring future open-source updates maintain strict compatibility with Intel's hardware.

## 4. Evaluation Plan
Upon receiving access to the vLab environment, our intended workflow is:
1. Transfer the pre-trained `sleep_weights.npz` and the auto-generated Lava python scripts from our NMTK pipeline.
2. Execute the workload replacing the `Loihi2SimCfg` with the `Loihi2HwCfg` configuration.
3. Quantify the delta between the simulated CPU baseline and the physical Loihi 2 board in regards to execution speed (latency) and total energy cost per inference.
4. Open-source these findings as part of the core benchmark results for the NeuroMorphicToolKit.
```



The docs show a strong research story already: controlled natural language for SNN design, biosignal-to-spike encoding, simulation, deployment, benchmarking, and a mature prosthetic-control case study. I’m reading the integration surfaces next so the thesis write-up reflects not just aspirations but the actual end-to-end workflows the repository already tests.


**Files Read:**

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/tests/integration/test_cross_module.py**
```
import os
import time
from pathlib import Path

import httpx
import pytest

# Service URLs from environment or defaults (Docker service names)
NEUROCNL_URL = os.getenv("NEUROCNL_URL", "http://neurocnl:8000")
NEUROSIM_URL = os.getenv("NEUROSIM_URL", "http://neurosim:8000")
NEUROCHIP_URL = os.getenv("NEUROCHIP_URL", "http://neurochip:8000")
NEUROSENSE_URL = os.getenv("NEUROSENSE_URL", "http://neurosense:8000")
NEUROHUB_URL = os.getenv("NEUROHUB_URL", "http://neurohub:8000")
NEUROBENCH_URL = os.getenv("NEUROBENCH_URL", "http://neurobench:8000")


def _default_neurosense_artifact_path() -> str:
    return str(
        Path(__file__).resolve().parents[2]
        / "Neurosense"
        / "neurosense"
        / "tests"
        / "fixtures"
        / "canonical_emg_session.hdf5"
    )


@pytest.mark.asyncio
async def test_neurocnl_to_neurosim():
    """Test neurocnl -> Neurosim pipeline (CNL design -> simulation)"""
    spec = "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5"

    # 1. Validate in neurocnl
    async with httpx.AsyncClient() as client:
        resp = await client.post(f"{NEUROCNL_URL}/api/parse", json={"spec": spec})
        assert resp.status_code == 200
        assert resp.json()["errors"] == 0

        # 2. Parse in neurosim to get graph
        resp = await client.post(
            f"{NEUROSIM_URL}/api/neurosim/parse-cnl", json={"cnl_spec": spec}
        )
        assert resp.status_code == 200
        graph = resp.json()
        assert "nodes" in graph

        # 3. Run preview in neurosim
        resp = await client.post(
            f"{NEUROSIM_URL}/api/neurosim/preview",
            json={"graph": graph, "duration_ms": 100},
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"


@pytest.mark.asyncio
async def test_neurosim_to_neurochip():
    """Test Neurosim -> Neurochip pipeline (simulation -> hardware deployment)"""
    mock_graph = {
        "nodes": [
            {
                "id": "n1",
                "component_id": "lif_population",
                "parameters": {"n_neurons": 10},
                "position": [0, 0],
            }
        ],
        "edges": [],
        "metadata": {},
    }

    async with httpx.AsyncClient() as client:
        # 1. Export from neurosim as C
        resp = await client.post(
            f"{NEUROSIM_URL}/api/neurosim/export/c", json=mock_graph
        )
        assert resp.status_code == 200
        assert resp.json()["format"] == "c"

        # 2. Validate deployment in neurochip
        manifest = {
            "target_device": "Teensy 4.1",
            "firmware_version": "1.0.0",
            "checksum_sha256": "a" * 64,
        }
        resp = await client.post(
            f"{NEUROCHIP_URL}/api/neurochip/deployments/validate", json=manifest
        )
        assert resp.status_code == 200
        assert resp.json()["target_device"] == "Teensy 4.1"


@pytest.mark.asyncio
async def test_neurosense_to_neurocnl():
    """Test Neurosense -> neurocnl pipeline (biosignal -> SNN model)"""
    mock_data = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
    encoding_config = {"method": "step_forward", "parameters": {"threshold": 0.01}}

    async with httpx.AsyncClient() as client:
        # 1. Encode in neurosense
        resp = await client.post(
            f"{NEUROSENSE_URL}/api/neurosense/encode",
            json={
                "data": mock_data,
                "encoding_config": encoding_config,
                "sampling_rate_hz": 250.0,
            },
        )
        assert resp.status_code == 200
        spikes = resp.json()["spike_trains"]
        assert len(spikes) == 2

        # 2. Use in neurocnl (Mocking integration via prosthetic sim)
        spec = "The sensory neuron MUST fire"
        resp = await client.post(
            f"{NEUROCNL_URL}/api/prosthetic/simulate",
            json={"spec": spec, "duration": 0.1, "n_neurons": 10},
        )
        # The endpoint returns 202 Accepted for background jobs
        assert resp.status_code == 202


@pytest.mark.asyncio
async def test_neurosense_artifact_handoff():
    """Test canonical NeuroSense artifact handoff into neurocnl and Neurobench."""
    artifact_path = os.getenv(
        "NEUROSENSE_ARTIFACT_PATH", _default_neurosense_artifact_path()
    )

    async with httpx.AsyncClient() as client:
        replay_resp = await client.post(
            f"{NEUROCNL_URL}/api/prosthetic/neurosense/replay",
            json={"artifact_path": artifact_path, "preview_frames": 2},
        )
        if replay_resp.status_code == 404:
            pytest.skip(
                "NeuroCNL service could not access the configured NeuroSense artifact path."
            )
        assert replay_resp.status_code == 200, replay_resp.text
        replay_data = replay_resp.json()
        assert replay_data["artifact_schema_version"] == "1.0"
        assert replay_data["frame_count"] > 0
        assert replay_data["spike_event_count"] > 0

        bench_resp = await client.post(
            f"{NEUROBENCH_URL}/api/neurobench/run",
            json={
                "benchmark_id": "neurosense_replay_contract",
                "network_path": "unused-for-recording-benchmark.cnl",
                "params": {"artifact_path": artifact_path},
            },
        )
        if bench_resp.status_code == 404:
            pytest.skip(
                "NeuroBench service does not have the NeuroSense recording benchmark loaded."
            )
        assert bench_resp.status_code == 200, bench_resp.text
        job_id = bench_resp.json()["job_id"]

        for _ in range(10):
            status_resp = await client.get(
                f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}"
            )
            assert status_resp.status_code == 200, status_resp.text
            status_data = status_resp.json()
            if status_data["status"] == "COMPLETED":
                result_resp = await client.get(
                    f"{NEUROBENCH_URL}/api/neurobench/run/{job_id}/result"
                )
                assert result_resp.status_code == 200, result_resp.text
                result = result_resp.json()
                assert result["target_id"] == "neurosense_recording"
                assert result["metrics"]["input_spike_events"] > 0
                break
            if status_data["status"] == "FAILED":
                if "Session artifact not found" in (status_data.get("error") or ""):
                    pytest.skip(
                        "NeuroBench service could not access the configured NeuroSense artifact path."
                    )
                pytest.fail(
                    f"NeuroBench recording benchmark failed: {status_data.get('error')}"
                )
            time.sleep(1)
        else:
            pytest.fail("Timed out waiting for NeuroBench recording benchmark job.")


@pytest.mark.asyncio
async def test_neurohub_orchestration():
    """Test Neurohub orchestration of multi-module workflow"""
    workflow = {
        "id": "test-integration-wf",
        "name": "Integration Pipeline",
        "description": "Validates CNL then runs Sim",
        "steps": [
            {
                "id": "val-step",
                "name": "Validate",
                "app": "neurocnl",
                "endpoint": "/api/validate",
                "method": "POST",
                "parameters": {"spec": "Sensory neuron MUST fire"},
                "success_criteria": "overall == True",
                "on_failure": "halt",
            },
            {
                "id": "sim-step",
                "name": "Simulate",
                "app": "neurosim",
                "endpoint": "/api/neurosim/preview",
                "method": "POST",
                "parameters": {
                    "graph": {
                        "nodes": [
                            {
                                "id": "n1",
                                "component_id": "lif",
                                "parameters": {},
                                "position": [0, 0],
                            }
                        ],
                        "edges": [],
                        "metadata": {},
                    },
                    "duration_ms": 50,
                },
                "success_criteria": "status == 'ok'",
                "on_failure": "halt",
                "depends_on": ["val-step"],
            },
        ],
        "builtin": False,
    }

    async with httpx.AsyncClient() as client:
        # 1. Create workflow
        resp = await client.post(
            f"{NEUROHUB_URL}/api/neurohub/workflows", json=workflow
        )
        assert resp.status_code == 201

        # 2. Run workflow (requires a project_id)
        # First create a mock project
        project_resp = await client.post(
            f"{NEUROHUB_URL}/api/neurohub/projects",
            json={"name": "Test Project", "description": "Integration Test"},
        )
        project_id = project_resp.json()["id"]

        run_resp = await client.post(
            f"{NEUROHUB_URL}/api/neurohub/workflows/test-integration-wf/run",
            params={"project_id": project_id},
        )
        assert run_resp.status_code == 200
        run_id = run_resp.json()["id"]

        # 3. Poll for completion
        for _ in range(10):
            status_resp = await client.get(
                f"{NEUROHUB_URL}/api/neurohub/workflows/runs/{run_id}"
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/tests/integration/test_teensy_e2e.py**
```
"""End-to-end integration tests for the Teensy deployment pipeline.

Covers:
1. Happy path: CNL spec → neurocnl /api/deploy/teensy/network → Neurochip /api/neurochip/export/teensy → firmware zip
2. Rejected network paths: oversized, recurrent, STDP → proper rejection
3. Post-flash verification via Dream-Hand /api/neurochip/serial/flash/{job_id}/verify

Requires running services (typically via docker-compose).
Service URLs are read from environment variables with Docker service-name defaults.
"""

from __future__ import annotations

import io
import os
import zipfile

import httpx
import pytest

NEUROCNL_URL = os.getenv("NEUROCNL_URL", "http://neurocnl:8000")
NEUROCHIP_URL = os.getenv("NEUROCHIP_URL", "http://neurochip:8000")

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

VALID_REFLEX_ARC_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.8\n"
    "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
    "The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
    "The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds\n"
    "The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.8\n"
)

OVERSIZED_NETWORK_SPEC = "\n".join(
    [
        f"The network MUST contain an excitatory pop{i} population of 100 neurons"
        for i in range(50)  # 50 × 100 = 5000 neurons > 4096
    ]
    + ["The connection from pop0 to pop1 MUST have WITH synaptic weight of 1.0"]
)

RECURRENT_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.5\n"
    "The connection from motor neuron to sensory neuron MUST have WITH synaptic weight of 0.3\n"
)

STDP_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.5\n"
    "The connection from sensory neuron to motor neuron MUST adapt WITH STDP learning rate of 0.01\n"
)


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_teensy_e2e_happy_path():
    """Full pipeline: valid CNL spec → deploy endpoint → firmware zip."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Step 1: Deploy through neurocnl (parse → lower → plan → handoff)
        deploy_resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": VALID_REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        assert deploy_resp.status_code == 200, (
            f"Deploy failed: {deploy_resp.status_code} {deploy_resp.text}"
        )

        deploy_data = deploy_resp.json()
        assert deploy_data["verdict"] in ("faithful", "approximate")
        assert deploy_data["payload"] is not None
        assert deploy_data["rejection_reasons"] == []

        payload = deploy_data["payload"]
        assert "num_neurons" in payload
        assert "num_synapses" in payload
        assert payload["neuron_model"] == "LIF"
        assert payload["weight_bit_width"] == 8
        assert "populations" in payload
        assert "connections" in payload
        assert payload["network_depth"] >= 1

        # Step 2: Export firmware through Neurochip
        export_resp = await client.post(
            f"{NEUROCHIP_URL}/api/neurochip/export/teensy",
            json=payload,
            params={"bit_width": 8},
        )
        assert export_resp.status_code == 200, (
            f"Export failed: {export_resp.status_code} {export_resp.text}"
        )
        assert export_resp.headers["content-type"] == "application/zip"

        # Step 3: Verify the firmware zip contents
        firmware_zip = zipfile.ZipFile(io.BytesIO(export_resp.content))
        names = firmware_zip.namelist()
        assert any("main.ino" in n for n in names), f"main.ino not found in {names}"
        assert any("network_params.h" in n for n in names), f"network_params.h not found in {names}"
        assert any("lif_engine.h" in n for n in names), f"lif_engine.h not found in {names}"
        assert any("platformio.ini" in n for n in names), f"platformio.ini not found in {names}"


@pytest.mark.asyncio
async def test_teensy_e2e_happy_path_with_warnings():
    """Verify a near-capacity network returns 'approximate' verdict with warnings."""
    # Build a network that is within limits but close to capacity
    large_spec = "\n".join(
        [
            "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The network MUST contain an excitatory hidden population of 3000 neurons",
            "The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0",
            "The connection from sensory neuron to hidden MUST have WITH synaptic weight of 0.5",
            "The connection from hidden to motor neuron MUST have WITH synaptic weight of 0.5",
        ]
    )

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": large_spec, "weight_bit_width": 8},
        )
        # May be 200 (deployable with warnings) or 422 (not_deployable) depending on
        # exact neuron count from parsing — both are correct integration outcomes
        if resp.status_code == 200:
            data = resp.json()
            assert data["verdict"] in ("faithful", "approximate")
            assert data["payload"] is not None


# ---------------------------------------------------------------------------
# Rejected network paths
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_teensy_rejected_oversized_network():
    """Network with >4096 neurons must be rejected with EXCEEDS_NEURON_CAPACITY."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": OVERSIZED_NETWORK_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422

        detail = resp.json()["detail"]
        assert detail["error"] == "not_deployable"
        assert len(detail["rejection_reasons"]) > 0
        reasons_text = " ".join(detail["rejection_reasons"]).lower()
        assert "neuron" in reasons_text or "capacity" in reasons_text


@pytest.mark.asyncio
async def test_teensy_rejected_recurrent_topology():
    """Recurrent connections must be rejected with UNSUPPORTED_TOPOLOGY."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": RECURRENT_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422

        detail = resp.json()["detail"]
        assert detail["error"] == "not_deployable"
        reasons_text = " ".join(detail["rejection_reasons"]).lower()
        assert "topology" in reasons_text or "recurrent" in reasons_text


@pytest.mark.asyncio
async def test_teensy_rejected_learning_rule():
    """STDP learning must be rejected before any Teensy payload is produced."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": STDP_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422

        detail = resp.json()["detail"]
        assert detail["error"] in {"lowering_failed", "not_deployable"}
        detail_text = " ".join(
            [str(detail.get("error", ""))]
            + [str(msg) for msg in detail.get("messages", [])]
            + [str(msg) for msg in detail.get("rejection_reasons", [])]
        ).lower()
        assert "learning" in detail_text or "stdp" in detail_text


@pytest.mark.asyncio
async def test_teensy_rejected_invalid_bit_width():
    """Bit widths outside {8, 16, 32} must be rejected."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": VALID_REFLEX_ARC_SPEC, "weight_bit_width": 4},
        )
        assert resp.status_code == 422


@pytest.mark.asyncio
async def test_teensy_rejected_network_does_not_reach_neurochip():
    """Rejected networks should never produce a payload for Neurochip."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": RECURRENT_SPEC, "weight_bit_width": 8},
        )
        assert resp.status_code == 422
        detail = resp.json()["detail"]
        # With a 422, no payload is returned — Neurochip never called
        assert "payload" not in detail or detail.get("payload") is None


# ---------------------------------------------------------------------------
# Post-flash Dream-Hand verification
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_teensy_post_flash_verification_contract():
    """Verify the Dream-Hand verification API contract shape.

    This test exercises the Neurochip serial API endpoints:
    1. POST /api/neurochip/serial/flash — start flash job
    2. GET  /api/neurochip/serial/flash/{job_id} — poll status
    3. POST /api/neurochip/serial/flash/{job_id}/verify — trigger verification

    In CI (no hardware), flash will fail at COMPILING or UPLOADING.
    The verify endpoint may return 503 if neurodreamhand is not installed.
    We test API contract shape, not hardware success.
    """
    async with httpx.AsyncClient(timeout=60.0) as client:
        # First, get a firmware zip from a happy-path deploy
        deploy_resp = await client.post(
            f"{NEUROCNL_URL}/api/deploy/teensy/network",
            json={"spec": VALID_REFLEX_ARC_SPEC, "weight_bit_width": 8},
        )
        if deploy_resp.status_code != 200:
            pytest.skip("Deploy endpoint not available for flash test")

        payload = deploy_resp.json()["payload"]

        export_resp = await client.post(
            f"{NEUROCHIP_URL}/api/neurochip/export/teensy",
            json=payload,
            params={"bit_width": 8},
        )
        if export_resp.status_code != 200:
            pytest.skip("Export endpoint not available for flash test")

        firmware_bytes = export_resp.content
```



MCP tool call completed: [CallToolResult { content: [Annotated { raw: Text(RawTextContent { text: "Found 9 thought(s):\n\n--- Result 1 (68.7% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: robotics, prosthetics, simulation\nActions: Validate physical performance of Neuro-Dream-Hand\n\nIn NeuroMorphicToolKit, Neuro-Dream-Hand is the applied robotics and prosthetic-control module with mature simulation capabilities and hardware-phase software that is unit-tested against mocks but still awaiting physical validation.\n\n--- Result 2 (42.4% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, neuroscience, software development\n\nThe current repository, NeuroMorphicToolKit, is a multi-module workspace that combines a Flutter launcher/control plane with neuromorphic product modules including neurocnl, Neurosim, Neurosense, Neurochip, Neurobench, Neurohub, and Neuro-Dream-Hand.\n\n--- Result 3 (41.1% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: hardware deployment, NeuroMorphicToolKit, workflow\n\nThe hardware deployment roadmap in NeuroMorphicToolKit is organized as a toolkit-level flow rather than a NeuroCNL-only flow: NeuroCNL authors and validates, Neurochip deploys, Neuro-Dream-Hand optionally verifies runtime, Neurobench optionally benchmarks, and NMTK orchestrates the user experience.\n\n--- Result 4 (39.9% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: hardware rollout, NeuroMorphicToolKit, UX design\n\nActive hardware rollout plans in NeuroMorphicToolKit exist for Teensy, PYNQ-Z2, and Akida, and each target emphasizes truthful support semantics, shared cross-module contracts, explicit handoff boundaries, and guided toolkit UX.\n\n--- Result 5 (39.0% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, Neurosense, EMG\n\nIn NeuroMorphicToolKit, Neurosense is currently narrowed around a credibility-first workflow of 2-channel forearm EMG to filter to spike encoding to record to replay, with a canonical HDF5 session artifact as the main validated output.\n\n--- Result 6 (38.7% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, neurocli, automation\n\nIn NeuroMorphicToolKit, neurocli is still planning-stage and appears intended to become the scriptable CLI front door for scaffolding and automation-heavy toolkit workflows.\n\n--- Result 7 (35.8% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, development pipeline, automation\n\nThe unified development pipeline in NeuroMorphicToolKit follows this pattern: humans write contracts and properties, manifests define migration state, scripts publish topologically sorted issues, agents implement code, CI verifies contracts and properties, and auto-merge is allowed when protected-file rules permit it.\n\n--- Result 8 (35.4% match) ---\nCaptured: 4/13/2026\nType: reference\nTopics: NeuroMorphicToolKit, neurocnl, controlled natural language\n\nIn NeuroMorphicToolKit, neurocnl is the controlled natural language module that parses plain-English neuromorphic specifications, validates them against invariants, simulates them, and supports multiple hardware or export backends with varying support levels.\n\n--- Result 9 (35.1% match) ---\nCaptured: 4/13/2026\nType: observation\nTopics: NeuroMorphicToolKit, Neurochip, deployment\n\nIn NeuroMorphicToolKit, Neurochip is the hardware and deployment-facing module responsible for packaging, compile and flash, and low-level deployment behavior rather than broad product orchestration.", meta: None }), annotations: None }], structured_content: None, is_error: Some(false), meta: None }]



**Files Read:**

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/docs/support_matrix.md**
```
# neurocnl Backend Support Matrix

This document is the canonical reference for what `neurocnl` can honestly claim to do today.
All other docs cross-reference this file. Claims here are derived directly from
`neurocnl/backends/capabilities.py`, the individual backend capability profiles, and
confirmed implementation state in the exporter and converter code.

---

## Fidelity Terms

`neurocnl` uses three terms consistently across the project:

- `faithful` — execution closely preserves the intended semantics
- `approximate` — execution or export works, but semantics rely on heuristics or backend-specific simplifications
- `unsupported` — the project cannot honestly claim runtime or backend support yet

A fourth term, `parser-recognized`, means the sentence family is accepted by `neurocnl.cnl.cnl_parser` but says nothing about execution fidelity.

**Important:** parser recognition is broader than execution fidelity, and exporter availability is not the same as validated on-hardware execution. Producing an export file (a Python script, C header, or ZIP overlay) means the artifact was generated — it does not mean the artifact has been compiled, flashed, or run on real hardware. On the Akida path specifically, NeuroCNL exportability is not proof of BrainChip SDK deployability; that confirmation must come from Neurochip runtime verification in the target environment.

---

## Backend Support Matrix

| Backend | Overall Status | Execution Type | Topology Support | Key Constraints | Environment Requirements |
|---|---|---|---|---|---|
| `nengo` | **faithful** | Full simulation | faithful | Primary execution path | `pip install .` + nengo |
| `loihi` | **approximate** | NengoLoihi script | approximate | Placement-aware topology mapping is still pending; timing resolution fixed at 1 ms | `pip install ".[loihi]"` + Intel Loihi developer access |
| `lava` | **approximate** | Export script | approximate | Dense-connection oriented; static weights only; integer weight scaling (128×) applied | `lava` package (Intel) |
| `spinnaker` | **approximate** | Export script (PyNN) | approximate | Projection topology may need backend-specific manual tuning | PyNN + SpiNNaker toolchain |
| `spinnaker2` | **approximate — export only** | Export script (py-spinnaker2) | approximate | I/O modules are still stubs; connectivity is lowered to explicit connection lists using represented-dimension weights | `py-spinnaker2` package |
| `akida` / `akida2` | **approximate** | IR-direct generator + Neurochip handoff | approx (akida2), unsupported branching (akida1) | NeuroCNL proves scaffold exportability and mapped-payload eligibility only; real SDK deployability must be verified later by Neurochip in the current runtime environment. STDP, homeostatic plasticity, STP, receptor dynamics: unsupported on all Akida targets; Akida1 strict sequential only; Akida2 approximates constrained non-sequential topologies | BrainChip MetaTF / akida package; **macOS is not supported by the akida package** |
| `teensy` | **approximate** | Handoff to Neurochip (port 8002) | unsupported (multi-population) | Feedforward LIF only; no recurrent connections, no axonal delays, no learning rules; int8 / int16 / float32 weights | Teensy 4.1 hardware; Neurochip backend running |
| `pynq` | **approximate — export only** | Export overlay ZIP | approximate | Max ~64 K synapses at int4 precision; **FINN compilation pipeline is a Phase 2 placeholder — the FINN stage is not yet wired** | PYNQ Z2 (Zynq-7000 SoC); overlay ZIP must be manually loaded |
| `sinabs` | **partial** | Export script | approximate | Sequential path is the most faithful; branching DAGs now lower through a deterministic sinabs wrapper, but still rely on approximation rather than backend-native graph semantics | `sinabs` package + PyTorch |
| `rockpool` | **partial — sequential only** | Rockpool module export | approximate (sequential) / **unsupported (branching)** | Sequential feed-forward exports work through NIR and direct IR lowering; branching and merged topologies remain unsupported | `rockpool` package |
| `nir` | **faithful** | Export format only | — | Round-trip format for cross-framework exchange; no execution path inside neurocnl | `nir` package |

---

## What "export only" Means

Several backends above are marked *export only*. This means `neurocnl` generates a file artifact
(a Python script, C header, or ZIP overlay) that must be separately compiled and deployed via the
vendor's toolchain. Producing the artifact is the extent of neurocnl's responsibility for those
backends — it does not imply compilation success, hardware validation, or runtime correctness on
the target device.

---

## Environment Requirements Summary

| Backend | pip extras / packages | OS restrictions |
|---|---|---|
| `nengo` | none beyond core install | None |
| `loihi` | `pip install ".[loihi]"` (NengoLoihi) | Loihi developer program access required for hardware |
| `lava` | `lava` (Intel) | None documented |
| `spinnaker` | PyNN, spynnaker / spalloc | SpiNNaker board or HBP access |
| `spinnaker2` | `py-spinnaker2` | SpiNNaker 2 board access |
| `akida` | BrainChip `akida` + MetaTF | **macOS not supported** by the akida package |
| `teensy` | none (generation only); Neurochip backend for deploy | Teensy 4.1 hardware for actual deployment |
| `pynq` | none (export only); PYNQ board + Vivado for full pipeline | PYNQ Z2 board; FINN toolchain for Phase 2 |
| `sinabs` | `sinabs`, `torch` | None |
| `rockpool` | *(broken — do not use)* | — |
| `nir` | `nir` | None |
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/docs/benchmarks.md**
```
# NeuroSense Benchmark Baselines

This document records the current benchmark baseline for the flagship
workflow:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

## Command

```bash
python -m neurosense.scripts.benchmark_pipeline --json
```

Measured on 2026-04-14 against:

- artifact: `neurosense/tests/fixtures/canonical_emg_session.hdf5`
- benchmark iterations: `5`
- replay chunk size: `50`
- environment: local NeuroSense `venv` in this checkout

## Current Baseline

| Metric | Measured value |
| --- | --- |
| artifact load average | `1.291 ms` |
| filter average | `0.140 ms` |
| encode average | `0.071 ms` |
| replay wall time | `1.113 ms` |
| replay throughput | `134750.671 samples/s` |
| channels | `2` |
| sampling rate | `200 Hz` |
| support level | `experimental` |

## Interpretation

- These numbers are fixture-backed software baselines, not real-board latency
  claims.
- The replay throughput measurement disables pacing so it can act as a stable
  regression benchmark for chunk emission rather than a wall-clock hardware
  claim.
- The artifact remains labeled `experimental` because no physical Cyton run has
  been accepted yet.

## Regression Thresholds

Treat the current baseline as the reference for local regression checks.

- artifact load should remain under `10 ms` for the canonical fixture
- filter should remain under `5 ms`
- encode should remain under `5 ms`
- replay throughput should remain above `10000 samples/s`
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neuro-Dream-Hand/SPEC.md**
```
# Engineering Specification: Planned Phases

This document specifies all unimplemented work for the Neuro-Dream Hand project.
It is organized into two phases: physical hardware integration (Phase 4) and
neuromorphic chip deployment (Phase 5). The existing simulation (Phases 1–3)
is described in the README and serves as the baseline these phases must validate against.

---

## Context: What the simulation has established

Before building anything physical, the following results exist from the MuJoCo
simulation and provide the target behaviour to match or exceed on real hardware:

- SNN reflex controller achieves >95% object survival under random force perturbations
  after <5 s of online PES learning.
- Sleep/wake consolidation reduces stopping distance progressively over 30 simulated days.
- Weight quantization to 4-bit INT causes measurable but recoverable degradation in
  drop-test survival rate.
- Optimal OCL hyperparameters: `learning_rate ≈ 1e-4`, `error_scale ≈ 5.0`
  (Goldilocks regime from `step8` sweep).

These are the numbers the HITL and chip deployment phases need to compare against.

---

## Phase 4: Hardware-in-the-Loop (HITL)

**Goal:** Bridge the simulation outputs to physical I/O. Measure real round-trip
latency, real sensor noise characteristics, and the gap between simulated and
physical drop-test survival rates.

The hardware path is:

```
OpenBCI Ganglion (EMG, Bluetooth)
        │
        ▼
EMGStreamer  ──►  EMGSpikeEncoder  ──►  Nengo SNN (existing)
                                                │
             Teensy 4.0 (Serial) ◄─────── grip command (float 0..1)
                    │
             Servo / BLDC actuator
                    │
             FSR / Load cell  ──────────► SerialBridge ──► Nengo SNN
```

### 4.1 Serial Bridge

**File:** `neurodreamhand/hardware/serial_bridge.py`

**Purpose:** Replace the MuJoCo physics step as the source of physical state
(object_z, slip_vz) and the sink for grip commands during HITL runs. The
existing `PinchBridge` co-simulation loop calls `bridge.step(grip)` and receives
a state tuple; `SerialBridge` must present the same interface.

**New dependency:** `pyserial>=3.5`

**Packet protocol (Teensy ↔ Python, little-endian binary):**

Command frame (Python → Teensy), 5 bytes:
```
[0x55] [grip_u16_hi] [grip_u16_lo] [checksum] [0xAA]
```
`grip` encoded as `uint16` in range `[0, 65535]` mapping to `[0.0, 1.0]`.

Sensor frame (Teensy → Python), 10 bytes:
```
[0x55] [timestamp_ms u32, 4 bytes] [force_raw u16, 2 bytes] [checksum] [0xAA]
```
`force_raw` is a 12-bit ADC reading from the FSR connected to Teensy pin A0.

**Class interface:**

```python
from dataclasses import dataclass

@dataclass
class SensorFrame:
    timestamp_ms: int     # Teensy millis() counter
    force_raw: int        # Raw 12-bit ADC value [0, 4095]
    force_N: float        # Calibrated force in Newtons
    slip_vz: float        # Numerically differentiated from force_N over dt

class SerialBridge:
    def __init__(
        self,
        port: str,                     # e.g. "/dev/ttyUSB0" or "COM3"
        baud_rate: int = 1_000_000,    # Teensy 4.0 USB serial: 1 Mbaud reliable
        dt: float = 0.002,            # Must match Nengo dt
        *,
        calibration_slope: float = 1.0,
        calibration_offset: float = 0.0,
    ) -> None: ...

    def connect(self) -> None:
        """Open serial port and flush buffers. Raises IOError if port not found."""

    def send_grip_command(self, grip: float) -> None:
        """Pack and send a grip command frame. grip clamped to [0.0, 1.0]."""

    def read_sensor_frame(self, timeout_s: float = 0.005) -> SensorFrame | None:
        """
        Read one sensor frame. Returns None if timeout elapses (treat as no-slip).
        Computes slip_vz = (force_N - prev_force_N) / dt internally.
        """

    def step(self, grip: float) -> tuple[float, float]:
        """
        Combined send + receive matching the PinchBridge.step() signature.
        Returns (object_z_proxy, slip_vz).
        object_z_proxy is derived from cumulative force integration — see note below.
        """

    def calibrate(self, n_samples: int = 500) -> tuple[float, float]:
        """
        Collect n_samples with no load, then with a known mass.
        Returns (slope, offset) and stores them in self.calibration_slope/offset.
        Saves result to output/serial_bridge_calibration.json.
        """

    def close(self) -> None:
        """Flush and close the serial port."""
```

**Note on `object_z_proxy`:** A real object height sensor is not planned for Tier 2.
`object_z_proxy` should be approximated as `1.0 - (force_N / max_expected_force_N)`
so that the SNN's object-height input degrades gracefully when force increases.
Document this approximation clearly in the class docstring.

**Teensy firmware requirements (not a Python file — describe in comments at top of serial_bridge.py):**
- Sample FSR on pin A0 at 500 Hz using `analogRead` with 12-bit resolution.
- Receive command frames over USB Serial, update servo PWM via `Servo.write(angle)`.
- Servo angle mapping: grip `0.0` → 0°, grip `1.0` → 180° (calibrate per servo).
- Send sensor frames at 500 Hz continuously regardless of whether a command was received.
- Use a hardware timer interrupt for both sample and transmit — do not use `delay()`.

**Acceptance criteria:**
- `test_serial_bridge.py`: mock the serial port with `unittest.mock.patch`; verify
  that `send_grip_command(0.75)` encodes correctly and `read_sensor_frame()` parses
  a hand-crafted byte sequence to the correct `SensorFrame` values.
- End-to-end: median round-trip latency (command sent → sensor frame received) < 4 ms
  at 500 Hz on Teensy 4.0 USB Serial 1 Mbaud.

---

### 4.2 Force/Tactile Sensor Characterization

**File:** `neurodreamhand/experiments/sensor_characterization.py`

**Purpose:** Before running HITL learning experiments, characterize the FSR noise
floor and dynamic range. This produces calibration constants used by `SerialBridge`
and documents the real-world signal quality that the SNN must handle.

**Measurements to collect:**

1. **Noise floor:** 500 samples at zero load → mean, std, SNR.
2. **Linearity:** apply 0 g, 50 g, 100 g, 200 g, 500 g masses; fit slope (N/ADC count).
3. **Latency:** hammer-tap the FSR; measure ADC rise time from video frame sync.

**Output:**
- `output/sensor_characterization.json`: calibration constants.
- `output/sensor_characterization.png`: linearity plot.

**Script:** `step10_sensor_characterization.py`

---

### 4.3 EMG Ingestion

**File:** `neurodreamhand/hardware/emg_streamer.py`

**Purpose:** Stream raw surface EMG from an OpenBCI Ganglion board into the Nengo
environment. The Ganglion samples 4 channels at 200 Hz via Bluetooth. This module
wraps BrainFlow to expose a simple frame-by-frame read interface compatible with
the rest of the pipeline.

**New dependency:** `brainflow>=5.0.0`

**Hardware setup:**
- Ganglion board connected via Bluetooth (BLE or USB dongle).
- Electrode placement: two differential pairs over the flexor digitorum superficialis
  (forearm, channels 1–2) and extensor digitorum (channels 3–4).
- Reference electrode on bony prominance (lateral epicondyle).

**Class interface:**

```python
import numpy as np
from brainflow.board_shim import BoardShim, BrainFlowInputParams, BoardIds

class EMGStreamer:
    BOARD_ID = BoardIds.GANGLION_BOARD   # = 1
    SAMPLE_RATE = 200                    # Hz, fixed for Ganglion

    def __init__(
        self,
        *,
        mac_address: str = "",           # Leave empty for first discovered device
        serial_port: str = "",           # For USB dongle connection
        window_samples: int = 50,        # 250 ms window at 200 Hz
        emg_channels: list[int] | None = None,  # Default: [1, 2, 3, 4]
    ) -> None: ...

    def connect(self) -> None:
        """
        Initialize BrainFlow session, prepare streaming.
        Raises RuntimeError if board is not found within 10 s.
        """

    def start_stream(self) -> None:
        """Begin BrainFlow data acquisition."""

    def read_frame(self) -> np.ndarray:
        """
        Return the latest `window_samples` of raw EMG.
        Shape: (n_emg_channels, window_samples), dtype float64, units µV.
        Returns zeros if fewer than window_samples are available yet.
        """

```





**Files Read:**

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/docs/flagship_workflow.md**
```
# Flagship Workflow

NeuroSense currently treats the following as its credibility target:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

Everything in the module should be described relative to this path first.

## Workflow Definition

- Signal type: `emg`
- Preset: `emg_prosthetic`
- Channel labels: `flexor`, `extensor`
- Preferred future physical target: `OpenBCI Cyton`
- Current validated artifact path: canonical HDF5 recording fixture and
  synthetic-path recording/replay tests
- Primary outputs:
  raw analog samples,
  filtered samples,
  timestamps,
  spike batches,
  event markers,
  encoding metadata,
  hardware provenance

## Support Statement

- `OpenBCI Cyton` is the default real-board target for this workflow, but it is
  still `experimental` until a real acceptance script passes on hardware.
- Synthetic BrainFlow acquisition plus fixture-backed replay/export coverage is
  the only `validated` path in this slice.
- Other BrainFlow board families remain `experimental`.

## Success Metrics

These are the workflow success criteria for the credibility pass, not measured
performance claims yet:

- Sampling rate target: `250 Hz` for the first Cyton-backed EMG path
- Latency budget target: `< 50 ms` acquisition-to-display and
  `< 100 ms` replay-to-downstream handoff, to be measured in the later
  benchmarking slice
- Data integrity:
  raw, filtered, and timestamp datasets stay shape-aligned;
  timestamps are monotonic;
  channel labels and preset metadata are preserved in the artifact
- Replay correctness:
  replay reads the same canonical HDF5 contract used for live recording;
  markers remain addressable;
  artifact metadata is preserved for export and downstream reuse

## Downstream Consumers

- Current downstream consumers: session listing, replay, and export
- Planned downstream consumers: NeuroCNL replay input routing and Neurobench
  replay-based evaluation
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/docs/integration_guide_neurosense_to_toolkit.md**
```
# NeuroSense To Toolkit Handoff

This guide documents the current canonical artifact handoff from NeuroSense
into `neurocnl` and `Neurobench`.

## Shared Input

Both consumers use the canonical NeuroSense HDF5 artifact described in
[session_artifact_contract.md](session_artifact_contract.md).

Recommended starting artifact:

`neurosense/tests/fixtures/canonical_emg_session.hdf5`

## NeuroCNL Replay Prep

`neurocnl` exposes a replay-preparation endpoint that turns a canonical
NeuroSense recording into EMG frame previews plus spike/provenance metadata.

Example:

```bash
curl -sS \
  -X POST http://127.0.0.1:8000/api/prosthetic/neurosense/replay \
  -H 'Content-Type: application/json' \
  -d '{
    "artifact_path": "/absolute/path/to/canonical_emg_session.hdf5",
    "preview_frames": 3
  }'
```

What it proves today:

- the artifact is readable by `neurocnl`
- schema version `1.0` is enforced
- EMG frames can be prepared for replay-oriented workflows without ad hoc
  conversion
- spike/provenance metadata survives the handoff

## Neurobench Recording Benchmark

`Neurobench` now includes the builtin benchmark
`neurosense_replay_contract`.

Example:

```bash
curl -sS \
  -X POST http://127.0.0.1:8000/api/neurobench/run \
  -H 'Content-Type: application/json' \
  -d '{
    "benchmark_id": "neurosense_replay_contract",
    "network_path": "unused-for-recording-benchmark.cnl",
    "params": {
      "artifact_path": "/absolute/path/to/canonical_emg_session.hdf5"
    }
  }'
```

What it measures today:

- artifact ingest latency
- presence of spike batches and spike events
- duration, channel count, and provenance metadata needed for replay benchmarks

## Current Scope

- This handoff is currently file-based.
- `neurocnl` replay prep is truthful preparation for downstream workflows, not a
  claim that continuous artifact-driven simulation is fully validated.
- `Neurobench` recording support currently benchmarks the artifact contract and
  ingest path first; it does not yet replace richer downstream evaluation flows.
```

**/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurosense/docs/session_artifact_contract.md**
```
# Session Artifact Contract

NeuroSense records flagship workflow sessions as HDF5 artifacts with canonical
schema version `1.0`.

The contract is the shared source of truth for:

- recorded-session metadata
- replay
- export
- `neurocnl` replay preparation
- `Neurobench` recording benchmarks
- fixture-backed automated tests

## Root Attributes

Required root attrs:

- `artifact_schema_version`
- `workflow_id`
- `workflow_label`
- `session_id`
- `timestamp`
- `duration_seconds`
- `device_type`
- `preset_id`
- `channels`
- `sampling_rate_hz`
- `signal_type`
- `capture_mode`
- `support_level`
- `channel_labels` as JSON list
- `hardware_provenance` as JSON object
- `encoding_config` as JSON object
- `subject_id` when provided

## Required Datasets And Groups

- `raw`: `(channels, samples)` float64
- `filtered`: `(channels, samples)` float64
- `timestamps`: `(samples,)` float64 seconds from recording start
- `markers/timestamps`: float64 marker offsets
- `markers/labels`: UTF-8 marker labels
- `spikes/batch_*`: per-batch spike groups with `method` attr and per-channel
  spike-time datasets

## Canonical Metadata Semantics

- `capture_mode`
  `live` for standard acquisition,
  `synthetic` for the validated BrainFlow synthetic path
- `support_level`
  `validated` for synthetic/fixture-backed artifact coverage,
  `experimental` for unvalidated real biosignal boards,
  `prototype` for PYNQ and Prophesee-style ingestion paths
- `hardware_provenance`
  contains enough detail to state what produced the session and what support
  level applies

## Checked-In Fixture

The canonical example artifact used by tests lives at:

`neurosense/tests/fixtures/canonical_emg_session.hdf5`

It represents the flagship forearm-EMG workflow with:

- `emg_prosthetic` preset metadata
- `flexor` and `extensor` channel labels
- `OpenBCI Cyton` recorded as the future target validation board
- `experimental` support level because no physical board has been validated yet
```



MarkAsCompleted: 2 items
I’ve got enough evidence now to synthesize a serious thesis recommendation instead of generic ideas. One theme is clearly stronger than the rest: using the suite as an end-to-end applied AI pipeline for neuromorphic prosthetic control, with other modules acting as alternatives or support layers rather than equal thesis candidates.
UpdateTodos: 3 items
Save this as `MASTER_THESIS_NMTK_JKU.md`.

# NeuroMorphicToolKit as a Master’s Thesis at JKU Applied AI

## Short conclusion

Yes — this codebase can support a strong Master’s thesis, but the thesis should **not** be “I built a toolkit.”  
For an **Applied AI** degree, the strongest thesis is to use the toolkit as an **end-to-end experimental platform** for a concrete AI problem.

The best current thesis direction in this repository is:

**From EMG to Deployable Neuromorphic Prosthetic Control: an End-to-End Applied AI Pipeline using Controlled Natural Language, Spiking Neural Networks, and Hardware-Aware Evaluation**

That direction is stronger than a pure platform/UI thesis because it combines:

- biosignal processing
- spike encoding
- spiking neural networks
- continual learning
- simulation-to-hardware transfer
- benchmarking and reproducibility

## What I checked

I went through the main repo documentation and module specs, especially:

- `README.md`
- `neurocnl/README.md`
- `neurocnl/docs/support_matrix.md`
- `Neurosense/README.md`
- `Neurosense/docs/flagship_workflow.md`
- `Neurosense/docs/integration_guide_neurosense_to_toolkit.md`
- `Neurosense/docs/session_artifact_contract.md`
- `Neurosim/neurosim_spec.md`
- `Neurochip/neurochip_spec.md`
- `Neurobench/neurobench_spec.md`
- `Neurohub/README.md`
- `Neurohub/neurohub_spec.md`
- `Neuro-Dream-Hand/README.md`
- `Neuro-Dream-Hand/THESIS_ROADMAP.md`
- `Neuro-Dream-Hand/SPEC.md`
- `tests/integration/test_cross_module.py`
- `tests/integration/test_teensy_e2e.py`
- `pitches/inrc_project_proposal.md`

I also checked your `open-brain` memory. The useful memories confirmed:

- this repo is a multi-module neuromorphic workspace
- `Neuro-Dream-Hand` is currently the most thesis-ready applied robotics slice
- the real workflow is toolkit-level: `neurocnl` authors/validates, `Neurochip` deploys, `Neuro-Dream-Hand` verifies runtime, `Neurobench` benchmarks, and `nmtk` orchestrates UX
- `Neurosense` is currently focused on a credible `2-channel forearm EMG -> filter -> spike encoding -> record -> replay` path

I did **not** find extra stored memory about your personal thesis preferences or JKU-specific constraints beyond what you told me.

## Why this repo is thesis-worthy

This project already contains the ingredients for a serious Applied AI thesis:

### 1. Interpretable model specification

`neurocnl` already frames neuromorphic systems as **controlled natural language specifications** that are:

- parsed
- validated against invariants
- converted into executable Nengo networks
- optionally lowered toward hardware/export targets

That gives you an unusual and strong thesis angle: **human-readable AI system design with machine-checkable semantics**.

### 2. Real input data, not just toy simulation

`Neurosense` is not just a generic sensor app. It is already narrowing around a realistic applied pipeline:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

That matters for a thesis because it gives you:

- a defined signal modality
- canonical artifacts
- replayable experiments
- an entry point for real human biosignals

### 3. Embodied control / robotics

`Neuro-Dream-Hand` is the clearest thesis core in the repo. It already claims mature simulated results around:

- reflexive prosthetic grasp control
- online continual learning
- sleep/wake consolidation
- quantization analysis
- fault injection
- hardware-in-the-loop preparation

That is much more thesis-ready than a generic dashboard or registry module.

### 4. Deployment and benchmarking layers

`Neurochip` and `Neurobench` give the thesis a proper evaluation frame:

- deployment constraints
- quantization tradeoffs
- latency/power estimates
- robustness analysis
- cross-target comparison
- sim-to-real benchmarking

That is important because a Master’s thesis needs evidence, not just architecture.

### 5. End-to-end integration already exists conceptually and in tests

The root integration tests already show cross-module workflows such as:

- `neurocnl -> Neurosim`
- `Neurosim -> Neurochip`
- `Neurosense -> neurocnl`
- `Neurosense -> Neurobench`
- Teensy end-to-end deployment handoff

So the thesis does not need to invent an end-to-end story from scratch. The repository is already organized around one.

## Best thesis direction

## Recommended thesis title

**From EMG to Deployable Neuromorphic Prosthetic Control: An End-to-End Applied AI Pipeline with Controlled Natural Language, Spiking Neural Networks, and Hardware-Aware Evaluation**

## Core idea

Use the NeuroMorphicToolKit as the experimental platform for a thesis that asks:

**Can an interpretable, modular neuromorphic pipeline transform human EMG signals into robust, deployable spiking controllers for prosthetic grasp tasks, and what are the tradeoffs across encoding, learning, quantization, and hardware deployment?**

## Why this is the best fit for JKU Applied AI

This topic is clearly **Applied AI**, not only software engineering.

It includes:

- AI model design
- representation of knowledge/specifications
- continual learning
- signal processing
- embodied intelligence / robotics
- explainability / interpretability
- evaluation under deployment constraints

It also gives you both:

- a concrete application domain: prosthetic control / assistive robotics
- a methodological contribution: a structured neuromorphic pipeline

## Modules to use in the thesis

### Core thesis modules

- `Neuro-Dream-Hand`  
  Main experimental task and controller setting.

- `Neurosense`  
  EMG acquisition, spike encoding, canonical artifact generation, replay.

- `neurocnl`  
  Human-readable controller specification and validation.

- `Neurochip`  
  Quantization, deployment analysis, firmware/export path.

- `Neurobench`  
  Metrics, baselines, robustness, comparison.

### Supporting context only

- `nmtk`  
  Use as platform/orchestration context, not the central thesis contribution.

- `Neurosim`  
  Useful as a design/workbench layer, but not the strongest thesis centerpiece.

- `Neurohub`  
  Interesting for open science and reuse, but currently too immature to be the main thesis axis.

## A realistic thesis contribution

A good thesis here is not “build all modules.”

A good thesis is:

1. define one clear applied problem
2. use the existing toolkit pieces as the system
3. run a rigorous empirical study
4. contribute either new evaluation, new integration, or new experimental evidence

## Concrete research questions

### Main research question

How effective is an end-to-end neuromorphic pipeline for prosthetic control when combining EMG-derived spike inputs, controlled natural language controller specification, spiking simulation, and deployment-aware evaluation?

### Strong sub-questions

1. Which spike encoding strategy or preset gives the best tradeoff for downstream prosthetic control?
2. How much performance is lost under deployment-aware quantization?
3. How large is the sim-to-real gap between Nengo simulation and hardware-in-the-loop execution?
4. Does a CNL-based controller description improve reproducibility and traceability compared with lower-level direct implementation?
5. What robustness margins exist under sensor noise, dead-neuron faults, or constrained hardware targets?

## Suggested thesis structure

## Option A: strongest and most balanced thesis

### Theme
**EMG-driven neuromorphic prosthetic control**

### What you would do
- use `Neurosense` to produce or replay EMG-derived spike inputs
- use `neurocnl` to specify controller behavior in interpretable form
- use `Neuro-Dream-Hand` as the experimental control environment
- use `Neurochip` to analyze deployment feasibility and quantization
- use `Neurobench` to benchmark robustness and regression

### Why it is strong
It gives you a full Applied AI story:
input -> representation -> learning/control -> deployment -> evaluation

### Likely deliverables
- reproducible experimental pipeline
- benchmarked controller variants
- quantization and robustness analysis
- optional hardware-in-the-loop validation
- thesis-quality figures and ablations

## Suggested methodology

### Phase 1: establish the simulation baseline
Start from the existing `Neuro-Dream-Hand` simulated setup and reproduce the main baseline metrics already described in the repo:

- grip/object survival
- stopping distance
- learning curves
- quantization effects

### Phase 2: integrate EMG-driven or replay-driven input
Use `Neurosense` canonical artifacts and replay flow as the sensory input source.

This gives a stronger thesis than using only synthetic controller inputs.

### Phase 3: compare encoding / control choices
Run controlled comparisons such as:

- rate vs delta vs temporal-style spike encoding
- different CNL-specified controller variants
- learning on/off
- sleep consolidation on/off

### Phase 4: deployment-aware analysis
Use `Neurochip` / `Neurobench` to compare:

- float vs 8-bit vs 4-bit quantization
- CPU simulation vs Teensy path
- optional Loihi/Akida/PYNQ path if access exists

### Phase 5: optional hardware-in-the-loop
If you have actual hardware access, this becomes excellent thesis material.  
If not, the thesis can still be valid as a simulation + replay + deployment-analysis thesis, but you should make the boundary explicit.

## Evaluation metrics

A strong evaluation section could include:

- task success rate
- object survival rate
- stopping distance
- adaptation speed
- convergence of learning
- latency
- spike rate / spike-event count
- robustness under perturbation
- quantization loss
- estimated power / efficiency
- sim-to-real delta

## What is already strong in the repo

These areas already look strong enough to anchor a thesis:

- `neurocnl`: clear CNL-to-SNN framing
- `Neurosense`: focused EMG workflow and canonical artifact contract
- `Neuro-Dream-Hand`: mature simulation and thesis-style roadmap
- root integration tests: real evidence of intended cross-module workflows

## What is weaker or risky

These areas should be treated carefully:

- several hardware targets are explicitly marked as `approximate`, `partial`, `export only`, or `unsupported` in `neurocnl/docs/support_matrix.md`
- `Neurosense` truthfully marks real-board validation as still experimental
- `Neuro-Dream-Hand` hardware phases are software-complete but still awaiting physical validation
- `Neurohub` appears conceptually useful but not mature enough to anchor the thesis

That means your thesis should avoid making unsupported claims like:

- real on-chip efficiency without real hardware measurement
- full physical prosthetic validation if the hardware stage is not actually completed
- strong deployment claims for targets that are currently export-only

## Best academic framing

A good way to frame the thesis academically is:

> This thesis investigates whether a modular neuromorphic AI pipeline can support interpretable specification, biosignal-driven control, and deployment-aware evaluation for prosthetic grasping. The work uses NeuroMorphicToolKit as the experimental platform and focuses on the interaction between spike encoding, controller design, continual learning, and hardware constraints.

That is much stronger than:

> I built a toolkit for neuromorphic applications.

## Alternative thesis directions

## Alternative 1: CNL as an interface for neuromorphic system design

### Possible title
**Controlled Natural Language for Interpretable Design of Spiking Neural Networks**

### Focus
Use `neurocnl`, `Neurosim`, and `Neurochip` to study whether CNL improves:

- accessibility
- correctness
- reproducibility
- traceability

### Pros
- distinctive
- interpretable AI angle
- strong human-centered angle

### Cons
- may drift toward HCI/software-engineering unless paired with strong empirical AI evaluation

## Alternative 2: simulation-to-hardware gap in neuromorphic control

### Possible title
**Quantifying the Simulation-to-Hardware Gap in Neuromorphic Prosthetic Controllers**

### Focus
Use `Neuro-Dream-Hand`, `Neurochip`, and `Neurobench` to compare:

- simulation performance
- Teensy or other hardware deployment behavior
- latency / quantization / robustness differences

### Pros
- very clean experimental thesis
- strong evaluation focus

### Cons
- depends more on hardware access

## Alternative 3: EMG-to-spike encoding for downstream control

### Possible title
**Evaluating EMG Spike Encoding Strategies for Neuromorphic Prosthetic Control**

### Focus
Use `Neurosense` plus `Neuro-Dream-Hand` / `Neurobench` to study how encoding affects downstream control quality.

### Pros
- very Applied AI
- manageable scope
- strong signal-processing + AI story

### Cons
- narrower than the full end-to-end thesis

## Alternative 4: open-science / registry thesis

### Possible title
**A Registry-Centered Reproducibility Workflow for Neuromorphic AI Artifacts**

### Focus
Build around `Neurohub`.

### Pros
- strong reproducibility/open science angle

### Cons
- weaker as Applied AI
- current repo maturity suggests this is not the best main thesis today

## What I would recommend you avoid as the main thesis

I would **not** make these the center of the thesis:

- the Flutter launcher alone
- module installation/orchestration alone
- Neurohub alone
- generic “platform engineering” without experiments
- unsupported hardware claims

Those can appear in the thesis as enabling infrastructure, but they are not the strongest Applied AI core.

## Most realistic thesis recommendation

If you want the strongest thesis from this repository for a **Master’s in Applied AI at JKU Linz**, I would recommend:

### Final recommendation

Build the thesis around:

- `Neuro-Dream-Hand` as the task environment
- `Neurosense` as the biosignal/spike-input layer
- `neurocnl` as the interpretable controller specification layer
- `Neurochip` as the deployment/quantization layer
- `Neurobench` as the evaluation layer

Use `nmtk` and the rest of the suite as platform context, not the main scientific contribution.

In short:

**The best thesis is an experimentally grounded, end-to-end neuromorphic prosthetic-control study — not a general toolkit thesis.**

## One-sentence thesis pitch

**This thesis evaluates whether an interpretable, modular neuromorphic AI pipeline can transform EMG-derived signals into robust and deployment-aware spiking prosthetic controllers, using NeuroMorphicToolKit as the experimental platform.**

If you want, I can next turn this into a **formal 1-page thesis proposal**, a **research-question/objectives section**, or a **JKU-style thesis outline with timeline and milestones**.