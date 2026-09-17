# UI Technical Specification — neurocnl Studio

Technical specification for the visual interface wrapping the neurocnl library, built with Flutter (web) and FastAPI.

---

## 1. System Architecture

### 1.1 Overview

neurocnl Studio is a client-server application:

- **Backend** — A Python FastAPI server that imports and wraps the neurocnl library.
- **Frontend** — A Flutter web application compiled to JavaScript/CanvasKit and served as static assets.
- **Communication** — REST (JSON) for stateless operations (parse, validate, generate). WebSocket for streaming simulation data.

Both are packaged in a Docker Compose setup for single-command local deployment.

### 1.2 Directory Structure

```
neurocnl-studio/
├── backend/
│   ├── app/
│   │   ├── main.py                 # FastAPI app, CORS, lifespan
│   │   ├── routers/
│   │   │   ├── parse.py            # POST /api/parse
│   │   │   ├── validate.py         # POST /api/validate
│   │   │   ├── generate.py         # POST /api/generate
│   │   │   ├── simulate.py         # POST /api/simulate (+ WebSocket)
│   │   │   ├── templates.py        # GET  /api/templates
│   │   │   └── export.py           # POST /api/export
│   │   ├── schemas/
│   │   │   ├── parse.py            # Pydantic models for parse I/O
│   │   │   ├── validate.py         # Pydantic models for validation I/O
│   │   │   ├── generate.py         # Pydantic models for generation I/O
│   │   │   ├── simulate.py         # Pydantic models for simulation I/O
│   │   │   └── common.py           # Shared types (SpecSentence, Error, etc.)
│   │   ├── services/
│   │   │   ├── neurocnl_bridge.py  # Wraps neurocnl library calls
│   │   │   ├── network_serializer.py  # Converts nengo.Network → JSON graph
│   │   │   └── simulation_runner.py   # Runs Nengo sim, extracts probe data
│   │   └── templates/              # Built-in .cnl template files
│   │       ├── reflex_arc.cnl
│   │       ├── slip_reflex.cnl
│   │       ├── emg_gripper.cnl
│   │       ├── eeg_attention.cnl
│   │       └── audio_wakeword.cnl
│   ├── tests/
│   │   ├── test_parse_router.py
│   │   ├── test_validate_router.py
│   │   ├── test_generate_router.py
│   │   └── test_simulate_router.py
│   ├── requirements.txt
│   └── Dockerfile
│
├── frontend/
│   ├── lib/
│   │   ├── main.dart                          # App entry point, MaterialApp, theme
│   │   ├── app.dart                           # Root widget, route configuration
│   │   ├── models/
│   │   │   ├── parse_result.dart              # ParseResult, ParsedSpec
│   │   │   ├── validation_result.dart         # ValidationResult, InvariantResult
│   │   │   ├── network_graph.dart             # NetworkGraph, NetworkNode, NetworkEdge
│   │   │   ├── simulation_data.dart           # SimulationData, ProbeData, Summary
│   │   │   └── template.dart                  # Template model
│   │   ├── providers/
│   │   │   ├── spec_provider.dart             # Spec text state + debounce
│   │   │   ├── pipeline_provider.dart         # Pipeline orchestration + status
│   │   │   ├── simulation_provider.dart       # WebSocket simulation state
│   │   │   └── template_provider.dart         # Template gallery state
│   │   ├── services/
│   │   │   ├── api_client.dart                # HTTP client wrapper
│   │   │   └── websocket_client.dart          # WebSocket client for simulation
│   │   ├── widgets/
│   │   │   ├── editor/
│   │   │   │   ├── cnl_editor.dart            # Code editor with syntax highlighting
│   │   │   │   ├── cnl_syntax.dart            # CNL language definition (highlight)
│   │   │   │   └── cnl_autocomplete.dart      # Autocomplete overlay
│   │   │   ├── pipeline/
│   │   │   │   ├── pipeline_bar.dart          # Step-by-step status bar
│   │   │   │   ├── parse_results.dart         # Parsed specs table
│   │   │   │   └── validation_results.dart    # Pass/fail list with explanations
│   │   │   ├── network/
│   │   │   │   ├── network_graph.dart         # Graph view (graphview / CustomPainter)
│   │   │   │   └── node_detail.dart           # Population/connection detail panel
│   │   │   ├── simulation/
│   │   │   │   ├── simulation_dashboard.dart  # Container for all sim plots
│   │   │   │   ├── spike_raster.dart          # Raster plot (fl_chart)
│   │   │   │   ├── voltage_trace.dart         # Membrane voltage plot (fl_chart)
│   │   │   │   └── sim_controls.dart          # Duration, play/pause, speed
│   │   │   ├── templates/
│   │   │   │   ├── template_gallery.dart      # Grid of template cards
│   │   │   │   └── template_card.dart         # Single template card
│   │   │   ├── parameters/
│   │   │   │   ├── parameter_explorer.dart    # Auto-generated sliders
│   │   │   │   └── parameter_slider.dart      # Single parameter slider
│   │   │   └── layout/
│   │   │       ├── app_shell.dart             # Top-level layout (responsive)
│   │   │       ├── sidebar.dart               # Template gallery + parameters
│   │   │       └── header.dart                # App title, menu, export
│   │   └── utils/
│   │       ├── parameter_extractor.dart       # Extract params from spec text
│   │       └── debouncer.dart                 # Debounce utility
│   ├── test/
│   │   ├── widgets/
│   │   │   ├── cnl_editor_test.dart
│   │   │   ├── pipeline_bar_test.dart
│   │   │   ├── network_graph_test.dart
│   │   │   ├── spike_raster_test.dart
│   │   │   └── parameter_explorer_test.dart
│   │   ├── providers/
│   │   │   └── pipeline_provider_test.dart
│   │   └── utils/
│   │       └── parameter_extractor_test.dart
│   ├── web/
│   │   ├── index.html
│   │   ├── manifest.json
│   │   └── favicon.png
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   └── Dockerfile
│
├── .github/
│   └── workflows/
│       ├── ci.yml                  # Lint + test on every push/PR
│       └── deploy.yml              # Build + deploy on merge to main
│
├── docker-compose.yml
├── docker-compose.dev.yml
└── README.md
```

---

## 2. User Stories

User stories structured for agentic implementation — each story is self-contained with clear acceptance criteria, API dependencies, and testable outcomes.

### Epic 1: Spec Editing

| ID | Story | Acceptance Criteria | Priority |
|---|---|---|---|
| US-01 | As a neuromorphic engineer, I want to type CNL sentences in an editor so that I can define my network spec. | Editor loads, accepts text input, preserves state across tab switches. Line numbers visible. | P0 |
| US-02 | As a user, I want CNL keywords highlighted in distinct colours so that I can quickly scan my spec. | `MUST`, `ONLY IF`, `DURING`, `WITH` appear bold and coloured. Subject names and numbers use different colours. | P0 |
| US-03 | As a user, I want autocomplete suggestions after typing `The sensory neuron MUST` so that I don't have to memorise the grammar. | Typing `MUST ` triggers an overlay with valid continuations (`fire ONLY IF...`, `NOT fire DURING...`, `decay WITH...`). Selecting inserts the text. | P1 |
| US-04 | As a user, I want to see a red underline on invalid CNL sentences so that I know what to fix. | After debounce, each line is parsed. Invalid lines show a red underline. Tapping the underline shows the error message in a tooltip. | P1 |
| US-05 | As a user, I want to load a template so that I can start from a working example instead of a blank editor. | Template gallery shows at least 6 templates. Tapping "Use" replaces editor content. The template parses and validates successfully. | P0 |

### Epic 2: Validation Pipeline

