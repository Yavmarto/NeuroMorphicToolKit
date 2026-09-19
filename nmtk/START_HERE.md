# neurocnl Codebase Exploration - START HERE

## 📄 Four Reference Documents Created

All in `$HOME/Neuro-space/`:

### 1. **neurocnl_complete_reference.md** - FULL TECHNICAL DETAILS
- Complete specification of all 13 concepts with exact regex patterns
- Every function signature with full parameters
- All 18 Layer 1 biological invariants
- Code examples for every major function
- **Read this if**: You need exact patterns, complete specs, or all details

### 2. **QUICK_START_GUIDE.md** - IMPLEMENTATION WALKTHROUGH
- 5-stage pipeline explained with code examples
- Step-by-step: Parse → Validate → Generate → Simulate → Export
- All absolute file paths
- Implementation checklist
- **Read this if**: You're building a demo or want practical guidance

### 3. **NEUROCNL_EXPLORATION_SUMMARY.txt** - HIGH-LEVEL OVERVIEW
- Architecture summary
- Quick reference for 13 concepts
- Parser pattern examples
- Key takeaways
- **Read this if**: You need a quick overview or 30-second explanation

### 4. **README_EXPLORATION_RESULTS.md** - INDEX & GUIDE
- Which document to read for what
- Quick reference tables
- File locations
- 10-line example implementation
- **Read this if**: You need to find something or understand what was explored

---

## 🚀 Quick Start (Choose Your Path)

### Path A: I want to implement something NOW
1. Read `QUICK_START_GUIDE.md` (15 minutes)
2. Copy the 10-line example from `README_EXPLORATION_RESULTS.md`
3. Run it!

### Path B: I need to understand the architecture
1. Read `NEUROCNL_EXPLORATION_SUMMARY.txt` (10 minutes)
2. Review `/neurocnl/demos/gripper_reflex/README.md`
3. Look at `/neurocnl/examples/04_full_pipeline.py`

### Path C: I need all the technical details
1. Read `neurocnl_complete_reference.md` (30 minutes)
2. Keep it open as reference while coding
3. Use grep/search by line number to find specific patterns

---

## 📚 What You Have

A complete **5-stage pipeline** for translating English specifications into verified spiking neural networks:

```
CNL Spec (English) → PARSE → VALIDATE → GENERATE → SIMULATE → ASSERT
                     ↓         ↓          ↓          ↓          ↓
                 4 lines    18 checks   Nengo SNN   1 second   Pytest
```

**All 13 Concepts Documented**:
1-4: Core (threshold, refractory, decay, weight)
5-9: Extended (delay, STDP, inhibition, population, topology)
10-13: Advanced (lateral inhibition, homeostasis, neuromodulation, range)

**All 18 Invariants Explained**: Biological constraints for LIF neurons

**Multi-Format Export**: C (microcontroller), NeuroML, Loihi, Lava, SpiNNaker

---

## 💡 The Core Idea

Write neuromorphic specs in **plain English + math**:

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
```

Then **one line of code**:

```python
from neurocnl import run_pipeline
result = run_pipeline(spec_text)
```

Gets you:
- ✓ Parsed specification
- ✓ Validation against 18 biological invariants
- ✓ Generated Nengo spiking neural network
- ✓ Simulated for 1.0 second
- ✓ Auto-generated test assertions
- ✓ Ready to export to C, NeuroML, Loihi, Lava, or SpiNNaker

---

## 📍 File Locations (All Absolute Paths)

### Core Module
```
$HOME/Neuro-space/neurocnl/neurocnl/
├── __init__.py              - Public API exports
├── pipeline.py              - run_pipeline() orchestrator
├── cnl/cnl_parser.py        - 13 concept regex patterns
├── layers/layer1_validator.py - Biological invariant checking
├── generation/nengo_generator.py - SNN generation
├── export/c_header_exporter.py - Microcontroller export
└── spike_encoding.py        - Analog→spike conversion
```

### Examples
```
$HOME/Neuro-space/neurocnl/examples/
├── 01_parse_spec.py
├── 02_validate_spec.py
├── 03_generate_network.py
├── 04_full_pipeline.py      ← START HERE
└── 05_demo_simulations.py
```

### Demo
```
$HOME/Neuro-space/neurocnl/demos/gripper_reflex/
├── gripper_reflex.cnl       - 4-line CNL spec
└── README.md                - Hardware wiring + architecture
```

---

## ⚡ 60-Second Example

```python
from neurocnl import run_pipeline

spec = """
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
"""

result = run_pipeline(spec)

if result.overall_pass:
    print("✓ Specification validated and network generated!")
    print(f"  - Parsed specs: {len(result.parsed)}")
    print(f"  - Validation: {result.validation['overall']}")
    print(f"  - Network: {result.network}")
    print(f"  - Simulation: {result.simulation['wall_time_seconds']}s")
else:
    print("✗ Specification failed validation")
    print(f"  - Errors: {result.errors}")
```

That's it! The framework handles everything.

---

## 🎯 Next Steps

1. **Immediate**: Read `QUICK_START_GUIDE.md`
2. **Then**: Run `/neurocnl/examples/04_full_pipeline.py`
3. **Then**: Write your own CNL spec
4. **Then**: Call `neurocnl.run_pipeline(your_spec)`

Everything you need is in the 4 reference documents.

---

## 📚 Document Map

| Document | Read Time | Best For | When to Use |
|----------|-----------|----------|------------|
| QUICK_START_GUIDE.md | 15 min | Implementing | You're coding a demo |
| neurocnl_complete_reference.md | 30 min | Reference | You need exact specs |
| NEUROCNL_EXPLORATION_SUMMARY.txt | 10 min | Overview | You need a summary |
| README_EXPLORATION_RESULTS.md | 10 min | Navigation | You're looking for something |

---

**Last Updated**: 2024-03-15  
**Content**: Complete neurocnl codebase analysis (2,838 lines across 14 core files)  
**Coverage**: All 13 concepts, 18 invariants, all functions, all exporters  

**Ready to build?** → Start with `QUICK_START_GUIDE.md`
