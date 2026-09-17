# NeuroSim — Visual Network Design & Simulation Workbench
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

> **Status (2026-05-14):** This spec describes the originally planned standalone product.
> The active product shape is Studio-integrated: NeuroSim provides a FastAPI backend mounted
> by CNL Studio, and there is no standalone Flutter frontend. Sections describing the frontend,
> template gallery, and standalone build are historical. See `README.md` for the current
> architecture and supported scope.

---

## Overview

NeuroSim is a visual drag-and-drop workbench for designing, parameterizing, and simulating spiking neural networks. It generates neurocnl CNL specs from a graphical canvas, eliminating the need to write spec syntax or Python code. It targets hardware engineers, signal processing specialists, and other professionals who understand systems design but lack computational neuroscience background.

Workflow ownership note:

- NeuroSim is the visual editor and topology-inspection mode, not the primary deployment router.
- Deployment target selection belongs to `neurocnl` `Studio`, and canonical hardware execution continues in `Neurochip`.
- The suite-level contract for this flow is documented in
  [docs/ADR-claude/0020-studio-owns-deployment-target-selection.md](/NeuroMorphicToolKit/docs/ADR-claude/0020-studio-owns-deployment-target-selection.md).

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

**NS-E2 · Keep hardware execution routing in Studio**
As an engineer moving from design to hardware execution,
I want NeuroSim to stay focused on editing, inspection, and preview,
so that deployment target choice and hardware launch continue through `Studio`.

Acceptance criteria:
- Default NeuroSim chrome does not expose a first-class `NeuroSim -> Neurochip` launch action
- Operator-facing copy tells the user to return to `Studio` for target selection and hardware execution
- NeuroSim accepts incoming `Studio` imports for canvas hydration, but does not call `Neurochip` directly from the default flow
- Any future expert-only shortcut must be intentionally reintroduced and clearly labeled as non-canonical

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
    id: str                          # e.g., "lif_population"
    name: str                        # e.g., "LIF Population"
    category: str                    # e.g., "Neurons"
    description: str                 # Plain-language description
    icon: str                        # Material icon name
    parameters: list[ParameterDef]   # Configurable parameters with defaults and ranges
    ports: list[PortDef]             # Input/output connection ports
    cnl_template: str                # CNL sentence template this block maps to
```

**ParameterDef**
```python
class ParameterDef(BaseModel):
    name: str                        # e.g., "tau_rc"
    label: str                       # e.g., "Membrane Time Constant"
    description: str                 # What this does, in engineering terms
    type: Literal["float", "int", "bool", "enum"]
    default: float | int | bool | str
    min: float | int | None = None
    max: float | int | None = None
    unit: str | None = None          # e.g., "s", "mV", "Hz"
    enum_values: list[str] | None = None
```

**CanvasGraph**
```python
class CanvasGraph(BaseModel):
    nodes: list[CanvasNode]
    edges: list[CanvasEdge]
    metadata: dict                   # Layout positions, zoom, viewport

class CanvasNode(BaseModel):
    id: str
    component_id: str                # References ComponentBlock.id
    parameters: dict[str, Any]       # Current parameter values
    position: tuple[float, float]    # Canvas x, y

class CanvasEdge(BaseModel):
    id: str
    source_node_id: str
    source_port: str
    target_node_id: str
    target_port: str
    parameters: dict[str, Any]       # Synapse weight, learning rule, delay
```

**SweepRequest**
```python
class SweepRequest(BaseModel):
    graph: CanvasGraph
    parameter_path: str              # e.g., "nodes.sensory.tau_rc"
    start: float
    end: float
    steps: int                       # max 20
    simulation_duration_ms: float = 500.0
```

### Service Architecture

```
<!-- HISTORICAL: standalone frontend not implemented -->
NeuroSim Frontend (Flutter)
       |
       | HTTP / WebSocket
       |
NeuroSim Backend (FastAPI)
       |
       | Python import
       |
neurocnl core library
       |
       | Nengo simulation
       |
    Nengo engine
```

The NeuroSim backend is a **separate FastAPI process** that imports `neurocnl` as a library dependency. It does NOT proxy through the neurocnl backend — it calls the library directly for lower latency on preview simulations.

For cross-suite workflow integration, NeuroSim accepts incoming `Studio`
handoffs for canvas hydration. Hardware execution continues through the
authoritative `Studio -> Neurochip` route instead of direct NeuroSim-originated
backend calls.

### Component Library

Components are defined as JSON manifest files in `neurosim/components/`:

```
components/
  neurons/
    lif_population.json
    adaptive_lif.json
  synapses/
    static_synapse.json
    stdp_synapse.json
    pes_synapse.json
  encoders/
    rate_encoder.json
    temporal_encoder.json
    delta_encoder.json
  patterns/
    reflex_arc.json
    cpg_oscillator.json
    winner_take_all.json
    lateral_inhibition.json
