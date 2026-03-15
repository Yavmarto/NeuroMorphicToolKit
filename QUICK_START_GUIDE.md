# neurocnl Quick Start Guide - Demo Implementation

## What You Have
A complete Natural Language → Spiking Neural Network pipeline with:

### Core Module (`neurocnl/neurocnl/`)
- **cnl_parser.py** (473 lines): Regex-based parser for 13 neuromorphic concepts
- **pipeline.py** (268 lines): Orchestrator (`run_pipeline()`, `validate_spec()`, `parse_spec_text()`)
- **layers/layer1_validator.py** (70 lines): Check 18 biological invariants
- **layers/layer1_invariants.py** (316 lines): Define all invariant functions
- **layers/layer2_validator.py** (241 lines): Cross-sentence consistency checks
- **generation/nengo_generator.py** (488 lines): Generate Nengo SNN from specs
- **generation/assertion_generator.py** (400+ lines): Auto-generate pytest tests
- **export/__init__.py** (54 lines) + exporters: Export to C, NeuroML, Loihi, Lava, SpiNNaker
- **spike_encoding.py** (132 lines): rate_encode(), temporal_encode(), delta_encode()

### Example Files (`neurocnl/examples/`)
- **01_parse_spec.py**: How to parse CNL sentences
- **02_validate_spec.py**: How to validate parameters
- **03_generate_network.py**: How to generate and run Nengo network
- **04_full_pipeline.py**: Complete end-to-end with MuJoCo physics
- **05_demo_simulations.py**: Hardware demo simulations

### Demo Project (`neurocnl/demos/gripper_reflex/`)
- **gripper_reflex.cnl**: Example CNL spec (4 lines)
- **README.md**: Hardware wiring, neural architecture, training protocol

---

## The 13 Concepts (Parser Patterns)

### Core (Required for any network)
1. **threshold_firing**: Neuron fires when membrane potential exceeds X
2. **refractory_period**: Neuron blocked for X seconds after firing
3. **membrane_potential_decay**: Voltage decays with time constant τ
4. **synaptic_weight**: Connection strength between neurons

### Extended Concepts
5. **axonal_delay**: Transmission delay between neurons
6. **stdp_learning**: Spike-timing-dependent plasticity rules
7. **inhibitory_connection**: Negative-weight suppressive connections
8. **population_coding**: N neurons representing D-dimensional signals
9. **network_topology**: Multi-population architectures
10. **lateral_inhibition**: Self-organizing competition
11. **homeostatic_plasticity**: Target firing rate maintenance
12. **neuromodulation**: Modulatory factors (dopamine, etc.)
13. **population_coding_range**: Stimulus feature ranges (e.g., 360° orientation)

---

## Usage Pattern

### 1. Write CNL Spec (Plain English + Math)
```python
spec_text = """
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
"""
```

### 2. Run Full Pipeline
```python
from neurocnl import run_pipeline

result = run_pipeline(spec_text)

# Check results
print(f"Overall: {'PASS' if result.overall_pass else 'FAIL'}")
print(f"Parsed specs: {len(result.parsed)}")
print(f"Validation: {result.validation['overall']}")
print(f"Network: {result.network}")
print(f"Simulation wall time: {result.simulation.get('wall_time_seconds')}s")
print(f"Assertions: {result.assertions}")
```

### 3. Export to Hardware
```python
from neurocnl import export

# To C header for Teensy 4.1
c_code = export(result.network, format='c_header')
with open('network.h', 'w') as f:
    f.write(c_code)

# To NeuroML
xml_code = export(result.network, format='neuroml')

# To Loihi / Lava / SpiNNaker
lava_code = export(result.network, format='lava')
```

---

## Step-by-Step Implementation

### Step 1: Parse
```python
from neurocnl import parse, ParseError

sentence = "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0"
try:
    parsed = parse(sentence)
    print(parsed)
    # {
    #     'concept': 'threshold_firing',
    #     'subject': 'sensory neuron',
    #     'verb': 'MUST',
    #     'negated': False,
    #     'action': 'fire',
    #     'condition': 'exceeds 1.0',
    #     'raw': '...'
    # }
except ParseError as e:
    print(f"Invalid: {e}")
```

