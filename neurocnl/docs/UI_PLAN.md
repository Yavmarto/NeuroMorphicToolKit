# UI Wrapper Plan — neurocnl Studio

A plan for building a visual interface around the neurocnl library using Flutter (web) and FastAPI, designed to lower the barrier to entry for neuromorphic engineers and showcase full-stack + neuroscience skills for the Dutch neuromorphic sector.

---

## 1. Why a UI Wrapper?

Neuromorphic computing sits at the intersection of neuroscience, electrical engineering, and computer science. Most practitioners are strong in one or two of these disciplines but not all three. The neurocnl library already bridges neuroscience language and executable networks, but it requires comfort with the command line, Python imports, and Nengo internals.

A visual interface removes those barriers:

| Pain point today | What the UI solves |
|---|---|
| Writing CNL from scratch requires memorising the grammar | Autocomplete, templates, and inline syntax hints |
| Validation errors are printed to the terminal as text | Inline error markers with plain-English explanations |
| The generated network is invisible (a `nengo.Network` object) | Interactive network graph showing populations, connections, and parameters |
| Simulation output is raw NumPy arrays or pickled data | Spike raster plots, membrane voltage traces, and summary stats rendered in the browser |
| Parameter tuning requires editing the `.cnl` file and re-running the CLI | Compact number editing in the editor plus generated-output preview in Studio |
| Sharing results means sending JSON/pickle files | Shareable reports with embedded plots, downloadable as HTML or PDF |

---

## 2. Target Users

### Primary: Neuromorphic engineers who are not software engineers

Researchers at labs and companies who understand spiking neural networks conceptually but find it easier to work with a visual tool than a text pipeline. Examples:

- Neuroscience PhD students at TU Delft, Radboud University, or University of Groningen who want to prototype SNN architectures quickly.
- Hardware engineers at companies like Innatera or SynSense who design chips but want a rapid way to specify and validate network behaviour before committing to silicon.
- Biomedical engineers working on brain-computer interfaces who need to iterate on network parameters without deep Python knowledge.

### Secondary: Educators and workshop organisers

People who teach neuromorphic computing and need an interactive tool for demonstrations. The visual pipeline makes the spec → validate → generate → simulate flow tangible.

### Tertiary: The developer themselves (portfolio piece)

The UI is itself a portfolio artefact that demonstrates:

- Full-stack engineering (Flutter + FastAPI + Docker)
- Neuromorphic domain understanding (meaningful UX for SNN workflows)
- Psychology-informed UX design (reducing cognitive load, progressive disclosure)
- Mobile/cross-platform expertise leveraging 7 years of mobile development experience
- The ability to bridge disciplines, which is the core skill neuromorphic companies need

---

## 3. Feature Overview

### 3.1 CNL Editor

A code editor widget for `.cnl` specification files with neuromorphic-aware features:

- **Syntax highlighting** — Keywords (MUST, MUST NOT, ONLY IF, DURING, WITH), subjects (neuron, connection, synapse, population), and numeric parameters coloured distinctly.
- **Autocomplete** — Suggests valid continuations as the user types. For example, after typing `The sensory neuron MUST`, the editor suggests `fire ONLY IF`, `NOT fire DURING`, `decay WITH`, etc.
- **Inline validation** — As the user types, the backend parses each sentence and marks errors (red underline with tooltip showing what was expected).
- **Template insertion** — A sidebar with drag-and-drop templates for each of the 8 concept types. Clicking a template inserts a skeleton sentence with placeholder values.
- **Parameter editing** — Numeric values in the spec are rendered as inline editable fields (tap to type a new value, or use steppers to increment/decrement).

### 3.2 Visual Pipeline

A step-by-step view showing the current state of the pipeline:

```
┌──────────┐    ┌──────────────┐    ┌──────────────┐    ┌────────────┐    ┌──────────────┐
│  PARSE   │ →  │  VALIDATE L1 │ →  │  VALIDATE L2 │ →  │  GENERATE  │ →  │  SIMULATE    │
│  ✓ 7/7   │    │  ✓ 12/12     │    │  ✓ 3/3       │    │  ✓ network │    │  ✓ 1.0s      │
└──────────┘    └──────────────┘    └──────────────┘    └────────────┘    └──────────────┘
```

