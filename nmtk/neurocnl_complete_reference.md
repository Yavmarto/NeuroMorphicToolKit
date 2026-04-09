# NeuroControl Natural Language (neurocnl) - Complete Codebase Reference

## Overview
neurocnl is a Python framework that translates Controlled Natural Language (CNL) specifications for neuromorphic computing into validated Nengo spiking neural networks. It supports 13 concepts covering threshold firing, refractory periods, membrane potential dynamics, synaptic plasticity, learning rules, and network topology.

---

## Directory Structure

```
/Users/yoshimartodihardjo/Neuro-space/neurocnl/
├── neurocnl/                      # Main package
│   ├── __init__.py               # Exports: parse, validate, generate, run_pipeline, export, EXPORTERS
│   ├── pipeline.py               # Main orchestration: run_pipeline(), PipelineResult, validate_spec(), parse_spec_text(), default_params_from_specs()
│   ├── utils.py                  # Helper: extract_numeric()
│   ├── spike_encoding.py         # Analog→spike conversion: rate_encode(), temporal_encode(), delta_encode()
│   ├── visualization.py          # Plotting tools (requires matplotlib)
│   ├── cnl/                      # CNL Parser module
│   │   ├── cnl_parser.py        # Main parser with 13 concept patterns (470 lines)
│   │   └── types.py             # ParsedSentence TypedDict definition
│   ├── layers/                   # Validation layers
│   │   ├── layer1_validator.py  # validate() function (70 lines)
│   │   ├── layer1_invariants.py # 18 biological invariants + Loihi constraints (316 lines)
│   │   └── layer2_validator.py  # Cross-sentence validation (241 lines)
│   ├── generation/               # Network generation
│   │   ├── nengo_generator.py   # generate() function (488 lines)
│   │   └── assertion_generator.py # Layer 3 assertions (generated pytest code)
│   ├── export/                   # Multi-format exporters
│   │   ├── __init__.py          # export() function
│   │   ├── c_header_exporter.py # Teensy/microcontroller export
│   │   ├── neuroml_exporter.py
│   │   ├── loihi_exporter.py
│   │   ├── lava_exporter.py
│   │   └── spinnaker_exporter.py
│   ├── tests/                    # Unit tests
│   └── simulation/               # MuJoCo physics integration
├── examples/                      # Example scripts (5 progressively complex examples)
│   ├── 01_parse_spec.py
│   ├── 02_validate_spec.py
│   ├── 03_generate_network.py
│   ├── 04_full_pipeline.py       # Complete end-to-end demo
│   └── 05_demo_simulations.py    # Hardware demo simulations
└── demos/
    └── gripper_reflex/
        ├── gripper_reflex.cnl    # Example CNL spec for robotic gripper
        └── README.md             # Gripper demo with hardware wiring diagram
```

---

## THE 13 CONCEPTS (Parser Patterns in cnl_parser.py)

### Concept 1: **Threshold Firing**
```python
# Pattern:
_THRESHOLD_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>(?:sensory|motor)\s+neuron)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>(?:fire|emit\s+a\s+spike))\s+"
        r"(?:ONLY\s+)?IF\s+membrane\s+potential\s+"
        r"(?P<condition>(?:exceeds|is\s+below)\s+(?:\d+(?:\.\d+)?|threshold))$",
        re.IGNORECASE,
    ),
]

# Examples:
"The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8"
"A motor neuron MUST NOT fire ONLY IF membrane potential is below threshold"
"The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.5"
```

### Concept 2: **Refractory Period**
```python
_REFRACTORY_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>(?:sensory|motor)\s+neuron)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>(?:fire|respond\s+to\s+input|accept\s+input))\s+"
        r"DURING\s+the\s+refractory\s+period"
        r"(?:\s+of\s+(?P<duration>\d+(?:\.\d+)?)\s+seconds)?$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^(?:The|A)\s+(?P<subject>(?:sensory|motor)\s+neuron)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>remain\s+inactive)\s+"
        r"AFTER\s+firing\s+for\s+"
        r"(?P<duration>\d+(?:\.\d+)?)\s+seconds$",
        re.IGNORECASE,
    ),
]

# Examples:
"The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds"
"The sensory neuron MUST NOT respond to input DURING the refractory period"
"The sensory neuron MUST remain inactive AFTER firing for 0.002 seconds"
```

