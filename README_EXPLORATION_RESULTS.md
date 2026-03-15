# NeuroControl Natural Language (neurocnl) - Complete Exploration Results

## What Was Explored

Complete codebase analysis of the neurocnl neuromorphic specification framework located at:
```
/Users/yoshimartodihardjo/Neuro-space/neurocnl/
```

## Documents Created

### 1. **neurocnl_complete_reference.md** (1011 lines, 34KB)
**Your primary technical reference**

Contents:
- Complete architecture overview
- Full directory structure (3 levels deep)
- All 13 concept definitions with complete regex patterns
- Core classes: `PipelineResult`, `ParsedSentence`
- All key functions with complete signatures:
  - `run_pipeline()` - Full pipeline orchestration
  - `parse_spec_text()` - Parse CNL lines
  - `parse()` - Single sentence parser
  - `validate_spec()` - Layer 1+2 validation
  - `default_params_from_specs()` - Parameter extraction
  - `validate()` - Layer 1 invariant checking
  - `validate_cross_sentence()` - Layer 2 consistency
  - `generate()` - Nengo network generation
  - `export()` - Multi-platform export dispatcher
  - `export_c_header()` - Microcontroller export
  - `rate_encode()`, `temporal_encode()`, `delta_encode()` - Spike encoding
- Layer 1 invariants (18 total) with full descriptions
- Loihi-specific constraints
- Complete gripper reflex demo specification
- File line counts and reference tables

**Use this when:** You need exact function signatures, full regex patterns, or complete specifications.

### 2. **QUICK_START_GUIDE.md** (359 lines, 13KB)
**Your implementation playbook**

Contents:
- What you have (module structure overview)
- The 13 concepts (summary table)
- Usage pattern (5 stages)
- Step-by-step implementation walkthrough:
  1. Parse CNL spec with `parse()`
  2. Validate with `validate()`
  3. Generate with `generate()`
  4. Simulate with `nengo.Simulator()`
  5. Export with `export()`
- PipelineResult class definition
- All key function signatures
- All 18 Layer 1 invariants
- Gripper reflex example with CNL spec
- Hardware wiring diagram
- All absolute file paths
- Critical regex patterns summary
- Implementation checklist

**Use this when:** You're implementing a demo or need a quick reference guide.

### 3. **NEUROCNL_EXPLORATION_SUMMARY.txt** (344 lines, 14KB)
**Your high-level overview**

Contents:
- Architecture summary (5-stage pipeline)
- The 13 concepts listed with descriptions
- Core module structure tree
- Critical functions overview
- Example flow walkthrough
- Files provided summary
- Gripper reflex complete example
- Layer 1 invariants (18 total)
- Parser pattern examples
- Implementation checklist
- Key takeaways
- Next steps

**Use this when:** You need a quick overview or 30-second explanation.

## File Locations (All Absolute Paths)

### Core Module
```
/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/
├── __init__.py                           (60 lines)  - Module exports
├── pipeline.py                          (268 lines) - Main orchestrator
├── utils.py                              (27 lines) - extract_numeric()
├── spike_encoding.py                    (132 lines) - Encoding utilities
├── visualization.py                     (322 lines) - Plotting tools
├── cnl/
│   ├── cnl_parser.py                   (473 lines) - Parser (13 concepts)
│   └── types.py                         (16 lines) - ParsedSentence TypedDict
├── layers/
│   ├── layer1_validator.py              (70 lines) - Invariant validation
│   ├── layer1_invariants.py            (316 lines) - 18 invariants
│   └── layer2_validator.py             (241 lines) - Cross-sentence checks
├── generation/
│   ├── nengo_generator.py              (488 lines) - Network generation
│   └── assertion_generator.py          (400+ lines)- Test generation
└── export/
    ├── __init__.py                      (54 lines) - export() dispatcher
    ├── c_header_exporter.py            (127 lines) - Microcontroller
    ├── neuroml_exporter.py                          - NeuroML export
    ├── loihi_exporter.py                            - Loihi hardware
    ├── lava_exporter.py                             - Lava framework
    └── spinnaker_exporter.py                        - SpiNNaker platform
```