```

Each manifest follows the `ComponentBlock` schema. Users can add custom components by dropping JSON files into a user components directory.

---

## Frontend Spec

### Technology

<!-- HISTORICAL: standalone frontend not implemented -->
- **Framework:** Flutter (web + desktop)
- **State management:** Riverpod (matches neurocnl Studio pattern)
- **Canvas:** Custom `CustomPainter` widget for node-edge graph rendering
- **Design system:** `neuro-flutter-ui` shared package

### Screen Layout

```
┌──────────────────────────────────────────────────────┐
│ Toolbar: [New] [Open] [Save] [Export▾] [Deploy]      │
├────────┬─────────────────────────────┬───────────────┤
│        │                             │               │
│ Comp-  │        Canvas               │  Property     │
│ onent  │        (drag & drop)        │  Panel        │
│ Library│                             │               │
│        │                             │  - Node params│
│ [Search]                             │  - Edge params│
│        │                             │  - Validation │
│ Neurons│                             │    warnings   │
│ Synapse│                             │               │
│ Encoder│                             │               │
│ Pattern│                             │               │
│        │                             │               │
├────────┴─────────────────────────────┴───────────────┤
│ Preview Panel: [Spike Raster] [Voltage] [CNL Spec]   │
│ ▸ Play  ‖ Pause  ◼ Stop   Duration: [500ms]         │
└──────────────────────────────────────────────────────┘
```

- **Left sidebar:** Component library with search and categories
- **Center:** Canvas for node-edge graph editing
- **Right sidebar:** Property panel for selected node/edge
- **Bottom panel:** Collapsible preview (spike raster, voltage traces, or CNL spec view)

### Key Widgets

| Widget | Purpose |
|---|---|
| `ComponentLibrarySidebar` | Categorized, searchable list of draggable blocks |
| `NetworkCanvas` | Custom painter for nodes, edges, selection, pan/zoom |
| `CanvasNode` | Renders a single population block with ports |
| `CanvasEdge` | Renders a directed connection with parameter badge |
| `PropertyPanel` | Dynamic form generated from `ParameterDef` schema |
| `PreviewPanel` | Tabbed panel: spike raster, voltage trace, CNL text |
| `SweepGrid` | Grid of simulation result thumbnails for parameter sweeps |
| `TemplateGallery` | Card grid of starter templates with thumbnails |
| `ExportDialog` | Format selection and export configuration |

### Providers (Riverpod)

| Provider | State |
|---|---|
| `canvasGraphProvider` | Current `CanvasGraph` — nodes, edges, layout |
| `selectedElementProvider` | Currently selected node or edge ID |
| `componentLibraryProvider` | Available `ComponentBlock` list from backend |
| `cnlSpecProvider` | Generated CNL spec text (derived from graph) |
| `validationProvider` | Layer 1 validation results for current graph |
| `previewProvider` | Latest preview simulation result |
| `sweepProvider` | Parameter sweep configuration and results |
| `projectProvider` | Save/load project state |

### Canvas Interaction Model

- **Pan:** Middle-click drag or two-finger trackpad
- **Zoom:** Scroll wheel or pinch
- **Select:** Click node or edge
- **Multi-select:** Shift-click or rubber band
- **Move:** Drag selected nodes
- **Connect:** Click output port → drag to input port → release
- **Delete:** Select → Backspace/Delete key
- **Undo/Redo:** Ctrl+Z / Ctrl+Shift+Z
- **Drop component:** Drag from sidebar → drop on canvas

---

## File Structure

```
NeuroSim/
├── neurosim/                        # Python backend
│   ├── app/
│   │   ├── main.py                  # FastAPI app
│   │   ├── routers/
│   │   │   ├── components.py
│   │   │   ├── templates.py
│   │   │   ├── validation.py
│   │   │   ├── generation.py
│   │   │   ├── preview.py
│   │   │   ├── sweep.py
│   │   │   ├── export.py
│   │   │   └── projects.py
│   │   ├── schemas/
│   │   │   ├── canvas.py            # CanvasGraph, CanvasNode, CanvasEdge
│   │   │   ├── components.py        # ComponentBlock, ParameterDef
│   │   │   ├── sweep.py
│   │   │   └── export.py
│   │   └── services/
│   │       ├── graph_to_cnl.py      # Canvas graph → CNL spec conversion
│   │       ├── cnl_to_graph.py      # CNL spec → canvas graph conversion
│   │       ├── preview_runner.py    # Short simulation for live preview
│   │       └── sweep_runner.py      # Batch parameter sweep
│   ├── components/                  # JSON component manifests
│   │   ├── neurons/
│   │   ├── synapses/
│   │   ├── encoders/
│   │   └── patterns/
│   ├── pyproject.toml
│   └── tests/
<!-- HISTORICAL: standalone frontend not implemented -->
├── frontend/                        # Flutter frontend
│   ├── lib/
│   │   ├── app.dart
│   │   ├── screens/
│   │   │   ├── canvas_screen.dart
│   │   │   ├── template_gallery_screen.dart
│   │   │   └── sweep_results_screen.dart
│   │   ├── widgets/
│   │   │   ├── network_canvas.dart
│   │   │   ├── canvas_node.dart
│   │   │   ├── canvas_edge.dart
│   │   │   ├── component_library_sidebar.dart
│   │   │   ├── property_panel.dart
│   │   │   ├── preview_panel.dart
│   │   │   ├── sweep_grid.dart
│   │   │   └── export_dialog.dart
│   │   ├── providers/
│   │   ├── models/
│   │   └── services/
│   │       └── api_client.dart
│   ├── pubspec.yaml
│   └── test/
├── docker-compose.yml
├── Dockerfile
└── README.md
```