| ID | Story | Acceptance Criteria | Priority |
|---|---|---|---|
| US-06 | As a user, I want to see parsed specs in a table so that I understand what the parser extracted. | Parse results table shows columns: Line, Subject, Concept, Action, Condition. One row per valid sentence. | P0 |
| US-07 | As a user, I want to see Layer 1 validation results as a pass/fail list so that I know if my parameters are biologically plausible. | Validation panel shows invariant names, descriptions, and green checkmark / red cross. Failed invariants show the constraint that was violated. | P0 |
| US-08 | As a user, I want to see Layer 2 cross-reference results so that I know my neurons are properly connected. | L2 panel shows neurons found, dangling connection checks, and contradictory parameter checks. | P1 |
| US-09 | As a user, I want the pipeline to run automatically when I stop typing so that I always see up-to-date results. | After 500ms debounce, parse and validate run. Pipeline bar updates with status. No manual "Run" button needed for parse+validate. | P0 |

### Epic 3: Network Visualisation

| ID | Story | Acceptance Criteria | Priority |
|---|---|---|---|
| US-10 | As a user, I want to see my network as a graph with nodes and edges so that I can understand the topology. | After successful generation, a graph renders with one node per ensemble/input and one edge per connection. Labels show names. | P0 |
| US-11 | As a user, I want to tap a node to see its parameters (neuron count, type, tau, threshold) so that I can verify the generation. | Tapping a node opens a detail panel or bottom sheet showing all parameters from the `/generate` response. | P1 |
| US-12 | As a user, I want excitatory connections in blue and inhibitory in red so that I can visually distinguish them. | Edge colour is blue for positive weights and red for negative weights. Edge thickness scales with absolute weight value. | P1 |
| US-13 | As a user, I want to drag nodes to rearrange the graph so that I can create clearer layouts. | Nodes respond to drag gestures. New positions persist within the session. | P2 |

### Epic 4: Simulation

| ID | Story | Acceptance Criteria | Priority |
|---|---|---|---|
| US-14 | As a user, I want to run a simulation and see spike rasters so that I can verify firing behaviour. | Tapping "Run Simulation" calls `/simulate`. Spike raster plot shows time vs neuron index with dots for spikes. | P0 |
| US-15 | As a user, I want to see membrane voltage traces so that I can inspect subthreshold dynamics. | Voltage trace plot shows time on x-axis, voltage on y-axis. Visible spikes, decay, and refractory periods. | P1 |
| US-16 | As a user, I want to adjust the simulation duration with a slider so that I can explore different timescales. | Duration slider (0.1s to 10s) updates the `/simulate` request. Plot x-axis rescales accordingly. | P1 |
| US-17 | As a user, I want to see a progress indicator during simulation so that I know it is working. | During simulation (which can take 2 to 10s), a progress bar or spinner is visible. The pipeline bar shows "running" state for the simulate step. | P0 |
| US-18 | As a user, I want to see summary statistics (spike count, mean firing rate, latency) so that I can quantify network behaviour. | Summary card below plots shows the stats from the `/simulate` response `summary` object. | P1 |

### Epic 5: Parameter Exploration

| ID | Story | Acceptance Criteria | Priority |
|---|---|---|---|
| US-19 | As a user, I want to edit numeric parameters without manually retyping them in the source so that I can tune values quickly. | When the caret is on a numeric literal, Studio exposes a compact numeric editor for that value. | P1 |
| US-20 | As a user, I want numeric edits to update the CNL text and re-run the pipeline so that I see effects in real time. | Applying a numeric edit updates the spec text at the correct position. After debounce, parse+validate re-run. If auto-simulate is on, simulation also re-runs. | P1 |
| US-21 | As a user, I want Generate to show the generated network artifact so that I can inspect what the pipeline produced. | The Generate workspace shows the generated graph and related artifact summary instead of source-editing controls. | P2 |

### Epic 6: Export

| ID | Story | Acceptance Criteria | Priority |
|---|---|---|---|
| US-22 | As a user, I want to download my spec as a `.cnl` file so that I can use it outside the UI. | "Download .cnl" button triggers a file download with the current editor content. | P0 |
| US-23 | As a user, I want to export a report with plots and validation results so that I can share my findings. | "Export Report" produces an HTML file containing the spec, validation results, network diagram screenshot, and simulation plots. | P2 |
| US-24 | As a user, I want to download a standalone Python script that recreates my network so that I can run it without neurocnl. | "Export Python" produces a `.py` file with Nengo code that builds and simulates the network independently. | P2 |
| US-25 | As a user, I want to copy a shareable URL so that a colleague can see the same spec. | "Copy Link" encodes the spec text in the URL hash. Opening that URL loads the spec into the editor. | P2 |

### Epic 7: Onboarding and Accessibility

| ID | Story | Acceptance Criteria | Priority |
|---|---|---|---|
| US-26 | As a first-time user, I want an onboarding tour that explains each panel so that I can learn the tool quickly. | On first visit, a 4-step overlay highlights: Editor, Pipeline Bar, Results Panel, Template Gallery. Each step has a "Next" button and "Skip" option. | P2 |
| US-27 | As a keyboard-only user, I want to navigate all panels with Tab/Shift+Tab so that I do not need a mouse. | All interactive elements are focusable. Tab order follows visual layout. Focus indicators are visible. | P1 |
| US-28 | As a screen reader user, I want all buttons and status indicators to have semantic labels so that I can use the app. | `Semantics` widgets wrap all buttons, sliders, and status badges with descriptive labels. | P2 |

---

## 3. Backend API

### 3.1 Endpoints

All endpoints are prefixed with `/api`.

#### `POST /api/parse`

Parse a CNL spec into structured specifications.

**Request:**
```json
{
  "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\nThe sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds"
}
```

**Response (200):**
```json
{
  "sentences": [
    {
      "line": 1,
      "raw": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0",
      "parsed": {
        "concept": "threshold_firing",
        "subject": "sensory neuron",
        "action": "fire",
        "verb": "MUST",
        "negated": false,
        "condition": "exceeds 1.0"
      },
      "valid": true,
      "error": null
    },
    {
      "line": 2,
      "raw": "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds",
      "parsed": {
        "concept": "refractory_period",
        "subject": "sensory neuron",
        "action": "fire",
        "verb": "MUST NOT",
        "negated": true,
        "condition": "refractory period of 0.002 seconds"
      },
      "valid": true,
      "error": null
    }
  ],
  "total": 2,
  "errors": 0
}
```

**Response (200, with parse errors):**
```json
{
  "sentences": [
    {
      "line": 1,
      "raw": "The neuron does something weird",
      "parsed": null,
      "valid": false,
      "error": "No matching CNL pattern. Expected format: 'The <subject> MUST <action> ...' See grammar reference."
    }
  ],
  "total": 1,
  "errors": 1
}
```

#### `POST /api/validate`

Validate parsed specs against Layer 1 and Layer 2 invariants.

**Request:**
```json
{
  "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n...",
  "params": {
    "threshold": 1.0,
    "resting_potential": 0.0,
    "refractory_period": 0.002,
    "tau": 0.02,
    "reset_potential": 0.0,
    "current_voltage": 0.5
  },
  "backend": "nengo"
}
```

**Response (200):**
```json
{
  "layer1": {
    "overall": true,
    "passed": [
      {
        "name": "threshold_above_resting",
        "description": "Threshold (1.0) must be above resting potential (0.0)",
        "result": true
      }
    ],
    "failed": []
  },
  "layer2": {
    "overall": true,
    "checks_passed": ["no_dangling_connections", "no_contradictory_parameters"],
    "checks_failed": [],
    "neurons_found": ["sensory neuron", "motor neuron"]
  },
  "overall": true
}
```

