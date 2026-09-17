# Roadmap — neurocnl

## Current State (v0.3.0)

The library implements a complete spec-driven pipeline for spiking neural networks:

- **CNL Parser** — Regex-based parser for 18 parser-recognized sentence families, spanning core reflex-arc concepts plus topology, adaptation, receptor dynamics, short-term plasticity, background noise, and spatial connectivity
- **Layer 1 Validator** — 16 biological invariants from NeuroML (including learning rate, learning rule validity)
- **Layer 2 Validator** — Cross-sentence consistency checks with orphan population detection
- **Nengo Generator** — Compiles the most mature CNL concepts into executable Nengo networks with dynamic multi-population graph building, BCM/Oja/PES learning rules, and additional approximate mappings for newer concepts
- **Assertion Generator** — Auto-generates pytest suites from specs (template + LLM modes) for the established CNL execution surface
- **Simulation Runner** — End-to-end pipeline with unified `run_pipeline()` entry point
- **Spike Encoding** — `rate_encode()`, `temporal_encode()`, `delta_encode()` for analog-to-spike conversion
- **Visualization** — Spike raster, membrane traces, network topology, weight evolution, HTML export (optional matplotlib)
- **Export** — 5 target formats: NeuroML, C header, NengoLoihi, Lava, SpiNNaker + unified dispatcher, with backend fidelity that still varies by target

305 tests passing. The architecture supports arbitrary multi-population networks with learning rules and full export pipeline.

---

## Completed Phases

### ✅ Phase 1 — Learning Rules in CNL
BCM, Oja, and PES learning rules with explicit CNL patterns, generator routing, invariants, and assertion templates. 17 tests.

### ✅ Phase 2 — Multi-Population Network Topology
Dynamic population graph building, arbitrary neuron names, orphan detection, backward-compatible aliases. 16 tests.

### ✅ Phase 3 — Real-Time Hardware Interface
C header exporter for Teensy, BrainFlow adapter stub for Ganglion. Full export via `neurocnl.export`.

### ✅ Phase 4 — Spike Encoding Utilities
`spike_encoding.py` with rate, temporal, and delta encoding. 15 tests.

### ✅ Phase 5 — Visualization
Matplotlib-based plots with HTML export. Optional dependency (`pip install neurocnl[viz]`). 14 tests.

### ✅ Phase 6 — Export Formats
NeuroML, NengoLoihi, C header, Lava, SpiNNaker + unified `export()`. 23 tests.

### ✅ Phase 7 — Extended CNL Grammar
13 concepts total: original 8 + lateral inhibition, homeostatic plasticity, neuromodulation, population coding range. 25 tests.

### ✅ Phase 8 — Parser Expansion Wave 2
Adaptive spiking, receptor dynamics, short-term plasticity, background noise, and spatial connectivity were added to the parser and generator surface, but these newer concepts still have mixed execution fidelity relative to the core reflex-arc pipeline.

---

## What's Next

### Phase 9 — BrainFlow Integration

Live biosignal acquisition from OpenBCI Ganglion/Cyton boards. Wraps BrainFlow SDK and outputs spike-encoded streams compatible with the Nengo input node.

**Deliverable:** A `brainflow_adapter.py` module with real-time streaming + spike encoding pipeline.

---

## Research Directions

These are longer-term explorations that could differentiate the project:

The roadmap uses these support terms consistently:

- `parser-recognized`: accepted by the CNL parser
- `faithful`: execution closely preserves intended semantics
- `approximate`: execution or export works with heuristics or backend-specific simplifications
- `unsupported`: the project cannot yet honestly claim runtime or backend support

1. **Spec Verification** — Formal proof that a CNL spec satisfies Layer 1 invariants for all possible inputs, not just tested ones. Tools: Z3 SMT solver, model checking.

2. **Spec Synthesis** — Given a desired behavior (e.g., "maintain grip on object"), automatically generate the CNL spec that produces it. This inverts the pipeline.

3. **Cross-Hardware Validation** — Run the same spec on Nengo (CPU), NengoLoihi (Loihi), and Teensy (embedded) and verify that all three produce equivalent behavior within tolerance.

4. **Biological Validation** — Compare network outputs against published electrophysiology data (e.g., reflex arc recordings from spinal cord studies) to validate that the spec produces biologically plausible behavior.

---

## Hardware Demo Ideas

See [`demos/README.md`](demos/README.md) for detailed hardware project ideas using the Teensy 4.1 and OpenBCI Ganglion, with CNL specs, wiring guides, and estimated costs.

## Portfolio Build Order

See [`PORTFOLIO_ROADMAP.md`](PORTFOLIO_ROADMAP.md) for a prioritized build order that interleaves library development and hardware demos, ordered by portfolio impact for neuromorphic computing roles in the Netherlands.