Each step is tappable and expands to show:
- **Parse** — Table of parsed specs (concept, subject, action, condition).
- **Validate L1** — List of invariants with pass/fail status and explanations.
- **Validate L2** — Cross-sentence consistency results.
- **Generate** — Network topology graph (see 3.3).
- **Simulate** — Plots and metrics (see 3.4).

The pipeline runs automatically whenever the spec changes (debounced by 500ms), with each step showing its status in real time.

### 3.3 Network Visualiser

An interactive graph view of the generated Nengo network:

- **Nodes** — Populations (ensembles) shown as circles, sized by neuron count.
- **Edges** — Connections shown as arrows, coloured by type (excitatory = blue, inhibitory = red), thickness scaled by synaptic weight.
- **Labels** — Node labels show the population name, neuron model (LIF), and key parameters (τ, threshold). Edge labels show weight and delay.
- **Interaction** — Tap a node to see its full parameter table. Tap an edge to see connection details. Drag to rearrange. Pinch to zoom, pan to scroll.
- **Parameter editing** — Parameters shown in the graph can be edited inline. Changes propagate back to the CNL spec.

### 3.4 Simulation Dashboard

Visualisation of simulation results:

- **Spike raster plot** — Time on x-axis, neuron index on y-axis, dots for spikes. Standard computational neuroscience format.
- **Membrane voltage trace** — Time on x-axis, voltage on y-axis. Shows subthreshold dynamics, spikes, and refractory periods.
- **Input/output overlay** — Input stimulus and motor output plotted together to show the network's transfer function.
- **Summary statistics** — Mean firing rate, spike count, inter-spike interval distribution, latency from input to output spike.
- **Simulation controls** — Duration slider, step button (advance one timestep), play/pause, speed control.

### 3.5 Template Gallery

A searchable library of pre-built `.cnl` specifications:

- Each template has a title, description, difficulty level, and tags (e.g., "learning", "reflex", "BCI", "inhibition").
- Templates are grouped by application domain: motor control, sensory processing, learning, BCI.
- Tapping "Use this template" loads it into the editor.
- The gallery ships with the existing example and demo specs from the repository (reflex arc, slip reflex, EMG gripper, EEG attention, audio wakeword, plus the 6 hardware demo specs).

### 3.6 Compact Number Editing

A compact editor-local flow for tuning network parameters:

- When the caret is on a numeric literal, Studio exposes a compact numeric editor instead of a dedicated parameter pane.
- Editing a number updates the CNL spec in place and re-runs parse/validate after debounce.
- Generate remains focused on generated artifacts such as the network graph and generated code rather than source-editing controls.
- Keyboard access remains available so numeric tuning does not require leaving the editor flow.

### 3.7 Export and Sharing

- **Download spec** — `.cnl` file.
- **Download report** — HTML or PDF report with the spec, validation results, network diagram, and simulation plots.
- **Download Nengo script** — Standalone Python script that recreates the network and simulation without neurocnl.
- **Copy shareable link** — Encodes the current spec in the URL for sharing.

---