#### `POST /api/generate`

Generate a Nengo network and return its topology as a serialised graph.

**Request:**
```json
{
  "spec": "...",
  "params": {}
}
```

**Response (200):**
```json
{
  "network": {
    "nodes": [
      {
        "id": "sensory",
        "type": "ensemble",
        "label": "sensory neuron",
        "params": {
          "n_neurons": 50,
          "dimensions": 1,
          "neuron_type": "LIF",
          "tau_rc": 0.02,
          "tau_ref": 0.002
        },
        "position": { "x": 100, "y": 200 }
      },
      {
        "id": "motor",
        "type": "ensemble",
        "label": "motor neuron",
        "params": {
          "n_neurons": 50,
          "dimensions": 1,
          "neuron_type": "LIF",
          "tau_rc": 0.02,
          "tau_ref": 0.002
        },
        "position": { "x": 400, "y": 200 }
      },
      {
        "id": "input",
        "type": "input_node",
        "label": "stimulus",
        "position": { "x": 0, "y": 200 }
      }
    ],
    "edges": [
      {
        "id": "input_to_sensory",
        "source": "input",
        "target": "sensory",
        "params": { "transform": 1.0, "synapse": 0.01 }
      },
      {
        "id": "sensory_to_motor",
        "source": "sensory",
        "target": "motor",
        "params": {
          "transform": 1.0,
          "synapse": 0.005,
          "learning_rule": null
        }
      }
    ]
  },
  "nengo_code": "import nengo\n\nmodel = nengo.Network()\nwith model:\n    ..."
}
```

#### `POST /api/simulate`

Run a Nengo simulation and return probe data.

**Request:**
```json
{
  "spec": "...",
  "params": {},
  "duration": 1.0,
  "dt": 0.001,
  "backend": "nengo"
}
```

**Response (200):**
```json
{
  "duration": 1.0,
  "dt": 0.001,
  "timesteps": 1000,
  "probes": {
    "sensory_spikes": {
      "type": "spike_raster",
      "times": [0.045, 0.092, 0.138],
      "neuron_indices": [12, 5, 31]
    },
    "motor_spikes": {
      "type": "spike_raster",
      "times": [0.051, 0.098],
      "neuron_indices": [8, 22]
    },
    "sensory_voltage": {
      "type": "voltage_trace",
      "times": [0.0, 0.001, 0.002],
      "values": [0.0, 0.012, 0.024]
    },
    "input_signal": {
      "type": "continuous",
      "times": [0.0, 0.001],
      "values": [0.0, 0.0]
    },
    "motor_output": {
      "type": "continuous",
      "times": [0.0, 0.001],
      "values": [0.0, 0.0]
    }
  },
  "summary": {
    "sensory_spike_count": 47,
    "motor_spike_count": 32,
    "sensory_mean_rate": 47.0,
    "motor_mean_rate": 32.0,
    "first_output_spike": 0.051,
    "input_to_output_latency": 0.006
  },
  "wall_time_seconds": 2.34
}
```

#### `WebSocket /api/simulate/stream`

Streaming simulation for real-time plot updates.

**Client sends:**
```json
{
  "spec": "...",
  "params": {},
  "duration": 1.0,
  "dt": 0.001
}
```

**Server streams (one message per simulated time chunk):**
```json
{
  "type": "progress",
  "simulated_time": 0.1,
  "total_time": 1.0,
  "chunk": {
    "sensory_spikes": { "times": [], "neuron_indices": [] },
    "sensory_voltage": { "times": [], "values": [] }
  }
}
```

**Server sends on completion:**
```json
{
  "type": "complete",
  "summary": {}
}
```

#### `GET /api/templates`

List available CNL templates.

**Response (200):**
```json
{
  "templates": [
    {
      "id": "reflex_arc",
      "name": "Basic Reflex Arc",
      "description": "Minimal sensory-motor reflex with threshold, refractory, decay, and weight.",
      "tags": ["beginner", "motor-control", "reflex"],
      "difficulty": "beginner",
      "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n..."
    }
  ]
}
```

#### `POST /api/export`

Export the current session as a report or standalone script.

**Request:**
```json
{
  "spec": "...",
  "format": "html",
  "include_plots": true
}
```

**Response (200):** File download (Content-Disposition header).

---

## 4. Backend Services

### 4.1 neurocnl Bridge (`services/neurocnl_bridge.py`)

Wraps the neurocnl public API with error handling and output normalisation:

```python
from neurocnl import parse, validate, generate, ParseError


class NeurocnlBridge:
    def parse_spec(self, spec_text: str) -> list[dict]:
        results = []
        for i, line in enumerate(spec_text.splitlines(), 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                parsed = parse(line)
                results.append(
                    {"line": i, "raw": line, "parsed": parsed, "valid": True, "error": None}
                )
            except ParseError as e:
                results.append(
                    {"line": i, "raw": line, "parsed": None, "valid": False, "error": str(e)}
                )
        return results

    def validate_spec(self, spec_text: str, params: dict, backend: str = "nengo") -> dict:
        specs = [r["parsed"] for r in self.parse_spec(spec_text) if r["valid"]]
        return validate(specs, params, backend=backend)

    def generate_network(self, spec_text: str, params: dict) -> "nengo.Network":
        specs = [r["parsed"] for r in self.parse_spec(spec_text) if r["valid"]]
        return generate(specs, params)
```

### 4.2 Network Serialiser (`services/network_serializer.py`)

Converts a `nengo.Network` object into a JSON-serialisable graph structure:

```python
def serialize_network(network: "nengo.Network") -> dict:
    nodes = []
    edges = []

    for ensemble in network.ensembles:
        nodes.append(
            {
                "id": ensemble.label,
                "type": "ensemble",
                "label": ensemble.label,
                "params": {
                    "n_neurons": ensemble.n_neurons,
                    "dimensions": ensemble.dimensions,
                    "neuron_type": type(ensemble.neuron_type).__name__,
                    "tau_rc": getattr(ensemble.neuron_type, "tau_rc", None),
                    "tau_ref": getattr(ensemble.neuron_type, "tau_ref", None),
                },
            }
        )

    for node in network.nodes:
        nodes.append(
            {
                "id": node.label,
                "type": "input_node",
                "label": node.label,
            }
        )

    for conn in network.connections:
        edge = {
            "id": f"{conn.pre.label}_to_{conn.post.label}",
            "source": conn.pre.label,
            "target": conn.post.label,
            "params": {
                "transform": float(conn.transform.init)
                if hasattr(conn.transform, "init")
                else None,
                "synapse": float(conn.synapse.tau) if hasattr(conn.synapse, "tau") else None,
            },
        }
        if conn.learning_rule_type is not None:
            edge["params"]["learning_rule"] = type(conn.learning_rule_type).__name__
        edges.append(edge)

    return {"nodes": nodes, "edges": edges}
```

### 4.3 Simulation Runner (`services/simulation_runner.py`)

Runs the Nengo simulator and extracts probe data into JSON-serialisable format:

```python
import nengo
import numpy as np


def run_simulation(network: "nengo.Network", duration: float = 1.0, dt: float = 0.001) -> dict:
    with nengo.Simulator(network, dt=dt) as sim:
        sim.run(duration)

    probes = {}
    for probe in network.all_probes:
        data = sim.data[probe]
        target_label = probe.target.label if hasattr(probe.target, "label") else str(probe.target)
        probe_key = f"{target_label}_{probe.attr}" if hasattr(probe, "attr") else target_label

        if probe.attr == "spikes" or "spike" in probe_key:
            spike_times, neuron_indices = np.where(data > 0)
            probes[probe_key] = {
                "type": "spike_raster",
                "times": (spike_times * dt).tolist(),
                "neuron_indices": neuron_indices.tolist(),
            }
        else:
            times = np.arange(0, duration, dt).tolist()
            values = data[:, 0].tolist() if data.ndim > 1 else data.tolist()
            probes[probe_key] = {
                "type": "continuous",
                "times": times[: len(values)],
                "values": values,
            }

    return {"duration": duration, "dt": dt, "probes": probes}
```