### Concept 3: **Membrane Potential Decay**
```python
_DECAY_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>(?:sensory|motor)\s+neuron\s+membrane\s+potential)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>decay(?:\s+toward\s+resting\s+potential)?)\s+"
        r"WITH\s+time\s+constant\s+(?:of\s+)?"
        r"(?P<tau>\d+(?:\.\d+)?)\s+seconds$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^(?:The|A)\s+(?P<subject>(?:sensory|motor)\s+neuron\s+membrane\s+potential)\s+"
        r"(?P<verb>MUST\s+NOT)\s+"
        r"(?P<action>increase)\s+"
        r"WITHOUT\s+input$",
        re.IGNORECASE,
    ),
]

# Examples:
"The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds"
"The motor neuron membrane potential MUST NOT increase WITHOUT input"
```

### Concept 4: **Synaptic Weight**
```python
_SYNAPTIC_PATTERNS = [
    re.compile(
        r"^The\s+connection\s+from\s+"
        r"(?P<subject>.+?\s+to\s+.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>(?:have|transmit|scale\s+input))\s+"
        r"WITH\s+synaptic\s+weight\s+of\s+"
        r"(?P<weight>-?\d+(?:\.\d+)?)$",
        re.IGNORECASE,
    ),
]

# Examples:
"The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5"
"The connection from sensory neuron to motor neuron MUST transmit WITH synaptic weight of 0.5"
"The connection from sensory neuron to motor neuron MUST NOT have WITH synaptic weight of 0.0"
```

### Concept 5: **Axonal Delay**
```python
_DELAY_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>synapse|connection)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>have\s+a\s+transmission\s+delay)\s+"
        r"of\s+(?P<delay>\d+(?:\.\d+)?)\s*(?P<unit>ms|seconds?)\.?$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^The\s+connection\s+from\s+"
        r"(?P<subject>.+?\s+to\s+.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>transmit)\s+"
        r"WITH\s+delay\s+of\s+(?P<delay>\d+(?:\.\d+)?)\s*(?P<unit>ms|seconds?)\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"A synapse MUST have a transmission delay of 5ms"
"The connection from sensory neuron to motor neuron MUST transmit WITH delay of 3ms"
"A synapse MUST have a transmission delay of 0.005 seconds"
```

### Concept 6: **STDP Learning Rule**
```python
_STDP_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>synapse)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>strengthen|weaken)\s+"
        r"IF\s+(?P<condition>(?:pre|post)-synaptic\s+spike\s+precedes\s+"
        r"(?:pre|post)-synaptic\s+spike"
        r"(?:\s+by\s+less\s+than\s+(?P<window>\d+(?:\.\d+)?)\s*(?P<unit>ms|seconds?))?)\.?$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^(?:The|A)\s+(?P<subject>synapse)\s+"
        r"(?P<verb>MUST\s+NOT)\s+"
        r"(?P<action>have\s+weights\s+(?:exceeding|below))\s+"
        r"(?P<weight_bound>\d+(?:\.\d+)?)\.?$",
        re.IGNORECASE,
    ),
    # STDP learning rate:
    re.compile(
        r"^(?:The|A)\s+connection\s+from\s+"
        r"(?P<subject>(?:\w+(?:\s+\w+)*?)\s+to\s+(?:\w+(?:\s+\w+)*))\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>adapt)\s+"
        r"WITH\s+STDP\s+learning\s+rate\s+of\s+"
        r"(?P<learning_rate>\d+(?:\.\d+)?)$",
        re.IGNORECASE,
    ),
    # BCM learning:
    re.compile(
        r"^(?:The|A)\s+connection\s+from\s+"
        r"(?P<subject>(?:\w+(?:\s+\w+)*?)\s+to\s+(?:\w+(?:\s+\w+)*))\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>adapt)\s+"
        r"WITH\s+(?P<rule_type>BCM)\s+learning"
        r"(?:\s+rate\s+of\s+(?P<learning_rate>\d+(?:\.\d+)?))?$",
        re.IGNORECASE,
    ),
    # Oja learning:
    re.compile(
        r"^(?:The|A)\s+connection\s+from\s+"
        r"(?P<subject>(?:\w+(?:\s+\w+)*?)\s+to\s+(?:\w+(?:\s+\w+)*))\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>adapt)\s+"
        r"WITH\s+(?P<rule_type>Oja)\s+learning"
        r"(?:\s+rate\s+of\s+(?P<learning_rate>\d+(?:\.\d+)?))?$",
        re.IGNORECASE,
    ),
]

# Examples:
"A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than 20ms"
"A synapse MUST weaken IF post-synaptic spike precedes pre-synaptic spike"
"A synapse MUST NOT have weights exceeding 2.0"
"The connection from sensory neuron to motor neuron MUST adapt WITH STDP learning rate of 0.01"
"The connection from X to Y MUST adapt WITH BCM learning rate of 0.001"
"The connection from X to Y MUST adapt WITH Oja learning rate of 0.001"
```