## 4. Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| **Backend** | FastAPI (Python 3.11+) | Direct import of the neurocnl library. Async support. OpenAPI/Swagger auto-documentation. Widely used in ML/AI tooling. |
| **Frontend** | Flutter 3 (Web) + Dart | Single codebase for web, desktop, and mobile. Leverages 7 years of mobile development experience. Material 3 design system. High-performance rendering via Skia/CanvasKit. |
| **Editor** | `flutter_code_editor` + `highlight` | Rich code editor widget with custom language definitions for CNL syntax highlighting. Line numbers, autocomplete overlay, and inline markers. |
| **Network graph** | `graphview` (flutter_graphview) or custom `CustomPainter` | `graphview` for structured graph layouts (populations + connections). Custom `CustomPainter` as fallback for bespoke rendering with gesture detection. |
| **Simulation plots** | `fl_chart` | High-performance Flutter charting library. Supports scatter plots (spike rasters), line charts (voltage traces), and interactive tooltips. |
| **Styling** | Material 3 + custom `ThemeData` | Flutter's built-in theming system. Consistent design without external CSS frameworks. Adaptive layouts via `LayoutBuilder` and `MediaQuery`. |
| **State management** | Riverpod | Type-safe, compile-time checked, testable. Supports async providers for API calls. Preferred over BLoC for this app's complexity level. |
| **API communication** | `http` + `web_socket_channel` | `http` package for REST calls (parse/validate/generate). `web_socket_channel` for streaming simulation data. |
| **Deployment** | Docker Compose (FastAPI + Nginx serving Flutter web build) | Single `docker compose up` to run locally. No cloud dependency. Can be deployed to any VPS for demo hosting. |
| **Testing** | pytest (backend), Flutter widget tests + integration tests (frontend) | Matches existing neurocnl test infrastructure (backend). Standard Flutter testing (frontend). |
| **CI/CD** | GitHub Actions | Automated testing, building, and deployment. See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md). |

### Why Flutter instead of React?

Flutter is the preferred choice for this project because:
- **Existing expertise** — 7 years of mobile development experience makes Flutter the most productive framework. No ramp-up time on a new ecosystem.
- **Cross-platform potential** — The same codebase can run as a web app, desktop app (macOS/Linux/Windows), and mobile app. This is valuable for demo presentations, workshop use, and future distribution.
- **High-performance rendering** — Flutter's Skia/CanvasKit engine renders the network graph and simulation plots with GPU acceleration, which matters for real-time parameter exploration.
- **Material 3** — Built-in design system with adaptive layouts, dark mode, and accessibility features out of the box.
- **Single language** — Dart for everything (UI, state, API communication, tests). No context-switching between TypeScript and JSX.

### Why not Streamlit or Gradio?

Streamlit and Gradio are fast to prototype but limited in:
- Custom editor integration
- Interactive graph visualisation
- Fine-grained layout control
- WebSocket-based real-time updates

For a portfolio piece targeting engineering companies, a proper Flutter + FastAPI stack demonstrates production-grade skills. The neurocnl backend is non-trivial (Nengo simulations can take seconds), so a proper async API with WebSocket support is the right architecture.

---

## 5. Development Phases

### Phase 1: Backend API + Minimal Frontend (2–3 weeks)

**Goal:** A working web app where you can type a CNL spec and see parse + validation results.

**Backend:**
- FastAPI app with endpoints: `POST /parse`, `POST /validate`, `POST /generate`, `POST /simulate`.
- Each endpoint wraps the corresponding neurocnl function.
- Error responses return structured validation failures.
- CORS configuration for local development.

**Frontend:**
- Flutter web app with a code editor on the left and a results panel on the right.
- Editor sends the spec to the backend on each change (debounced).
- Results panel shows parsed specs as a table and validation results as a pass/fail list.
- No graph visualisation or simulation plots yet.

**CI/CD:**
- GitHub Actions workflow for backend tests (pytest) and Flutter web build.
- Docker Compose for local development.

**Deliverable:** A locally runnable app (`docker compose up`) that demonstrates the parse → validate flow interactively.

### Phase 2: Network Visualisation + Simulation Plots (2–3 weeks)

**Goal:** See the generated network as a graph and simulation results as plots.

**Backend:**
- `POST /generate` returns a serialised network description (nodes, edges, parameters) as JSON, not a `nengo.Network` object.
- `POST /simulate` runs the Nengo simulation and returns probe data (spike times, voltage traces) as JSON arrays.

**Frontend:**
- Network graph panel using `graphview`: populations as nodes, connections as edges, parameters as labels.
- Simulation dashboard with `fl_chart`: spike raster plot, membrane voltage trace, input/output overlay.
- Pipeline progress bar showing parse → validate → generate → simulate with status indicators.

**Deliverable:** Full visual pipeline from CNL text to simulation plots.

### Phase 3: Interactive Features (2–3 weeks)