### Examples
```
/Users/yoshimartodihardjo/Neuro-space/neurocnl/examples/
├── 01_parse_spec.py         - Parsing demo
├── 02_validate_spec.py      - Validation demo
├── 03_generate_network.py   - Network generation demo
├── 04_full_pipeline.py      - Complete end-to-end with MuJoCo
└── 05_demo_simulations.py   - Hardware simulation demos
```

### Demo Project
```
/Users/yoshimartodihardjo/Neuro-space/neurocnl/demos/gripper_reflex/
├── gripper_reflex.cnl       - 4-line CNL specification
└── README.md                - Hardware wiring + architecture
```

## The 13 Concepts (Quick Reference)

### Required Core (4)
1. **threshold_firing** - Fire when V > threshold
2. **refractory_period** - Blocked for X seconds after spike
3. **membrane_potential_decay** - Exponential decay with tau
4. **synaptic_weight** - Connection strength

### Extended (9)
5. **axonal_delay** - Transmission delay
6. **stdp_learning** - Spike-timing plasticity
7. **inhibitory_connection** - Negative weights
8. **population_coding** - N neurons → D dimensions
9. **network_topology** - Multi-population architectures
10. **lateral_inhibition** - Competitive self-organization
11. **homeostatic_plasticity** - Target firing rate
12. **neuromodulation** - Modulatory signals
13. **population_coding_range** - Feature ranges

**All patterns documented with full regexes in neurocnl_complete_reference.md**

## Architecture Overview

```
Input CNL Spec (Plain English)
         ↓
    [STAGE 1: PARSE]  → 13 regex patterns → ParsedSentence[]
         ↓
    [STAGE 2: VALIDATE] → 18 Layer 1 invariants + Layer 2 checks
         ↓
    [STAGE 3: GENERATE] → Nengo network with LIF neurons
         ↓
    [STAGE 4: SIMULATE] → nengo.Simulator (1.0 second)
         ↓
    [STAGE 5: ASSERT] → Auto-generated pytest tests
         ↓
    [STAGE 6: EXPORT] → C header / NeuroML / Loihi / Lava / SpiNNaker

All 6 stages automated in: run_pipeline(spec_text) → PipelineResult
```

## Key Classes

### ParsedSentence (TypedDict)
```python
{
    'concept': str          # One of 13 concepts
    'subject': str          # Neuron/population being described
    'action': str           # Verb action (fire, decay, have, etc.)
    'verb': str             # "MUST" or "MUST NOT"
    'negated': bool         # True if "NOT" present
    'condition': str | None # Numeric/descriptive parameters
    'raw': str              # Original CNL text
}
```

### PipelineResult (@dataclass)
```python
{
    'parsed': list[ParsedSentence]      # Output of parser
    'validation': dict                  # Layer 1+2 validation report
    'network': nengo.Network | None     # Generated SNN
    'simulation': dict                  # Duration, wall_time, motor_output
    'assertions': dict                  # Passed/failed counts
    'errors': list[str]                 # Any errors encountered
    'neuron_params': dict               # Extracted parameters
    'overall_pass': bool                # True if all 5 stages passed
}
```

## Example: Complete Demo in 10 Lines

```python
from neurocnl import run_pipeline

spec_text = """
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
"""

result = run_pipeline(spec_text)
print(f"✓ PASS" if result.overall_pass else f"✗ FAIL")
print(f"  Parsed: {len(result.parsed)} specs")
print(f"  Network: {result.network}")
```

## Layer 1 Invariants (18 Total)

### LIF Core (6)
- `threshold_above_resting`: threshold > resting_potential
- `refractory_period_positive`: refractory_period > 0
- `time_constant_positive`: tau > 0
- `reset_at_or_below_threshold`: reset_potential ≤ threshold
- `membrane_potential_decays_toward_rest`: dv/dt equation
- `axonal_delay_in_range`: 0 ≤ delay ≤ max