### Concept 7: **Inhibitory Connections**
```python
_INHIBITORY_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+connection\s+from\s+(?P<subject>.+?)\s+to\s+(?P<target>.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?:be|have)\s+inhibitory"
        r"(?:\s+(?:with\s+)?weight\s+(?:of\s+)?(?P<weight>-?\d+(?:\.\d+)?))?"
        r"\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"The connection from interneuron to motor neuron MUST be inhibitory"
"The connection from sensory neuron to motor neuron MUST be inhibitory with weight of -0.5"
```

### Concept 8: **Population Coding / Ensemble Parameters**
```python
_POPULATION_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>encode\s+input)\s+using\s+(?P<n_neurons>\d+)\s+neurons"
        r"(?:\s+with\s+(?P<dimensions>\d+)\s+dimensions?)?"
        r"\.?$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^(?:The|A)\s+(?P<subject>.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>represent\s+values)\s+in\s+range\s+"
        r"(?P<range_min>-?\d+(?:\.\d+)?)\s+to\s+(?P<range_max>-?\d+(?:\.\d+)?)"
        r"\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"The sensory population MUST encode input using 100 neurons"
"The motor ensemble MUST represent values in range -1 to 1"
"The sensory population MUST encode input using 50 neurons with 2 dimensions"
```

### Concept 9: **Network Topology**
```python
_NETWORK_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+network\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"contain\s+(?:an?\s+)?(?P<pop_type>excitatory|inhibitory)\s+"
        r"(?P<subject>\w+(?:\s+\w+)*?)\s+population\s+"
        r"of\s+(?P<n_neurons>\d+)\s+neurons"
        r"\.?$",
        re.IGNORECASE,
    ),
    re.compile(
        r"^(?:The|A)\s+(?P<subject>.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>project\s+to)\s+"
        r"(?:both\s+)?(?P<targets>.+)"
        r"\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"The network MUST contain an inhibitory interneuron population of 30 neurons"
"The network MUST contain an excitatory relay population of 50 neurons"
"The sensory neuron MUST project to both motor neuron AND interneuron"
```

### Concept 10: **Lateral Inhibition**
```python
_LATERAL_INHIBITION_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>inhibit\s+neighboring\s+neurons)\s+"
        r"WITHIN\s+radius\s+of\s+(?P<radius>\d+(?:\.\d+)?)"
        r"\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"The sensory neuron MUST inhibit neighboring neurons WITHIN radius of 2"
```

### Concept 11: **Homeostatic Plasticity**
```python
_HOMEOSTATIC_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>maintain\s+average\s+firing\s+rate)\s+"
        r"of\s+(?P<target_rate>\d+(?:\.\d+)?)\s*(?:Hz|hz)"
        r"\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"The sensory neuron MUST maintain average firing rate of 10 Hz"
```

### Concept 12: **Neuromodulation**
```python
_NEUROMODULATION_PATTERNS = [
    re.compile(
        r"^(?:The|A\s+)?(?P<subject>\w+(?:\s+\w+)*?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>modulate\s+synaptic\s+weight)\s+"
        r"BY\s+factor\s+of\s+(?P<factor>\d+(?:\.\d+)?)"
        r"\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"Dopamine MUST modulate synaptic weight BY factor of 1.5"
```

### Concept 13: **Population Coding Range**
```python
_CODING_RANGE_PATTERNS = [
    re.compile(
        r"^(?:The|A)\s+(?P<subject>.+?)\s+"
        r"(?P<verb>MUST(?:\s+NOT)?)\s+"
        r"(?P<action>encode\s+(?:stimulus\s+)?\w+)\s+"
        r"WITH\s+(?P<range_val>\d+(?:\.\d+)?)\s+degree\s+range"
        r"\.?$",
        re.IGNORECASE,
    ),
]

# Examples:
"The population MUST encode stimulus orientation WITH 360 degree range"
```

---