---

## 5. Frontend — Flutter Widgets

### 5.1 State Management (Riverpod Providers)

Application state is managed with Riverpod providers. Each provider is independently watchable and testable:

```dart
// providers/spec_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final specTextProvider = StateProvider<String>((ref) => '');

// providers/pipeline_provider.dart
enum PipelineStepStatus { idle, running, success, error }

class PipelineState {
  final PipelineStepStatus parse;
  final PipelineStepStatus validate;
  final PipelineStepStatus generate;
  final PipelineStepStatus simulate;
  final List<ParseResult>? parseResults;
  final ValidationResult? validationResults;
  final NetworkGraph? networkGraph;
  final SimulationData? simulationData;

  const PipelineState({
    this.parse = PipelineStepStatus.idle,
    this.validate = PipelineStepStatus.idle,
    this.generate = PipelineStepStatus.idle,
    this.simulate = PipelineStepStatus.idle,
    this.parseResults,
    this.validationResults,
    this.networkGraph,
    this.simulationData,
  });

  PipelineState copyWith({
    PipelineStepStatus? parse,
    PipelineStepStatus? validate,
    PipelineStepStatus? generate,
    PipelineStepStatus? simulate,
    List<ParseResult>? parseResults,
    ValidationResult? validationResults,
    NetworkGraph? networkGraph,
    SimulationData? simulationData,
  }) {
    return PipelineState(
      parse: parse ?? this.parse,
      validate: validate ?? this.validate,
      generate: generate ?? this.generate,
      simulate: simulate ?? this.simulate,
      parseResults: parseResults ?? this.parseResults,
      validationResults: validationResults ?? this.validationResults,
      networkGraph: networkGraph ?? this.networkGraph,
      simulationData: simulationData ?? this.simulationData,
    );
  }
}

final pipelineProvider =
    StateNotifierProvider<PipelineNotifier, PipelineState>((ref) {
  return PipelineNotifier(ref);
});

class PipelineNotifier extends StateNotifier<PipelineState> {
  final Ref ref;
  PipelineNotifier(this.ref) : super(const PipelineState());

  Future<void> runPipeline(String specText) async {
    state = state.copyWith(parse: PipelineStepStatus.running);
    try {
      final parseResults = await ref.read(apiClientProvider).parse(specText);
      state = state.copyWith(
        parse: PipelineStepStatus.success,
        parseResults: parseResults,
      );
    } catch (e) {
      state = state.copyWith(parse: PipelineStepStatus.error);
      return;
    }

    state = state.copyWith(validate: PipelineStepStatus.running);
    try {
      final validationResults =
          await ref.read(apiClientProvider).validate(specText);
      state = state.copyWith(
        validate: PipelineStepStatus.success,
        validationResults: validationResults,
      );
    } catch (e) {
      state = state.copyWith(validate: PipelineStepStatus.error);
    }
  }

  Future<void> generateAndSimulate(String specText,
      {double duration = 1.0}) async {
    state = state.copyWith(generate: PipelineStepStatus.running);
    try {
      final networkGraph =
          await ref.read(apiClientProvider).generate(specText);
      state = state.copyWith(
        generate: PipelineStepStatus.success,
        networkGraph: networkGraph,
      );
    } catch (e) {
      state = state.copyWith(generate: PipelineStepStatus.error);
      return;
    }

    state = state.copyWith(simulate: PipelineStepStatus.running);
    try {
      final simulationData = await ref
          .read(apiClientProvider)
          .simulate(specText, duration: duration);
      state = state.copyWith(
        simulate: PipelineStepStatus.success,
        simulationData: simulationData,
      );
    } catch (e) {
      state = state.copyWith(simulate: PipelineStepStatus.error);
    }
  }
}
```

### 5.2 CNL Editor (`widgets/editor/cnl_editor.dart`)

Code editor with custom CNL syntax highlighting:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'cnl_syntax.dart';

class CnlEditor extends StatefulWidget {
  final String initialText;
  final ValueChanged<String> onChanged;
  final List<EditorMarker>? markers;

  const CnlEditor({
    super.key,
    required this.initialText,
    required this.onChanged,
    this.markers,
  });

  @override
  State<CnlEditor> createState() => _CnlEditorState();
}

class _CnlEditorState extends State<CnlEditor> {
  late final CodeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(
      text: widget.initialText,
      language: cnlHighlightLanguage,
    );
    _controller.addListener(() {
      widget.onChanged(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CodeTheme(
      data: CodeThemeData(styles: cnlThemeStyles),
      child: CodeField(
        controller: _controller,
        minLines: 20,
        maxLines: null,
        textStyle: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 14,
        ),
      ),
    );
  }
}

class EditorMarker {
  final int line;
  final String message;
  final MarkerSeverity severity;

  const EditorMarker({
    required this.line,
    required this.message,
    this.severity = MarkerSeverity.error,
  });
}

enum MarkerSeverity { error, warning, info }
```

**CNL syntax definition (`widgets/editor/cnl_syntax.dart`):**

```dart
import 'package:highlight/highlight_core.dart';
import 'package:flutter/material.dart';

final cnlHighlightLanguage = Mode(
  refs: {},
  contains: [
    Mode(className: 'comment', begin: '#', end: r'$'),
    Mode(
      className: 'keyword',
      begin: r'\b(MUST NOT|MUST|ONLY IF|DURING|WITH|IF)\b',
    ),
    Mode(
      className: 'type',
      begin: r'\b(sensory neuron|motor neuron|interneuron|sensory population|motor population)\b',
    ),
    Mode(
      className: 'built_in',
      begin: r'\b(fire|emit a spike|decay|have|strengthen|weaken|be inhibitory|encode)\b',
    ),
    Mode(className: 'number', begin: r'\b\d+(\.\d+)?\b'),
    Mode(className: 'symbol', begin: r'\b(seconds|ms|Hz|neurons)\b'),
    Mode(className: 'meta', begin: r'\b(The|A|the|a)\b'),
  ],
);

const cnlThemeStyles = {
  'keyword': TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold),
  'type': TextStyle(color: Color(0xFFDC2626)),
  'built_in': TextStyle(color: Color(0xFF2563EB)),
  'number': TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold),
  'symbol': TextStyle(color: Color(0xFF059669)),
  'comment': TextStyle(color: Color(0xFF9CA3AF), fontStyle: FontStyle.italic),
  'meta': TextStyle(color: Color(0xFF6B7280)),
};
```

### 5.3 Pipeline Bar (`widgets/pipeline/pipeline_bar.dart`)

Horizontal status bar showing pipeline steps:

```dart
import 'package:flutter/material.dart';

class PipelineBar extends StatelessWidget {
  final List<PipelineStep> steps;

  const PipelineBar({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _PipelineStepBadge(step: steps[i]),
            if (i < steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 16),
              ),
          ],
        ],
      ),
    );
  }
}

class PipelineStep {
  final String name;
  final PipelineStepStatus status;
  final String summary;
  final VoidCallback? onTap;

  const PipelineStep({
    required this.name,
    required this.status,
    this.summary = '',
    this.onTap,
  });
}

enum PipelineStepStatus { idle, running, success, error }
```

### 5.4 Network Graph (`widgets/network/network_graph.dart`)

Interactive graph using `CustomPainter` with gesture detection:

```dart
import 'package:flutter/material.dart';
import '../../models/network_graph.dart';