### Learning (5)
- `stdp_window_positive`: 0 < window ≤ 100ms
- `stdp_weight_bounds_valid`: w_min < w_max
- `inhibitory_weight_negative`: weight ≤ 0
- `learning_rate_positive`: lr > 0
- `learning_rule_valid`: rule ∈ {PES, BCM, OJA, STDP}

### Population (7)
- `population_neuron_count_positive`, `population_dimensions_positive`, `population_radius_positive`
- `lateral_inhibition_radius_positive`, `homeostatic_target_rate_positive`
- `neuromodulation_factor_positive`, `population_coding_range_positive`

### Loihi-Specific (3, optional)
- `loihi_weight_quantizable`: 8-bit signed int
- `loihi_ensemble_size_within_limits`: ≤ 1024 neurons
- `loihi_delay_in_range`: 0 ≤ delay ≤ 62ms

## Critical Functions Quick Reference

| Function | File | Lines | Purpose |
|----------|------|-------|---------|
| `run_pipeline()` | pipeline.py | 133-268 | Full automation (parse→validate→generate→simulate→assert) |
| `parse_spec_text()` | pipeline.py | 75-94 | Parse CNL lines |
| `parse()` | cnl_parser.py | 427-472 | Parse single sentence |
| `validate_spec()` | pipeline.py | 97-130 | Layer 1+2 validation |
| `default_params_from_specs()` | pipeline.py | 43-72 | Extract parameters |
| `validate()` | layer1_validator.py | 15-69 | Layer 1 invariants |
| `validate_cross_sentence()` | layer2_validator.py | 191-240 | Layer 2 checks |
| `generate()` | nengo_generator.py | 29-487 | Generate Nengo network |
| `export()` | export/__init__.py | 26-53 | Multi-format export |
| `export_c_header()` | export/c_header_exporter.py | 12-126 | Microcontroller export |

## Gripper Reflex Demo

**CNL Specification** (4 lines):
```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
```

**Hardware**:
- Teensy 4.1 microcontroller
- FSR 402 force sensor (Pin A0)
- Servo motor (Pin 9)
- 3D-printed gripper

**Architecture**:
```
FSR Signal → Rate Encoding → 50 Sensory LIF Neurons
             τ=0.01s, threshold=0.8
                         ↓ (weight=1.5)
                50 Motor LIF Neurons → Servo PWM
```

**Complete Implementation Available At**:
```
/Users/yoshimartodihardjo/Neuro-space/neurocnl/demos/gripper_reflex/gripper_reflex.cnl
/Users/yoshimartodihardjo/Neuro-space/neurocnl/demos/gripper_reflex/README.md
```

## Files You Should Have

✓ `/Users/yoshimartodihardjo/Neuro-space/neurocnl_complete_reference.md` (1011 lines)
✓ `/Users/yoshimartodihardjo/Neuro-space/QUICK_START_GUIDE.md` (359 lines)
✓ `/Users/yoshimartodihardjo/Neuro-space/NEUROCNL_EXPLORATION_SUMMARY.txt` (344 lines)
✓ `/Users/yoshimartodihardjo/Neuro-space/README_EXPLORATION_RESULTS.md` (THIS FILE)

## How to Use These Documents

**Just want to implement something quickly?**
→ Read `QUICK_START_GUIDE.md`

**Need complete technical details?**
→ Read `neurocnl_complete_reference.md`

**Want a high-level overview?**
→ Read `NEUROCNL_EXPLORATION_SUMMARY.txt`

**Need to find something specific?**
→ Use grep/search in the reference files (line numbers provided)

## Next Steps

1. Pick one of the reference documents based on your need
2. Review the gripper reflex example in `/neurocnl/demos/gripper_reflex/`
3. Run one of the example scripts in `/neurocnl/examples/`
4. Write your own CNL specification
5. Use `neurocnl.run_pipeline(your_spec)` for instant results

---

**Last Updated**: 2024-03-15
**Explored**: Complete neurocnl codebase (2,838 lines across 14 core files)
**Coverage**: All 13 concepts, all invariants, all functions, all exporters