## Core Classes & Functions

### 1. **ParsedSentence** (types.py)
```python
class ParsedSentence(TypedDict):
    """Structured output from parsing a single CNL sentence."""
    concept: str          # One of 13 concepts above
    subject: str          # Neuron/population being described
    action: str           # Verb action (fire, decay, have, etc.)
    verb: str             # MUST or MUST NOT
    negated: bool         # True if "NOT" present
    condition: str | None # Numeric/descriptive parameters
    raw: str              # Original CNL text
```

### 2. **PipelineResult** (pipeline.py)
```python
@dataclass
class PipelineResult:
    """Result of a full pipeline run."""
    parsed: list[ParsedSentence] = field(default_factory=list)
    validation: dict = field(default_factory=dict)
    network: object | None = None
    simulation: dict = field(default_factory=dict)
    assertions: dict = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)
    neuron_params: dict = field(default_factory=dict)
    overall_pass: bool = False
```

### 3. **run_pipeline()** (pipeline.py)
```python
def run_pipeline(
    spec_text: str,
    backend: str = "nengo",
    verbose: bool = False,
    user_params: dict | None = None,
    skip_simulation: bool = False,
    skip_assertions: bool = False,
) -> PipelineResult:
    """Execute the full pipeline: parse → validate → generate → simulate → assert.

    Parameters
    ----------
    spec_text : str
        Raw CNL spec text (multi-line).
    backend : str
        "nengo" (default) or "loihi".
    verbose : bool
        Enable verbose logging.
    user_params : dict | None
        User-supplied parameter overrides.
    skip_simulation : bool
        If True, stop after network generation.
    skip_assertions : bool
        If True, skip Layer 3 assertion generation/execution.

    Returns
    -------
    PipelineResult
        Aggregated result with parsed specs, validation, network, simulation, assertions.

    Steps:
    1. Parse each non-empty, non-comment line using parse_spec_text()
    2. Build neuron_params from parsed specs using default_params_from_specs()
    3. Validate using validate_spec() (Layer 1 + Layer 2)
    4. Generate Nengo network using generate()
    5. Run nengo.Simulator for 1.0 second
    6. Generate and execute pytest assertions (Layer 3)
    7. Return aggregated result
    """
```

### 4. **parse_spec_text()** (pipeline.py)
```python
def parse_spec_text(spec_text: str) -> list[dict]:
    """Parse each non-empty, non-comment line of spec_text.

    Returns a list of result dicts with keys: line, raw, parsed, valid, error.

    Returns
    -------
    list[dict]
        Each dict:
        - line: line number (1-indexed)
        - raw: stripped text
        - parsed: ParsedSentence (if valid==True) or None
        - valid: bool
        - error: str (if valid==False) or None
    """
```

### 5. **parse()** (cnl_parser.py)
```python
def parse(sentence: str) -> ParsedSentence:
    """Parse a CNL sentence into a structured dictionary.

    Tries all 13 concept patterns in sequence until one matches.
    Uses pure regex — no LLM required.

    Parameters
    ----------
    sentence : str
        A plain text CNL sentence.

    Returns
    -------
    ParsedSentence
        Keys: concept, subject, condition, action, verb, negated, raw

    Raises
    ------
    ParseError
        If the sentence does not match any grammar pattern.
    """
```

### 6. **validate_spec()** (pipeline.py)
```python
def validate_spec(
    parsed_specs: list[ParsedSentence],
    neuron_params: dict,
    backend: str = "nengo",
) -> dict:
    """Run Layer 1 + Layer 2 validation and return a combined result.

    Layer 1: Check physical invariants against neuron_params
    Layer 2: Check cross-sentence consistency

    Returns
    -------
    dict
        {
            "layer1": {"overall": bool, "passed": [...], "failed": [...]},
            "layer2": {"overall": bool, "checks_passed": [...], "checks_failed": [...]},
            "overall": bool
        }
    """
```

### 7. **default_params_from_specs()** (pipeline.py)
```python
def default_params_from_specs(parsed_specs: list[ParsedSentence]) -> dict:
    """Build a reasonable neuron_params dict from parsed spec values.

    Maps concept → parameter name:
    - "threshold_firing" → "threshold"
    - "refractory_period" → "refractory_period"
    - "membrane_potential_decay" → "tau"
    - "synaptic_weight" → "synaptic_weight"
    - "axonal_delay" → "axonal_delay"
    - "population_coding" → "population_n_neurons"

    Returns
    -------
    dict
        {
            "threshold": 1.0,
            "resting_potential": 0.0,
            "refractory_period": 0.002,
            "tau": 0.02,
            "reset_potential": 0.0,
            "current_voltage": 0.5,
            "synaptic_weight": 1.0,
            ... (plus any extracted from parsed specs)
        }
    """
```