**Goal:** Make the UI genuinely useful for parameter exploration and iterative design.

**Features:**
- Parameter Explorer panel with auto-extracted sliders from the current spec.
- Template Gallery with the existing example and demo specs.
- Custom CNL language definition: syntax highlighting, autocomplete, hover documentation.
- Inline validation markers in the editor (red underlines on invalid sentences).
- Graph ↔ editor synchronisation: tapping a node in the graph highlights the corresponding sentence in the editor.

**Deliverable:** An interactive design tool, not just a viewer.

### Phase 4: Polish + Export + Deployment (1–2 weeks)

**Goal:** Portfolio-ready polish and production deployment.

**Features:**
- Export as HTML report, standalone Python script, or `.cnl` file.
- Shareable URL encoding.
- Responsive layout for presentation on different screen sizes.
- Guided onboarding tour for first-time users.
- README with screenshots, GIF demos, and installation instructions.
- CI/CD pipeline deploying to production (see [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)).

**Deliverable:** A polished, documented, deployed, demo-ready application.

---

## 6. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Browser (Flutter Web + Dart)                      │
│                                                                     │
│  ┌───────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │
│  │ CNL Editor    │  │ Network Graph│  │ Simulation Dashboard     │ │
│  │ (code_editor) │  │ (graphview)  │  │ (fl_chart)               │ │
│  └───────┬───────┘  └──────────────┘  └──────────────────────────┘ │
│          │                                                          │
│  ┌───────▼───────────────────────────────────────────────────────┐  │
│  │              State Manager (Riverpod)                         │  │
│  │  spec, parsedSpecs, validationResults, networkGraph,          │  │
│  │  simulationData, uiPreferences                                │  │
│  └───────┬───────────────────────────────────────────────────────┘  │
│          │ REST / WebSocket                                         │
└──────────┼──────────────────────────────────────────────────────────┘
           │
┌──────────▼──────────────────────────────────────────────────────────┐
│                     FastAPI Backend (Python)                         │
│                                                                     │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌─────────────────┐  │
│  │ /parse     │ │ /validate  │ │ /generate  │ │ /simulate       │  │
│  │            │ │            │ │            │ │ (WebSocket opt.) │  │
│  └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └────────┬────────┘  │
│        │              │              │                  │           │
│  ┌─────▼──────────────▼──────────────▼──────────────────▼────────┐  │
│  │                    neurocnl library                            │  │
│  │  parse() → validate() → generate() → simulate via Nengo       │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 7. Portfolio and Job Search Fit

### How this strengthens the portfolio

| What it demonstrates | Why Dutch neuromorphic companies care |
|---|---|
| Full-stack engineering (Flutter + FastAPI + Docker) | They need engineers who can build tooling, not just write papers |
| Cross-platform mobile/web expertise (7 years mobile + Flutter web) | Shows production engineering skills beyond research prototyping |
| Domain-specific UX for SNN workflows | Shows you understand the neuromorphic workflow deeply enough to design tools for it |
| Psychology-informed design (cognitive load, progressive disclosure) | Your psychology degree becomes a tangible engineering asset |
| Direct integration with Nengo + Loihi ecosystem | Nengo is the standard tool in the field; Loihi is Intel's chip; showing you can wrap both is directly relevant |
| Bridging neuroscience and software engineering | This is the exact gap that neuromorphic companies struggle to fill |

### Relevant Dutch companies and how to position this

| Company | Location | What they do | How neurocnl Studio maps |
|---|---|---|---|
| **Innatera Nanosystems** | Delft | Ultra-low-power analog neuromorphic processors for always-on sensing | The UI demonstrates spec-driven SNN design that could feed into their toolchain; shows understanding of sensor-to-spike pipelines |
| **SynSense** | Zurich (NL operations) | Event-driven AI processors | Event-driven architectures align with the spike-based paradigm; the visualisation of spike rasters and temporal dynamics is directly relevant |
| **Imec** | Leuven/Eindhoven | Semiconductor research including neuromorphic | Research tooling and rapid prototyping are core needs; a visual spec tool fits their workflow |
| **Intel Neuromorphic** | Global (NL contributors) | Loihi chip + Lava framework | neurocnl already supports the Loihi backend; the UI makes Loihi development accessible |
| **TU Delft BioRobotics** | Delft | Neuromorphic control for robotics | The reflex arc and motor control demos map directly; the UI lets researchers iterate faster |
| **Radboud University DCC** | Nijmegen | Computational neuroscience | The CNL-to-network pipeline is a research tool; the UI enables non-programmer neuroscientists |