class NetworkGraphView extends StatefulWidget {
  final NetworkGraph graph;
  final ValueChanged<NetworkNode>? onNodeTap;

  const NetworkGraphView({
    super.key,
    required this.graph,
    this.onNodeTap,
  });

  @override
  State<NetworkGraphView> createState() => _NetworkGraphViewState();
}

class _NetworkGraphViewState extends State<NetworkGraphView> {
  final TransformationController _transformController =
      TransformationController();

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _transformController,
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.5,
      maxScale: 3.0,
      child: CustomPaint(
        painter: _NetworkPainter(graph: widget.graph),
        child: Stack(
          children: widget.graph.nodes.map((node) {
            final pos = node.position ?? Offset.zero;
            return Positioned(
              left: pos.dx - 40,
              top: pos.dy - 25,
              child: GestureDetector(
                onTap: () => widget.onNodeTap?.call(node),
                child: _NodeWidget(node: node),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NodeWidget extends StatelessWidget {
  final NetworkNode node;
  const _NodeWidget({required this.node});

  @override
  Widget build(BuildContext context) {
    final isEnsemble = node.type == 'ensemble';
    return Container(
      width: 80,
      height: 50,
      decoration: BoxDecoration(
        color: isEnsemble ? Colors.blue[100] : Colors.amber[100],
        borderRadius: BorderRadius.circular(isEnsemble ? 25 : 8),
        border: Border.all(
          color: isEnsemble ? Colors.blue : Colors.amber,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          node.label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _NetworkPainter extends CustomPainter {
  final NetworkGraph graph;
  _NetworkPainter({required this.graph});

  @override
  void paint(Canvas canvas, Size size) {
    // Index nodes by ID for O(1) lookup per edge
    final nodeMap = {for (final n in graph.nodes) n.id: n};

    for (final edge in graph.edges) {
      final sourceNode = nodeMap[edge.source];
      final targetNode = nodeMap[edge.target];
      if (sourceNode == null || targetNode == null) continue;

      final isInhibitory = (edge.params['transform'] ?? 1.0) < 0;
      final weight = (edge.params['transform'] ?? 1.0).abs();

      final paint = Paint()
        ..color = isInhibitory ? Colors.red : Colors.blue
        ..strokeWidth = (weight * 2).clamp(1.0, 6.0)
        ..style = PaintingStyle.stroke;

      final source = sourceNode.position ?? Offset.zero;
      final target = targetNode.position ?? Offset.zero;
      canvas.drawLine(source, target, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) =>
      graph != oldDelegate.graph;
}
```

### 5.5 Spike Raster Plot (`widgets/simulation/spike_raster.dart`)

fl_chart scatter plot:

```dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/simulation_data.dart';

class SpikeRaster extends StatelessWidget {
  final SpikeRasterData data;
  final String title;

  const SpikeRaster({
    super.key,
    required this.data,
    this.title = 'Spike Raster',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        SizedBox(
          height: 250,
          child: ScatterChart(
            ScatterChartData(
              scatterSpots: List.generate(
                data.times.length,
                (i) => ScatterSpot(
                  data.times[i],
                  data.neuronIndices[i].toDouble(),
                  dotPainter: FlDotCirclePainter(
                    radius: 1.5,
                    color: const Color(0xFF1E40AF),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text('Time (s)'),
                  sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: const Text('Neuron Index'),
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true),
            ),
          ),
        ),
      ],
    );
  }
}
```

### 5.6 Parameter Explorer (`widgets/parameters/parameter_explorer.dart`)

Extracts numeric parameters from the spec and renders sliders:

```dart
import 'package:flutter/material.dart';
import '../../utils/parameter_extractor.dart';

class ParameterExplorer extends StatelessWidget {
  final String specText;
  final ValueChanged<ParameterUpdate> onUpdate;

  const ParameterExplorer({
    super.key,
    required this.specText,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final parameters = extractParameters(specText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Parameters',
              style: Theme.of(context).textTheme.titleSmall),
        ),
        ...parameters.map((param) => _ParameterSlider(
              parameter: param,
              onChanged: (newValue) => onUpdate(
                ParameterUpdate(
                  name: param.name,
                  lineNumber: param.lineNumber,
                  oldValue: param.value,
                  newValue: newValue,
                ),
              ),
            )),
      ],
    );
  }
}

class _ParameterSlider extends StatelessWidget {
  final ExtractedParameter parameter;
  final ValueChanged<double> onChanged;

  const _ParameterSlider({
    required this.parameter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(parameter.name, style: const TextStyle(fontSize: 12)),
              Text(
                '${parameter.value.toStringAsFixed(3)} ${parameter.unit}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
          Slider(
            value: parameter.value,
            min: parameter.min,
            max: parameter.max,
            divisions:
                ((parameter.max - parameter.min) / parameter.step).round(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class ParameterUpdate {
  final String name;
  final int lineNumber;
  final double oldValue;
  final double newValue;

  const ParameterUpdate({
    required this.name,
    required this.lineNumber,
    required this.oldValue,
    required this.newValue,
  });
}
```

**Parameter extraction logic (`utils/parameter_extractor.dart`):**

```dart
class ExtractedParameter {
  final String name;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final int lineNumber;

  const ExtractedParameter({
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.lineNumber,
  });
}

final _paramPatterns = <({RegExp pattern, String name, String unit, double min, double max})>[
  (pattern: RegExp(r'membrane potential exceeds ([\d.]+)'), name: 'Threshold', unit: 'V', min: 0, max: 5),
  (pattern: RegExp(r'refractory period of ([\d.]+) seconds'), name: 'Refractory Period', unit: 's', min: 0.0001, max: 0.05),
  (pattern: RegExp(r'time constant of ([\d.]+) seconds'), name: 'Time Constant', unit: 's', min: 0.001, max: 0.1),
  (pattern: RegExp(r'synaptic weight of ([\d.]+)'), name: 'Synaptic Weight', unit: '', min: 0, max: 10),
  (pattern: RegExp(r'transmission delay of ([\d.]+)ms'), name: 'Axonal Delay', unit: 'ms', min: 0, max: 150),
  (pattern: RegExp(r'spike by less than ([\d.]+)ms'), name: 'STDP Window', unit: 'ms', min: 1, max: 100),
  (pattern: RegExp(r'using (\d+) neurons'), name: 'Population Size', unit: 'neurons', min: 1, max: 1000),
];

List<ExtractedParameter> extractParameters(String specText) {
  final parameters = <ExtractedParameter>[];
  final lines = specText.split('\n');

  for (int i = 0; i < lines.length; i++) {
    for (final entry in _paramPatterns) {
      final match = entry.pattern.firstMatch(lines[i]);
      if (match != null) {
        final value = double.parse(match.group(1)!);
        parameters.add(ExtractedParameter(
          name: '${entry.name} (line ${i + 1})',
          value: value,
          min: entry.min,
          max: entry.max,
          step: entry.max > 10 ? 1 : 0.001,
          unit: entry.unit,
          lineNumber: i + 1,
        ));
      }
    }
  }

  return parameters;
}
```

---

## 6. Dart Models (`models/`)

### 6.1 Parse Models

```dart
// models/parse_result.dart
class ParseResult {
  final int line;
  final String raw;
  final ParsedSpec? parsed;
  final bool valid;
  final String? error;

  const ParseResult({
    required this.line,
    required this.raw,
    this.parsed,
    required this.valid,
    this.error,
  });

  factory ParseResult.fromJson(Map<String, dynamic> json) {
    return ParseResult(
      line: json['line'] as int,
      raw: json['raw'] as String,
      parsed: json['parsed'] != null
          ? ParsedSpec.fromJson(json['parsed'] as Map<String, dynamic>)
          : null,
      valid: json['valid'] as bool,
      error: json['error'] as String?,
    );
  }
}

class ParsedSpec {
  final String concept;
  final String subject;
  final String action;
  final String verb;
  final bool negated;
  final String? condition;

  const ParsedSpec({
    required this.concept,
    required this.subject,
    required this.action,
    required this.verb,
    required this.negated,
    this.condition,
  });

  factory ParsedSpec.fromJson(Map<String, dynamic> json) {
    return ParsedSpec(
      concept: json['concept'] as String,
      subject: json['subject'] as String,
      action: json['action'] as String,
      verb: json['verb'] as String,
      negated: json['negated'] as bool,
      condition: json['condition'] as String?,
    );
  }
}
```

### 6.2 Validation Models

```dart
// models/validation_result.dart
class ValidationResult {
  final Layer1Result layer1;
  final Layer2Result layer2;
  final bool overall;

  const ValidationResult({
    required this.layer1,
    required this.layer2,
    required this.overall,
  });

  factory ValidationResult.fromJson(Map<String, dynamic> json) {
    return ValidationResult(
      layer1: Layer1Result.fromJson(json['layer1'] as Map<String, dynamic>),
      layer2: Layer2Result.fromJson(json['layer2'] as Map<String, dynamic>),
      overall: json['overall'] as bool,
    );
  }
}

class Layer1Result {
  final bool overall;
  final List<InvariantResult> passed;
  final List<InvariantResult> failed;

  const Layer1Result({
    required this.overall,
    required this.passed,
    required this.failed,
  });

  factory Layer1Result.fromJson(Map<String, dynamic> json) {
    return Layer1Result(
      overall: json['overall'] as bool,
      passed: (json['passed'] as List)
          .map((e) => InvariantResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      failed: (json['failed'] as List)
          .map((e) => InvariantResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Layer2Result {
  final bool overall;
  final List<String> checksPassed;
  final List<String> checksFailed;
  final List<String> neuronsFound;

  const Layer2Result({
    required this.overall,
    required this.checksPassed,
    required this.checksFailed,
    required this.neuronsFound,
  });

  factory Layer2Result.fromJson(Map<String, dynamic> json) {
    return Layer2Result(
      overall: json['overall'] as bool,
      checksPassed: List<String>.from(json['checks_passed'] as List),
      checksFailed: List<String>.from(json['checks_failed'] as List),
      neuronsFound: List<String>.from(json['neurons_found'] as List),
    );
  }
}

class InvariantResult {
  final String name;
  final String description;
  final bool result;

  const InvariantResult({
    required this.name,
    required this.description,
    required this.result,
  });

  factory InvariantResult.fromJson(Map<String, dynamic> json) {
    return InvariantResult(
      name: json['name'] as String,
      description: json['description'] as String,
      result: json['result'] as bool,
    );
  }
}
```

### 6.3 Network Models

```dart
// models/network_graph.dart
import 'dart:ui';

class NetworkGraph {
  final List<NetworkNode> nodes;
  final List<NetworkEdge> edges;

  const NetworkGraph({required this.nodes, required this.edges});

  factory NetworkGraph.fromJson(Map<String, dynamic> json) {
    return NetworkGraph(
      nodes: (json['nodes'] as List)
          .map((e) => NetworkNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List)
          .map((e) => NetworkEdge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NetworkNode {
  final String id;
  final String type;
  final String label;
  final Map<String, dynamic> params;
  final Offset? position;

  const NetworkNode({
    required this.id,
    required this.type,
    required this.label,
    required this.params,
    this.position,
  });

  factory NetworkNode.fromJson(Map<String, dynamic> json) {
    return NetworkNode(
      id: json['id'] as String,
      type: json['type'] as String,
      label: json['label'] as String,
      params: json['params'] as Map<String, dynamic>? ?? {},
      position: json['position'] != null
          ? Offset(
              (json['position']['x'] as num).toDouble(),
              (json['position']['y'] as num).toDouble(),
            )
          : null,
    );
  }
}

class NetworkEdge {
  final String id;
  final String source;
  final String target;
  final Map<String, dynamic> params;

  const NetworkEdge({
    required this.id,
    required this.source,
    required this.target,
    required this.params,
  });

  factory NetworkEdge.fromJson(Map<String, dynamic> json) {
    return NetworkEdge(
      id: json['id'] as String,
      source: json['source'] as String,
      target: json['target'] as String,
      params: json['params'] as Map<String, dynamic>? ?? {},
    );
  }
}
```

### 6.4 Simulation Models

```dart
// models/simulation_data.dart
class SimulationData {
  final double duration;
  final double dt;
  final Map<String, ProbeData> probes;
  final SimulationSummary summary;
  final double wallTimeSeconds;

  const SimulationData({
    required this.duration,
    required this.dt,
    required this.probes,
    required this.summary,
    required this.wallTimeSeconds,
  });

  factory SimulationData.fromJson(Map<String, dynamic> json) {
    final probesJson = json['probes'] as Map<String, dynamic>;
    final probes = probesJson.map((key, value) {
      final probeJson = value as Map<String, dynamic>;
      if (probeJson['type'] == 'spike_raster') {
        return MapEntry(key, SpikeRasterData.fromJson(probeJson));
      } else {
        return MapEntry(key, ContinuousData.fromJson(probeJson));
      }
    });

    return SimulationData(
      duration: (json['duration'] as num).toDouble(),
      dt: (json['dt'] as num).toDouble(),
      probes: probes,
      summary: SimulationSummary.fromJson(
          json['summary'] as Map<String, dynamic>),
      wallTimeSeconds: (json['wall_time_seconds'] as num).toDouble(),
    );
  }
}

abstract class ProbeData {
  String get type;
}

class SpikeRasterData implements ProbeData {
  @override
  final String type = 'spike_raster';
  final List<double> times;
  final List<int> neuronIndices;

  const SpikeRasterData({required this.times, required this.neuronIndices});

  factory SpikeRasterData.fromJson(Map<String, dynamic> json) {
    return SpikeRasterData(
      times: (json['times'] as List).map((e) => (e as num).toDouble()).toList(),
      neuronIndices:
          (json['neuron_indices'] as List).map((e) => e as int).toList(),
    );
  }
}

class ContinuousData implements ProbeData {
  @override
  final String type = 'continuous';
  final List<double> times;
  final List<double> values;

  const ContinuousData({required this.times, required this.values});

  factory ContinuousData.fromJson(Map<String, dynamic> json) {
    return ContinuousData(
      times: (json['times'] as List).map((e) => (e as num).toDouble()).toList(),
      values:
          (json['values'] as List).map((e) => (e as num).toDouble()).toList(),
    );
  }
}

class SimulationSummary {
  final int sensorySpikeCount;
  final int motorSpikeCount;
  final double sensoryMeanRate;
  final double motorMeanRate;
  final double? firstOutputSpike;
  final double? inputToOutputLatency;

  const SimulationSummary({
    required this.sensorySpikeCount,
    required this.motorSpikeCount,
    required this.sensoryMeanRate,
    required this.motorMeanRate,
    this.firstOutputSpike,
    this.inputToOutputLatency,
  });

  factory SimulationSummary.fromJson(Map<String, dynamic> json) {
    return SimulationSummary(
      sensorySpikeCount: json['sensory_spike_count'] as int,
      motorSpikeCount: json['motor_spike_count'] as int,
      sensoryMeanRate: (json['sensory_mean_rate'] as num).toDouble(),
      motorMeanRate: (json['motor_mean_rate'] as num).toDouble(),
      firstOutputSpike: (json['first_output_spike'] as num?)?.toDouble(),
      inputToOutputLatency:
          (json['input_to_output_latency'] as num?)?.toDouble(),
    );
  }
}
```

### 6.5 Template Model

```dart
// models/template.dart
class CnlTemplate {
  final String id;
  final String name;
  final String description;
  final List<String> tags;
  final String difficulty;
  final String spec;

  const CnlTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.tags,
    required this.difficulty,
    required this.spec,
  });

  factory CnlTemplate.fromJson(Map<String, dynamic> json) {
    return CnlTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      tags: List<String>.from(json['tags'] as List),
      difficulty: json['difficulty'] as String,
      spec: json['spec'] as String,
    );
  }
}
```

---

## 7. Data Flow

### 7.1 Edit then Parse then Validate (Real-Time)

```
User types in editor
    then debounce (500ms)
    then POST /api/parse with spec text
    then update parseResults in PipelineNotifier
    then if parseResults has no errors:
        then POST /api/validate with spec text + params
        then update validationResults in PipelineNotifier
    then update pipeline status badges
    then update editor markers (inline validation)
```

### 7.2 Generate then Simulate (On Demand)

```
User taps "Run Simulation" (or auto-triggers after successful validation)
    then POST /api/generate with spec text + params
    then update networkGraph in PipelineNotifier then render graph widget
    then POST /api/simulate with spec text + params + duration
        (or WebSocket /api/simulate/stream for progressive rendering)
    then update simulationData in PipelineNotifier then render fl_chart plots
    then update pipeline status badges
```

### 7.3 Parameter Change then Re-Run

```
User adjusts slider in Parameter Explorer
    then compute new value
    then update spec text in editor (replace numeric value at the correct line/position)
    then trigger Edit then Parse then Validate flow (debounced)
    then if auto-simulate is on: trigger Generate then Simulate flow
```

---

## 8. UI Layout

### 8.1 Desktop Layout (1024px and above)

```
+----------------------------------------------------------------------+
|  Header: neurocnl Studio    [Templates] [Export]  [Settings]          |
+----------------------------------------------------------------------+
|  Pipeline: [Parse ok] > [Validate ok] > [Generate ok] > [Sim ok]     |
+------------------------+---------------------------------------------+
|                        |                                              |
|   CNL Editor           |   Results Panel (tabbed)                     |
|   (code_editor, ~50%)  |                                              |
|                        |   [Parsed Specs] [Network] [Simulation]      |
|   +------------------+ |                                              |
|   | # Reflex arc     | |   Currently showing: Network Graph           |
|   |                  | |   +-------------------------------------+    |
|   | The sensory ne...| |   |  (input) --> [sensory] --> [motor]  |    |
|   | The sensory ne...| |   |          w=1.0, t=0.005s            |    |
|   | The sensory ne...| |   +-------------------------------------+    |
|   | The connection...| |                                              |
|   |                  | |                                              |
|   +------------------+ |                                              |
|                        |                                              |
|   Parameter Explorer   |                                              |
|   +------------------+ |                                              |
|   | Threshold  [--o] | |                                              |
|   | Refract.   [-o-] | |                                              |
|   | Tau        [-o-] | |                                              |
|   | Weight     [--o] | |                                              |
|   +------------------+ |                                              |
|                        |                                              |
+------------------------+---------------------------------------------+
|  Status: Simulation completed in 2.34s  |  7 specs parsed  |  ok    |
+----------------------------------------------------------------------+
```

### 8.2 Responsive Behaviour

Flutter's `LayoutBuilder` and `MediaQuery` handle responsive breakpoints:

| Breakpoint | Layout |
|---|---|
| 1024px and above | Side-by-side: editor (left) + results (right) via `Row` |
| 768 to 1023px | Stacked: editor (top) + results (bottom), collapsible via `Column` |
| Below 768px | Single column: editor fills screen, results accessible via bottom sheet or `NavigationBar` tabs |

---

## 9. Backend Pydantic Schemas

### 9.1 Common Types (`schemas/common.py`)

```python
from pydantic import BaseModel, Field


class NeuronParams(BaseModel):
    threshold: float = Field(1.0, description="Membrane potential threshold for firing")
    resting_potential: float = Field(0.0, description="Resting membrane potential")
    refractory_period: float = Field(0.002, description="Refractory period in seconds")
    tau: float = Field(0.02, description="Membrane time constant in seconds")
    reset_potential: float = Field(0.0, description="Reset potential after spike")
    current_voltage: float = Field(0.5, description="Current membrane voltage")
```

### 9.2 Parse Schemas (`schemas/parse.py`)

```python
from pydantic import BaseModel


class ParseRequest(BaseModel):
    spec: str


class ParsedSentence(BaseModel):
    line: int
    raw: str
    parsed: dict | None
    valid: bool
    error: str | None


class ParseResponse(BaseModel):
    sentences: list[ParsedSentence]
    total: int
    errors: int
```

### 9.3 Validate Schemas (`schemas/validate.py`)

```python
from pydantic import BaseModel
from .common import NeuronParams


class ValidateRequest(BaseModel):
    spec: str
    params: NeuronParams
    backend: str = "nengo"


class InvariantResult(BaseModel):
    name: str
    description: str
    result: bool


class Layer1Result(BaseModel):
    overall: bool
    passed: list[InvariantResult]
    failed: list[InvariantResult]


class Layer2Result(BaseModel):
    overall: bool
    checks_passed: list[str]
    checks_failed: list[str]
    neurons_found: list[str]


class ValidateResponse(BaseModel):
    layer1: Layer1Result
    layer2: Layer2Result
    overall: bool
```

### 9.4 Simulate Schemas (`schemas/simulate.py`)

```python
from pydantic import BaseModel
from .common import NeuronParams


class SimulateRequest(BaseModel):
    spec: str
    params: NeuronParams
    duration: float = 1.0
    dt: float = 0.001
    backend: str = "nengo"


class ProbeData(BaseModel):
    type: str
    times: list[float]
    values: list[float] | None = None
    neuron_indices: list[int] | None = None


class SimulationSummary(BaseModel):
    sensory_spike_count: int
    motor_spike_count: int
    sensory_mean_rate: float
    motor_mean_rate: float
    first_output_spike: float | None
    input_to_output_latency: float | None


class SimulateResponse(BaseModel):
    duration: float
    dt: float
    probes: dict[str, ProbeData]
    summary: SimulationSummary
    wall_time_seconds: float
```

---

## 10. Docker Configuration

### 10.1 Backend Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY neurocnl/ /app/neurocnl/
COPY pyproject.toml /app/
RUN pip install --no-cache-dir -e .

COPY backend/app/ /app/app/
COPY backend/app/templates/ /app/app/templates/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 10.2 Frontend Dockerfile

```dockerfile
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY frontend/pubspec.yaml frontend/pubspec.lock ./
RUN flutter pub get

COPY frontend/ .
RUN flutter build web --release --web-renderer canvaskit

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
```

### 10.3 Nginx Configuration (`frontend/nginx.conf`)

```nginx
server {
    listen 80;
    server_name localhost;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://backend:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /api/simulate/stream {
        proxy_pass http://backend:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### 10.4 Docker Compose (`docker-compose.yml`)

```yaml
services:
  backend:
    build:
      context: .
      dockerfile: backend/Dockerfile
    ports:
      - "8000:8000"
    environment:
      - MAX_SIMULATION_DURATION=10
      - CORS_ORIGINS=http://localhost:3000

  frontend:
    build:
      context: .
      dockerfile: frontend/Dockerfile
    ports:
      - "3000:80"
    depends_on:
      - backend
```

### 10.5 Development Docker Compose (`docker-compose.dev.yml`)

```yaml
services:
  backend:
    build:
      context: .
      dockerfile: backend/Dockerfile
    ports:
      - "8000:8000"
    volumes:
      - ./neurocnl:/app/neurocnl
      - ./backend/app:/app/app
    environment:
      - MAX_SIMULATION_DURATION=10
      - CORS_ORIGINS=*
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 11. CI/CD Pipeline

See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) for full deployment details. Summary of the pipeline:

### 11.1 CI Workflow (`.github/workflows/ci.yml`)

Runs on every push and pull request:

```yaml
name: CI

on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]

jobs:
  backend-test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install -r backend/requirements.txt
      - run: pip install -e .
      - run: python -m pytest backend/tests/ -v
      - run: python -m pytest neurocnl/ -v -p no:nengo  # Disable nengo pytest plugin to prevent test collection conflicts

  frontend-test:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - working-directory: frontend
        run: flutter pub get
      - working-directory: frontend
        run: flutter analyze
      - working-directory: frontend
        run: flutter test

  docker-build:
    runs-on: self-hosted
    needs: [backend-test, frontend-test]
    steps:
      - uses: actions/checkout@v4
      - run: docker compose build
```

### 11.2 Deploy Workflow (`.github/workflows/deploy.yml`)

Runs on merge to `main`:

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy-backend:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      # See DEPLOYMENT_GUIDE.md for platform-specific deploy steps

  deploy-frontend:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - working-directory: frontend
        run: flutter build web --release --web-renderer canvaskit
      # Deploy build/web/ to Firebase Hosting, Vercel, or Cloudflare Pages
```

---

## 12. Testing Strategy

### 12.1 Backend Tests

| Test | What it validates |
|---|---|
| `test_parse_router.py` | Correct parse output for all 8 concept types, error handling for invalid sentences |
| `test_validate_router.py` | Layer 1 + Layer 2 validation results, Loihi backend constraints |
| `test_generate_router.py` | Network serialisation matches expected node/edge structure |
| `test_simulate_router.py` | Simulation returns valid probe data, summary stats are computed correctly |
| `test_neurocnl_bridge.py` | Bridge correctly wraps neurocnl library, handles errors gracefully |

**Test framework:** pytest with `httpx.AsyncClient` for FastAPI testing.

```python
import pytest
from httpx import AsyncClient
from app.main import app


@pytest.mark.anyio
async def test_parse_valid_sentence():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post(
            "/api/parse",
            json={"spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"},
        )
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 1
    assert data["errors"] == 0
    assert data["sentences"][0]["parsed"]["concept"] == "threshold_firing"


@pytest.mark.anyio
async def test_parse_invalid_sentence():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post(
            "/api/parse", json={"spec": "This is not a valid CNL sentence"}
        )
    assert response.status_code == 200
    data = response.json()
    assert data["errors"] == 1
    assert data["sentences"][0]["valid"] is False
```

### 12.2 Frontend Tests (Flutter)

| Test | What it validates |
|---|---|
| `cnl_editor_test.dart` | Editor renders, accepts text input, fires onChanged callback |
| `pipeline_bar_test.dart` | Status badges update correctly for each pipeline state |
| `network_graph_test.dart` | Graph renders correct nodes and edges from mock data |
| `spike_raster_test.dart` | Plot renders with correct data points |
| `parameter_explorer_test.dart` | Sliders extract correct parameters from spec, onChanged updates work |
| `pipeline_provider_test.dart` | Provider state transitions work correctly |
| `parameter_extractor_test.dart` | Regex extraction finds all parameters with correct values |

**Test framework:** Flutter test + `mocktail` for mocking API calls.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:neurocnl_studio/utils/parameter_extractor.dart';

void main() {
  test('extractParameters finds threshold', () {
    const spec =
        'The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.5';
    final params = extractParameters(spec);
    expect(params.length, 1);
    expect(params[0].name, contains('Threshold'));
    expect(params[0].value, 1.5);
    expect(params[0].unit, 'V');
  });

  test('extractParameters finds multiple parameters', () {
    const spec =
        'The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n'
        'The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n'
        'The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds';
    final params = extractParameters(spec);
    expect(params.length, 3);
  });
}
```

---

## 13. Performance Considerations

| Concern | Approach |
|---|---|
| Nengo simulation can take 2-10 seconds | Run simulation in a background task. Show progress bar. Cache results for unchanged specs. |
| Large probe data (1M+ data points) | Downsample probe data on the backend before sending to frontend. Send at most 10K points per probe. |
| Frequent spec edits triggering many API calls | Debounce editor changes by 500ms. Only call /validate if /parse succeeds. Only call /simulate on explicit user action or toggle. |
| Flutter CanvasKit initial load (~2MB WASM) | Acceptable for a desktop-oriented tool. Show a loading spinner during WASM initialisation. Use `--web-renderer html` during development for faster iteration. |
| CustomPainter graph with many nodes | Unlikely to be an issue: typical networks have fewer than 20 populations. |

---

## 14. Security Considerations

| Concern | Mitigation |
|---|---|
| Arbitrary code execution via spec injection | The CNL parser uses regex pattern matching only. No eval(), no code generation from user input. The backend never executes user-provided strings as code. |
| Denial of service via long simulations | Backend enforces a maximum simulation duration (e.g., 10 seconds). Configurable via environment variable `MAX_SIMULATION_DURATION`. |
| Cross-origin requests | CORS configured to allow only the frontend origin in production. Configurable via `CORS_ORIGINS` environment variable. |
| Dependency vulnerabilities | Docker images use pinned versions. `pip audit` and `flutter pub outdated` run in CI. |

---

## 15. Accessibility

| Feature | Implementation |
|---|---|
| Keyboard navigation | All interactive elements use `Focus` and `FocusTraversalGroup`. Tab order follows visual layout. |
| Screen reader support | `Semantics` widgets on all buttons, sliders, and status badges. `ExcludeSemantics` on decorative elements. |
| Colour contrast | All text meets WCAG AA contrast ratios. Material 3 `ColorScheme.fromSeed` ensures contrast compliance. |
| Reduced motion | Animations check `MediaQuery.disableAnimationsOf(context)` and skip when true. |

---

## 16. Flutter Dependencies (`pubspec.yaml`)

```yaml
name: neurocnl_studio
description: Visual interface for the neurocnl neuromorphic specification library
publish_to: none

environment:
  sdk: ">=3.2.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.0
  http: ^1.2.0
  web_socket_channel: ^3.0.0
  flutter_code_editor: ^0.3.0
  highlight: ^0.7.0
  fl_chart: ^0.68.0
  url_launcher: ^6.2.0
  file_saver: ^0.2.0
  go_router: ^14.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  mocktail: ^1.0.0
```

---

## 17. Future Extensions

| Extension | How the architecture supports it |
|---|---|
| **Desktop/mobile builds** | Flutter compiles to macOS, Windows, Linux, iOS, and Android from the same codebase. The API client and Riverpod providers work unchanged across platforms. |
| **Collaborative editing** | The spec state is centralised in a Riverpod provider. Adding CRDT-based collaboration (e.g., via a WebSocket relay) would require wrapping the spec provider with a sync layer. |
| **Cloud deployment** | The Docker Compose setup can be deployed to any VPS or cloud provider. See [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md). |
| **Hardware integration** | Add a `/api/deploy` endpoint that calls a `teensy_exporter.py` or `loihi_exporter.py` module, extending the pipeline beyond simulation. |
| **AI-assisted spec writing** | Add an LLM-powered assistant that suggests CNL sentences from natural language descriptions. Integrate as a sidebar chat widget that calls an LLM API. |
| **Version history** | Store spec versions in `SharedPreferences` (Flutter) or a backend database. Add undo/redo and version comparison. |