### 8. **validate()** aka **l1_validate()** (layer1_validator.py)
```python
def validate(
    _parsed_specs: list[ParsedSentence],
    neuron_params: dict,
    backend: str = "nengo",
) -> dict:
    """Validate parsed CNL sentences against Layer 1 physical invariants.

    Invariants checked:
    1. threshold_above_resting: threshold > resting_potential
    2. refractory_period_positive: refractory_period > 0
    3. time_constant_positive: tau > 0
    4. reset_at_or_below_threshold: reset_potential <= threshold
    5. membrane_potential_decays_toward_rest: dv/dt follows LIF dynamics
    6. axonal_delay_in_range: 0 <= delay <= max_delay
    7. stdp_window_positive: 0 < window <= max_window
    8. stdp_weight_bounds_valid: w_min < w_max
    9. inhibitory_weight_negative: inhibitory_weight <= 0
    10. population_neuron_count_positive: n_neurons > 0
    11. population_dimensions_positive: dimensions > 0
    12. population_radius_positive: radius > 0
    13. learning_rate_positive: learning_rate > 0
    14. learning_rule_valid: rule in {PES, BCM, OJA, STDP}
    15. lateral_inhibition_radius_positive: radius > 0
    16. homeostatic_target_rate_positive: rate > 0
    17. neuromodulation_factor_positive: factor > 0
    18. population_coding_range_positive: range > 0

    Plus Loihi-specific invariants if backend=="loihi"

    Returns
    -------
    dict
        {
            "passed": [str],  # Invariant names that passed
            "failed": [{"name": str, "reason": str}, ...],
            "overall": bool
        }
    """
```

### 9. **validate_cross_sentence()** (layer2_validator.py)
```python
def validate_cross_sentence(parsed_specs: list[ParsedSentence]) -> dict:
    """Validate cross-sentence consistency of parsed CNL specs.

    Checks:
    1. no_dangling_connections: All connection endpoints reference defined neurons
    2. no_contradictory_params: Same neuron doesn't have conflicting parameter values
    3. no_orphan_populations: Declared populations have connections

    Returns
    -------
    dict
        {
            "checks_passed": [str],
            "checks_failed": [{"check": str, "detail": str}, ...],
            "neurons_found": [str],
            "connections_found": [(str, str), ...],
            "overall": bool
        }
    """
```

### 10. **generate()** (nengo_generator.py)
```python
def generate(parsed_specs: list[ParsedSentence], neuron_params: dict) -> nengo.Network:
    """Generate a Nengo network from validated CNL specifications.

    Required concepts in parsed_specs:
    - "threshold_firing"
    - "refractory_period"
    - "membrane_potential_decay"
    - "synaptic_weight"

    Creates:
    1. LIF neuron populations with tau_rc, tau_ref, threshold
    2. Synaptic connections with specified weights
    3. Input node (stimulus) → sensory population
    4. Motor probe for output recording
    5. Learning rule nodes if STDP/BCM/Oja specified
    6. Lateral inhibition, homeostatic, neuromodulation nodes

    Parameters
    ----------
    parsed_specs : list[ParsedSentence]
        Validated output of parse()
    neuron_params : dict
        Parameters: tau, threshold, reset_potential, refractory_period, etc.

    Returns
    -------
    nengo.Network
        Network with attributes:
        - net.populations: dict of ensembles
        - net.sensory, net.motor: backward-compatible aliases
        - net.input_node: stimulus input
        - net.motor_probe: output probe
        - net.spec_connections: list of all connections
        - net.connection: first connection (backward compat)
        - net.has_stdp, net.learning_rule_type_name: STDP info
        - net.has_inhibitory, net.has_lateral_inhibition: etc.

    Raises
    ------
    GeneratorError
        If any required concept is missing.
    """
```