### Talking points for interviews

1. "I built a visual tool that lets you write spiking neural network specifications in plain English and see the results immediately — spike rasters, network topology, and validation against physical constraints."
2. "My psychology background informed the UX: I used progressive disclosure to reduce cognitive load, so a neuroscience researcher can start with templates and gradually learn the CNL grammar."
3. "The tool wraps the Nengo ecosystem and supports the Loihi backend, so specs written in it can target Intel's neuromorphic hardware."
4. "I built the frontend in Flutter, leveraging my 7 years of mobile development experience — the same codebase runs as a web app and could be compiled for desktop or mobile for workshop use."
5. "I designed it as a portfolio piece specifically for the Dutch neuromorphic sector, understanding that companies like Innatera and SynSense need engineers who can bridge neuroscience, hardware, and software."

---

## 8. Success Metrics

| Metric | Target |
|---|---|
| A first-time user can load a template and see a simulation in under 2 minutes | Measured via onboarding flow |
| All 12 existing specs (6 examples + 6 demos) load and run correctly through the UI | Functional test |
| Parameter changes reflect in the simulation within 3 seconds | Performance test |
| The app runs locally with a single `docker compose up` command | Deployment test |
| CI/CD pipeline deploys to production on every merge to `main` | Automation test |
| The repository has a README with screenshots and a GIF demo | Documentation check |
| At least one Dutch neuromorphic company contact has seen a demo | Networking milestone |

---

## 9. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Nengo simulations are slow (seconds per run), making the UI feel sluggish | Cache parse and validation results. Show simulation progress. Offer "validate only" mode for fast iteration. Use background workers for simulation. |
| Flutter web performance with CanvasKit can have large initial load (~2MB WASM) | Use `--web-renderer html` for faster initial load during development. Switch to CanvasKit for production (better rendering). Lazy-load heavy screens. |
| Custom code editor in Flutter is less mature than Monaco | `flutter_code_editor` with `highlight` package provides syntax highlighting and line numbers. Autocomplete can be built as an overlay widget. The CNL grammar has only 8 patterns — it is small enough to handle. |
| The project scope is too large for one person | The phased plan means each phase produces a standalone deliverable. Phase 1 alone is a useful portfolio piece. |
| Nengo or its dependencies have installation issues | Docker containerisation isolates dependencies. The Dockerfile pins all versions. |

---

## 10. Related Documents

| Document | Description |
|---|---|
| [UI_SPEC.md](./UI_SPEC.md) | Full technical specification: API contracts, Dart models, widget tree, Docker config, CI/CD, user stories |
| [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) | CI/CD pipeline setup, deployment targets for backend and frontend, environment configuration |
| [USER_HAPPY_FLOW.md](./USER_HAPPY_FLOW.md) | Step-by-step walkthrough of the user experience from first launch to exporting results |
| ROADMAP.md | Library feature roadmap (STDP, multi-population, hardware export, etc.) |
| PORTFOLIO_ROADMAP.md | Prioritised milestones combining library work with hardware demos |

This UI wrapper is a standalone project that sits alongside the existing roadmaps. It does not replace any planned library work — it wraps whatever the library can do at any given time.

As library features are added (STDP learning, multi-population topology, spike encoding), the UI automatically gains those capabilities because it calls the library's public API.

The UI is best started **after Priority 2 (STDP learning rules)** from the Portfolio Roadmap, so that the first version of the UI can demonstrate learning — the most compelling feature for neuromorphic companies. However, it can also be started earlier with the current 8-concept grammar, which is already sufficient for a functional demo.