### Step 2: Validate
```python
from neurocnl import parse, validate

specs = [parse(line) for line in spec_text.strip().split('\n')]

neuron_params = {
    'threshold': 1.0,
    'resting_potential': 0.0,
    'refractory_period': 0.002,
    'tau': 0.02,
    'reset_potential': 0.0,
    'current_voltage': 0.5,
    'synaptic_weight': 1.5,
}

report = validate(specs, neuron_params)
if report['overall']:
    print("✓ All invariants passed!")
else:
    for failure in report['failed']:
        print(f"✗ {failure['name']}: {failure['reason']}")
```

### Step 3: Generate
```python
from neurocnl import generate

net = generate(specs, neuron_params)
print(f"Sensory neurons: {net.sensory.n_neurons}")
print(f"Motor neurons: {net.motor.n_neurons}")
```

### Step 4: Simulate
```python
import nengo

with net:
    probe = nengo.Probe(net.motor_ensemble, synapse=0.01)

with nengo.Simulator(net) as sim:
    sim.run(1.0)  # 1 second simulation

output = sim.data[probe]
print(f"Motor output range: [{output.min():.4f}, {output.max():.4f}]")
```

### Step 5: Assert
```python
from neurocnl import run_pipeline

result = run_pipeline(spec_text)
print(f"Assertions passed: {result.assertions.get('passed')}")
print(f"Assertions failed: {result.assertions.get('failed')}")
```

---

## PipelineResult Class

```python
@dataclass
class PipelineResult:
    parsed: list[ParsedSentence]  # Output of parser
    validation: dict              # Layer 1+2 validation report
    network: nengo.Network | None # Generated SNN
    simulation: dict              # Duration, wall_time, motor_output
    assertions: dict              # Passed/failed counts
    errors: list[str]             # Any errors encountered
    neuron_params: dict           # Extracted parameters
    overall_pass: bool            # True if all 5 stages passed
```

---

## Key Functions & Signatures

### `run_pipeline(spec_text, backend="nengo", verbose=False, user_params=None, skip_simulation=False, skip_assertions=False) -> PipelineResult`
Executes: Parse → Validate → Generate → Simulate → Assert

### `parse_spec_text(spec_text: str) -> list[dict]`
Returns: List of `{"line": int, "raw": str, "parsed": ParsedSentence|None, "valid": bool, "error": str|None}`

### `parse(sentence: str) -> ParsedSentence`
Tries all 13 patterns. Raises `ParseError` if no match.

### `validate_spec(parsed_specs, neuron_params, backend="nengo") -> dict`
Returns: `{"layer1": {...}, "layer2": {...}, "overall": bool}`

### `default_params_from_specs(parsed_specs) -> dict`
Auto-extracts parameter values from parsed specs. Fills in defaults.

### `validate(parsed_specs, neuron_params, backend="nengo") -> dict`
Layer 1 only. Returns: `{"passed": [str], "failed": [{"name", "reason"}], "overall": bool}`

### `generate(parsed_specs, neuron_params) -> nengo.Network`
Creates Nengo network with:
- `net.populations`: dict of ensembles
- `net.sensory`, `net.motor`: aliases for backward compat
- `net.input_node`: stimulus input
- `net.motor_probe`: output probe
- `net.spec_connections`: all connections
- Learning rule nodes (STDP/BCM/Oja if specified)

### `export(net, format: str, **kwargs) -> str`
Formats: 'neuroml' | 'c_header' | 'loihi' | 'lava' | 'spinnaker'

### `rate_encode(signal, dt, max_rate=100.0) -> np.ndarray`
Converts analog signal → spike train (rate coding)

### `temporal_encode(signal, dt, n_phases=8) -> np.ndarray`
Converts analog signal → spike train (phase coding)

### `delta_encode(signal, dt, threshold=0.1) -> np.ndarray`
Converts analog signal → spike train (change detection)

---

## Layer 1 Invariants (18 Total)

### LIF Core (6)
- `threshold_above_resting`: threshold > resting_potential
- `refractory_period_positive`: refractory_period > 0
- `time_constant_positive`: tau > 0
- `reset_at_or_below_threshold`: reset_potential ≤ threshold
- `membrane_potential_decays_toward_rest`: dv/dt equation satisfied
- `axonal_delay_in_range`: 0 ≤ delay ≤ max_delay

### Learning (5)
- `stdp_window_positive`: 0 < window ≤ 100ms
- `stdp_weight_bounds_valid`: w_min < w_max
- `inhibitory_weight_negative`: weight ≤ 0
- `learning_rate_positive`: lr > 0
- `learning_rule_valid`: rule in {PES, BCM, OJA, STDP}