### 11. **export()** (export/__init__.py)
```python
def export(net, format: str, **kwargs) -> str:
    """Export a Nengo network to the specified format.

    Parameters
    ----------
    net : nengo.Network
        A Nengo network (typically from neurocnl.generate()).
    format : str
        Target format: 'neuroml', 'c_header', 'loihi', 'lava', 'spinnaker'.
    **kwargs
        Format-specific options passed to the exporter.

    Returns
    -------
    str
        The exported code/markup as a string.

    Raises
    ------
    ValueError
        If the format is not supported.

    EXPORTERS dict:
    {
        "neuroml": export_neuroml,
        "c_header": export_c_header,
        "loihi": export_loihi,
        "lava": export_lava,
        "spinnaker": export_spinnaker,
    }
    """
```

### 12. **export_c_header()** (export/c_header_exporter.py)
```python
def export_c_header(
    net: nengo.Network,
    *,
    guard_name: str = "NEUROCNL_NETWORK_H",
    precision: str = "float",
) -> str:
    """Export a Nengo network to a C header file for microcontrollers.

    Generates:
    1. #define macros for ensemble sizes, neuron indices
    2. LIF parameters (tau_rc, tau_ref) for each population
    3. Synaptic weight arrays
    4. LIF update loop: lif_step(dt, input[])

    Returns
    -------
    str
        C header code ready for Teensy 4.1, Arduino, etc.

    Example output:
    ```c
    #define SENSORY_N_NEURONS 50
    #define SENSORY_TAU_RC 0.02f
    #define SENSORY_TAU_REF 0.002f
    #define W_SENSORY_TO_MOTOR 1.5f

    static float voltage[TOTAL_NEURONS];
    static float refractory[TOTAL_NEURONS];

    static inline void lif_step(const float dt, const float* input) {
        for (int i = 0; i < TOTAL_NEURONS; i++) {
            if (refractory[i] > 0.0f) {
                refractory[i] -= dt;
                continue;
            }
            voltage[i] += dt * (-voltage[i] + input[i]);
            if (voltage[i] >= 1.0f) {
                // Fire
                voltage[i] = 0.0f;
                refractory[i] = 0.002f;
            }
        }
    }
    ```
    """
```

### 13. **Spike Encoding Functions** (spike_encoding.py)
```python
def rate_encode(signal: np.ndarray, dt: float, max_rate: float = 100.0) -> np.ndarray:
    """Convert analog signal to spike train using rate coding.

    Spike probability at each timestep ∝ signal amplitude.
    Higher amplitude → higher spike rate.

    Best for: slow signals (force, temperature)

    Parameters
    ----------
    signal : np.ndarray
        1-D analog signal, shape (n_timesteps,). Non-negative.
    dt : float
        Simulation timestep (e.g., 0.001 for 1ms)
    max_rate : float
        Maximum spike rate in Hz at peak signal. Default 100 Hz.

    Returns
    -------
    np.ndarray
        Binary spike train, shape (n_timesteps,)
    """

def temporal_encode(signal: np.ndarray, dt: float, n_phases: int = 8) -> np.ndarray:
    """Convert analog signal to spike train using temporal/phase coding.

    Signal divided into phase bins. Higher amplitude → earlier spike
    within the phase window.

    Best for: fast signals (EMG, vibration)

    Parameters
    ----------
    signal : np.ndarray
        1-D analog signal, shape (n_timesteps,)
    dt : float
        Simulation timestep
    n_phases : int
        Number of phase bins. Default 8.

    Returns
    -------
    np.ndarray
        Binary spike train, shape (n_timesteps,)
    """

def delta_encode(signal: np.ndarray, dt: float, threshold: float = 0.1) -> np.ndarray:
    """Convert analog signal to spike train using delta modulation.

    Spike emitted when signal change exceeds threshold. Produces
    sparse trains for slow signals, dense for fast signals.

    Best for: event-driven sensors

    Parameters
    ----------
    signal : np.ndarray
        1-D analog signal, shape (n_timesteps,)
    dt : float
        Simulation timestep (for documentation)
    threshold : float
        Minimum absolute signal change to trigger spike. Default 0.1.

    Returns
    -------
    np.ndarray
        Binary spike train, shape (n_timesteps,)
    """
```

---

## Gripper Reflex Demo

### CNL Specification (gripper_reflex.cnl)
```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
```

### Hardware Architecture
```
FSR (force) → Rate encoding → [Sensory ensemble, 50 LIF neurons]
                                           ↓
                                   (synaptic weight 1.5)
                                           ↓
                                [Motor ensemble, 50 LIF neurons]
                                           ↓
                                   Servo PWM command
```

