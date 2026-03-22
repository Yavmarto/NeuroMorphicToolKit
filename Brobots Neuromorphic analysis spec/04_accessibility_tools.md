# Accessibility Tools
> Addresses the gap: no unified, welcoming starting point exists for newcomers to the field

---

## 1. Project Scaffolder

**Description**
Generate a working neuromorphic project skeleton in seconds — choose hardware target, framework, and task type.

**Target surfaces:** Desktop app + Python library / CLI

**Tags:** `templates` `scaffolding` `CLI`

### Spec
- Wizard: pick framework → hardware target → task type (classification, control, anomaly detection) → neuron model
- Generates: project folder, `requirements.txt`, annotated main script, and a README explaining each component
- Templates are versioned and community-contributed (pulled from GitHub); offline fallback to bundled defaults
- **CLI:** `neuro new --framework lava --target loihi2 --task kws`
- **Desktop:** visual step-by-step wizard with tooltips explaining each choice, aimed at newcomers

---

## 2. Software Simulator

**Description**
Run and test SNN models on a hardware-accurate software simulation — no physical chip required.

**Target surfaces:** Desktop app + Python library

**Tags:** `simulation` `hardware-free` `emulation`

### Spec
- Simulates the constraints and execution model of a chosen hardware target (core/neuron limits, connectivity rules)
- Reports estimated energy and latency based on hardware data sheets — clearly labelled as estimates, not measurements
- Flags model aspects that would fail or degrade on the chosen target before deployment
- Integrates with the Benchmark Runner so simulated results appear in the same comparison view as real hardware results
- **Python:** `sim = Simulator("loihi2"); sim.run(model, duration=1000)`

---

## 3. Interactive Docs Browser

**Description**
Unified, searchable documentation across all major frameworks — with runnable code examples in the sidebar.

**Target surfaces:** Desktop app

**Tags:** `docs` `search` `examples`

### Spec
- Aggregates and normalises official docs from PyNN, Lava, Nengo, Brian2, and NIR into a single searchable index
- Cross-framework search: searching "LIF neuron" returns the equivalent API in every framework side by side
- Every code example has a "run in simulator" button that opens it directly in the Software Simulator
- Offline-first: docs cached locally; auto-updates in background when a connection is available
- "Translate this snippet" button converts any shown example to the user's chosen target framework