### Population/Architecture (7)
- `population_neuron_count_positive`: n_neurons > 0
- `population_dimensions_positive`: dims > 0
- `population_radius_positive`: radius > 0
- `lateral_inhibition_radius_positive`: radius > 0
- `homeostatic_target_rate_positive`: rate > 0
- `neuromodulation_factor_positive`: factor > 0
- `population_coding_range_positive`: range > 0

### Loihi-Specific (3)
- `loihi_weight_quantizable`: Fits in 8-bit signed int
- `loihi_ensemble_size_within_limits`: n_neurons ≤ 1024
- `loihi_delay_in_range`: 0 ≤ delay ≤ 62ms

---

## Example: Gripper Reflex

### CNL Specification
```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
```

### Hardware Wiring
```
FSR 402 (force) → Teensy A0 (analog)
Teensy Pin 9 → Servo PWM
```

### Neural Architecture
```
Sensory Input
    ↓ [Rate encode FSR signal]
    ↓ [50 LIF neurons, τ=0.01s, threshold=0.8]
    ↓ [Weight 1.5]
    ↓ [50 Motor neurons, τ=0.02s]
    ↓
Servo Output
```

### Training Protocol
1. Present object, record baseline grip force
2. Increase weight until slip occurs
3. STDP strengthens sensory→motor connection
4. Repeat until network grips heavier objects

---

## File Locations (Absolute Paths)

### Source Code
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/__init__.py` - Module exports
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/pipeline.py` - Main orchestration
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/cnl/cnl_parser.py` - Parser (13 concepts)
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/layers/layer1_validator.py` - Invariant checking
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/layers/layer1_invariants.py` - 18 invariants
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/layers/layer2_validator.py` - Cross-sentence checks
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/generation/nengo_generator.py` - Network generation
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/generation/assertion_generator.py` - Test generation
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/export/__init__.py` - Export dispatcher
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/export/c_header_exporter.py` - Microcontroller export

### Examples
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/examples/01_parse_spec.py`
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/examples/02_validate_spec.py`
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/examples/03_generate_network.py`
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/examples/04_full_pipeline.py`
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/examples/05_demo_simulations.py`

### Demo
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/demos/gripper_reflex/gripper_reflex.cnl`
- `/Users/yoshimartodihardjo/Neuro-space/neurocnl/demos/gripper_reflex/README.md`

---

## Critical Regex Patterns Summary

```python
# Concept 1: Threshold Firing
r"^(?:The|A)\s+(?:sensory|motor)\s+neuron\s+MUST(?:\s+NOT)?\s+(?:fire|emit\s+a\s+spike)\s+(?:ONLY\s+)?IF\s+membrane\s+potential\s+(exceeds|is\s+below)\s+(\d+(?:\.\d+)?)"

# Concept 4: Synaptic Weight
r"^The\s+connection\s+from\s+(.+?)\s+to\s+(.+?)\s+MUST(?:\s+NOT)?\s+(?:have|transmit|scale\s+input)\s+WITH\s+synaptic\s+weight\s+of\s+(-?\d+(?:\.\d+)?)"

# Concept 6: STDP Learning
r"^(?:The|A)\s+connection\s+from\s+(...)\s+to\s+(...)\s+MUST(?:\s+NOT)?\s+adapt\s+WITH\s+(?:STDP|BCM|Oja)\s+learning(?:\s+rate\s+of\s+(\d+(?:\.\d+)?))"

# All patterns in: /Users/yoshimartodihardjo/Neuro-space/neurocnl/neurocnl/cnl/cnl_parser.py (lines 19-302)
```

---

## Next Steps for Your Demo

1. **Write your CNL spec** - Plain English sentences describing neuron behavior
2. **Test parsing** - Use `neurocnl.parse()` on each sentence
3. **Validate params** - Use `neurocnl.validate()` with reasonable LIF parameters
4. **Generate network** - Use `neurocnl.generate()` to create Nengo SNN
5. **Simulate** - Use `nengo.Simulator()` to run and record outputs
6. **Export** - Use `neurocnl.export(net, format='c_header')` for embedded deployment
7. **Test assertions** - Let `neurocnl.generate_assertions()` create pytest tests

All 5 steps automated in: `neurocnl.run_pipeline(spec_text)`