### Wiring
```
Teensy 4.1
├── Pin A0 ← FSR 402 (analog read, voltage divider with 10kΩ)
├── Pin 9  → Servo signal (PWM)
├── 3.3V   → FSR + Servo power
└── GND    → Common ground
```

---

## __init__.py Exports
```python
from neurocnl.cnl.cnl_parser import ParseError, parse
from neurocnl.cnl.types import ParsedSentence
from neurocnl.generation.assertion_generator import generate_assertions
from neurocnl.generation.nengo_generator import GeneratorError, generate
from neurocnl.layers.layer1_validator import validate
from neurocnl.pipeline import PipelineResult, run_pipeline
from neurocnl.spike_encoding import delta_encode, rate_encode, temporal_encode
from neurocnl.export import export, EXPORTERS

__all__ = [
    "__version__",
    "parse",
    "ParseError",
    "ParsedSentence",
    "validate",
    "generate",
    "GeneratorError",
    "generate_assertions",
    "run_pipeline",
    "PipelineResult",
    "rate_encode",
    "temporal_encode",
    "delta_encode",
    "export",
    "EXPORTERS",
    # Optional visualization (if matplotlib installed):
    # "spike_raster", "membrane_traces", "network_topology", "weight_evolution", "to_html",
]
```

---

## Example Usage

### Simple Parsing
```python
from neurocnl import parse, ParseError

try:
    parsed = parse("The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0")
    print(parsed)
    # Output: {
    #     'concept': 'threshold_firing',
    #     'subject': 'sensory neuron',
    #     'verb': 'MUST',
    #     'action': 'fire',
    #     'condition': 'exceeds 1.0',
    #     'negated': False,
    #     'raw': '...'
    # }
except ParseError as e:
    print(f"Parse error: {e}")
```

### Full Pipeline
```python
from neurocnl import run_pipeline

spec_text = """
The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.01 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.5
"""

result = run_pipeline(spec_text)

print(f"Parsed: {len(result.parsed)} specs")
print(f"Validation: {'PASS' if result.validation['overall'] else 'FAIL'}")
print(f"Network generated: {result.network is not None}")
print(f"Simulation wall time: {result.simulation.get('wall_time_seconds')}s")
print(f"Assertions: {result.assertions.get('passed')}/{result.assertions.get('passed') + result.assertions.get('failed')}")
print(f"Overall: {'PASS' if result.overall_pass else 'FAIL'}")
```

### Export to Microcontroller
```python
from neurocnl import parse, validate, generate, export

# Parse, validate, generate
specs = [parse(line) for line in spec_text.strip().split('\n')]
report = validate(specs, neuron_params)
net = generate(specs, neuron_params)

# Export to C header for Teensy
c_code = export(net, format='c_header')
with open('network.h', 'w') as f:
    f.write(c_code)

# Or NeuroML
neuroml_code = export(net, format='neuroml')
```

---

## Layer 1 Invariants (18 total)

### Core LIF Invariants (6)
1. **threshold_above_resting**: `threshold > resting_potential`
2. **refractory_period_positive**: `refractory_period > 0`
3. **time_constant_positive**: `tau > 0`
4. **reset_at_or_below_threshold**: `reset_potential <= threshold`
5. **membrane_potential_decays_toward_rest**: `dv/dt = (rest - v)/tau` dynamics
6. **axonal_delay_in_range**: `0 <= axonal_delay <= max_delay`

### Learning & Plasticity Invariants (5)
7. **stdp_window_positive**: `0 < stdp_window <= max_window`
8. **stdp_weight_bounds_valid**: `w_min < w_max`
9. **inhibitory_weight_negative**: `inhibitory_weight <= 0`
10. **learning_rate_positive**: `learning_rate > 0`
11. **learning_rule_valid**: `rule in {PES, BCM, OJA, STDP}`

### Population & Architecture Invariants (7)
12. **population_neuron_count_positive**: `n_neurons > 0`
13. **population_dimensions_positive**: `dimensions > 0`
14. **population_radius_positive**: `radius > 0`
15. **lateral_inhibition_radius_positive**: `radius > 0`
16. **homeostatic_target_rate_positive**: `target_rate > 0`
17. **neuromodulation_factor_positive**: `factor > 0`
18. **population_coding_range_positive**: `range > 0`

### Loihi-Specific Invariants (3)
19. **loihi_weight_quantizable**: Weight representable in 8-bit signed integer
20. **loihi_ensemble_size_within_limits**: `n_neurons <= 1024` (Loihi core size)
21. **loihi_delay_in_range**: `0 <= delay <= 62ms`

---

## File Line Counts
```
neurocnl/__init__.py                      60 lines
neurocnl/pipeline.py                      268 lines
neurocnl/utils.py                         27 lines
neurocnl/spike_encoding.py                132 lines
neurocnl/visualization.py                 322 lines
neurocnl/cnl/cnl_parser.py               473 lines
neurocnl/cnl/types.py                     16 lines
neurocnl/layers/layer1_validator.py       70 lines
neurocnl/layers/layer1_invariants.py     316 lines
neurocnl/layers/layer2_validator.py      241 lines
neurocnl/generation/nengo_generator.py   488 lines
neurocnl/generation/assertion_generator.py 400+ lines
neurocnl/export/__init__.py               54 lines
neurocnl/export/c_header_exporter.py     127 lines
```

---

## Quick Reference: Concept → Parser Pattern

| Concept | Pattern Match | Output Condition | Example |
|---------|------|---|---|
| threshold_firing | `(?:The\|A)\s+\w+\s+MUST\s+(?:fire\|emit a spike)\s+IF\s+membrane potential\s+(exceeds\|is below)\s+(\d+)` | "exceeds X" or "is below X" | "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.8" |
| refractory_period | `\w+\s+MUST\s+(?:NOT)?\s+(?:fire\|accept input)\s+DURING\s+refractory period\s+of\s+(\d+)\s+seconds` | "refractory period of X seconds" | "MUST NOT fire DURING the refractory period of 0.002 seconds" |
| membrane_potential_decay | `\w+\s+membrane potential\s+MUST\s+decay\s+WITH\s+time constant\s+(?:of\s+)?(\d+)\s+seconds` | "time constant of X seconds" | "MUST decay WITH time constant of 0.01 seconds" |
| synaptic_weight | `connection from\s+(.+?)\s+to\s+(.+?)\s+MUST\s+(?:have\|transmit)\s+WITH\s+synaptic weight of\s+(-?\d+(?:\.\d+)?)` | "synaptic weight of X" | "MUST have WITH synaptic weight of 1.5" |
| axonal_delay | `(?:synapse\|connection).*MUST.*delay.*of\s+(\d+(?:\.\d+)?)\s+(ms\|seconds)` | "transmission delay of X seconds" | "MUST have a transmission delay of 5ms" |
| stdp_learning | `synapse.*MUST.*(?:strengthen\|weaken)\s+IF.*spike.*(?:by\s+less than\s+(\d+)\s+(ms\|seconds))?` | "STDP learning...", timing window | "MUST strengthen IF pre-synaptic spike precedes post-synaptic by less than 20ms" |
| inhibitory_connection | `connection from\s+(.+?)\s+to\s+(.+?)\s+MUST.*inhibitory(?:\s+weight\s+of\s+(-?\d+))?` | "inhibitory weight of X" | "MUST be inhibitory with weight of -0.5" |
| population_coding | `(?:sensory\|motor) population.*MUST.*encode using\s+(\d+)\s+neurons(?:\s+with\s+(\d+)\s+dimensions)?` | "N neurons M dimensions" | "MUST encode input using 100 neurons" |
| network_topology | `network.*MUST.*contain\s+(excitatory\|inhibitory)\s+\w+\s+population\s+of\s+(\d+)` | "excitatory/inhibitory population of N neurons" | "MUST contain an inhibitory interneuron population of 30 neurons" |
| lateral_inhibition | `\w+.*MUST.*inhibit neighboring neurons\s+WITHIN radius of\s+(\d+)` | "radius of X" | "MUST inhibit neighboring neurons WITHIN radius of 2" |
| homeostatic_plasticity | `\w+.*MUST.*maintain average firing rate of\s+(\d+(?:\.\d+)?)\s+Hz` | "target rate of X Hz" | "MUST maintain average firing rate of 10 Hz" |
| neuromodulation | `\w+.*MUST.*modulate synaptic weight\s+BY factor of\s+(\d+)` | "modulation factor of X" | "Dopamine MUST modulate synaptic weight BY factor of 1.5" |
| population_coding_range | `\w+.*MUST.*encode.*WITH\s+(\d+)\s+degree range` | "range of X degrees" | "MUST encode stimulus orientation WITH 360 degree range" |
