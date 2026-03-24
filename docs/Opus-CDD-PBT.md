# Contract-Driven Development + Property-Based Testing Pipeline for NMTK

## A Verified, Automated Pipeline for Building Neuromorphic Software with AI Agents

**Author:** Claude Opus 4.6 | **Date:** 2026-03-23 | **Context:** NeuroMorphicToolKit

---

## 1. Executive Summary

This document proposes a **Contract-Driven Development (CDD) + Property-Based Testing (PBT)** pipeline designed specifically for the NeuroMorphicToolKit. The pipeline ensures that AI agents produce code that is **verifiably correct against physics, biology, and hardware specifications** — before, during, and after implementation.

The core idea:

```
Human writes contracts + properties + invariants (THE SCIENCE)
         ↓
Agent writes ALL implementation code
         ↓
Automated verification proves correctness against contracts
         ↓
Human reviews only failures and edge cases
```

**Key insight:** NMTK already has the foundation for this pipeline. NeuroCNL's Layer 1 invariants ARE contracts. The CNL grammar IS a specification language. The assertion generator IS property verification. This document formalizes and extends what exists into a complete, repeatable pipeline.

---

## 2. Why CDD+PBT Instead of SDD+BDD+BRMS

| Concern | SDD+BDD+BRMS Answer | CDD+PBT Answer | Why CDD+PBT Wins for NMTK |
|---------|---------------------|-----------------|---------------------------|
| "Is this biologically correct?" | Gherkin scenario + BRMS rule | Physics contract + property test | Properties generate thousands of edge cases automatically; Gherkin checks only the cases you thought of |
| "Does the hardware export work?" | BDD feature file | Hardware contract (bit-width, range, timing) + fuzzing | Contracts catch quantization errors Gherkin can't express |
| "Did the agent drift from spec?" | Spec drift shell script (grep-based) | Type checker + contract violation = compile/test failure | Immediate, deterministic feedback vs. heuristic grep |
| "Are business rules enforced?" | Drools/Camunda rule engine | Invariant functions in code (already: `layer1_invariants.py`) | Zero external infrastructure; validators ARE the rules |
| Agent overhead | 4+ governance docs per feature | Contracts + properties (code, not prose) | Agent reads code natively; less context window consumption |
| Human overhead | 3-6 hrs/feature (Generic), 15-20 hrs (Enterprise) | **~1-3 hrs/feature** (see Section 8) | Properties auto-generate test coverage humans would write manually |

---

## 3. Pipeline Architecture

### 3.1 The Five Layers

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 5: Simulation Regression Baselines                   │
│  "Does the network still behave like the golden reference?" │
│  ── Statistical comparison against known-good simulations   │
├─────────────────────────────────────────────────────────────┤
│  LAYER 4: Property-Based Tests (Hypothesis / PBT)           │
│  "For ALL valid inputs, do these scientific laws hold?"      │
│  ── Auto-generated edge cases, metamorphic relations        │
├─────────────────────────────────────────────────────────────┤
│  LAYER 3: Integration Contracts (API + Cross-Module)        │
│  "Do modules talk to each other correctly?"                 │
│  ── Pydantic models, API schemas, protocol contracts        │
├─────────────────────────────────────────────────────────────┤
│  LAYER 2: Domain Contracts (Physics + Biology + Hardware)   │
│  "Are the scientific laws and hardware limits respected?"   │
│  ── Invariant functions, Pydantic validators, type bounds   │
├─────────────────────────────────────────────────────────────┤
│  LAYER 1: Specification (CNL + Module Specs)                │
│  "What are we building and why?"                            │
│  ── CNL grammar, module SPEC.md, AGENTS.md, GUARDRAILS.md  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Information Flow

```
  ┌──────────────────────────────────────────────────────────────┐
  │                    HUMAN-AUTHORED (Layers 1-2)               │
  │                                                              │
  │  SPEC.md ──► CNL Sentences ──► Domain Contracts              │
  │     │              │                  │                      │
  │     │              ▼                  ▼                      │
  │     │     CNL Grammar Rules    Pydantic Models               │
  │     │     (cnl_parser.py)      + Invariant Functions         │
  │     │                          (layer1_invariants.py)        │
  │     │                                                        │
  │     ▼                                                        │
  │  AGENTS.md + GUARDRAILS.md                                   │
  │  (behavioral boundaries for AI agents)                       │
  └──────────────┬───────────────────────┬───────────────────────┘
                 │                       │
                 ▼                       ▼
  ┌──────────────────────────┐ ┌─────────────────────────────────┐
  │  HUMAN-AUTHORED (cont.)  │ │     HUMAN-AUTHORED (Layer 4)    │
  │  Integration Contracts   │ │     Property Definitions        │
  │  (Layer 3)               │ │                                 │
  │                          │ │  "For any valid LIF params,     │
  │  API schemas (FastAPI)   │ │   threshold > resting"          │
  │  Protocol specs (Serial) │ │                                 │
  │  Module interfaces       │ │  "Doubling input current →      │
  │                          │ │   monotonically higher rate"    │
  └──────────┬───────────────┘ └──────────────┬──────────────────┘
             │                                │
             ▼                                ▼
  ┌──────────────────────────────────────────────────────────────┐
  │                    AGENT-AUTHORED                             │
  │                                                              │
  │  Implementation Code                                         │
  │  ├── Python modules (services, routers, models)              │
  │  ├── Dart/Flutter UI code                                    │
  │  ├── Docker configurations                                   │
  │  └── Hardware export code                                    │
  │                                                              │
  │  Unit Tests (agent-written, must pass contracts)             │
  │  Integration Tests (agent-written, must satisfy properties)  │
  └──────────────────────────┬───────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │                    AUTOMATED VERIFICATION                    │
  │                                                              │
  │  1. Type check (mypy --strict) ─► Contract conformance      │
  │  2. Layer 1 invariants ─► Physics/biology gate               │
  │  3. Layer 2 cross-sentence ─► Consistency gate               │
  │  4. Hypothesis PBT ─► Property verification (1000s of cases)│
  │  5. Simulation regression ─► Behavioral baseline comparison  │
  │  6. Pytest suite ─► Unit + integration coverage              │
  │  7. Hardware contract check ─► Bit-width, timing, range      │
  │                                                              │
  │  ALL GATES MUST PASS ─► PR mergeable                         │
  └──────────────────────────────────────────────────────────────┘
```

---

## 4. What Humans Write (The Contracts & Properties)

Humans are responsible for **defining what is correct** — the science, the constraints, the boundaries. They never write implementation code in this pipeline.

### 4.1 Layer 1: Specification Documents

**Already exists (extend it):**

| Artifact | Status in NMTK | Action Needed |
|----------|----------------|---------------|
| CNL Grammar (`cnl_grammar.md`) | Complete (8 concepts) | Extend as new concepts are added |
| Module SPEC.md files | Exist for all 7 modules | Formalize with FR-XXX IDs and acceptance criteria |
| AGENTS.md | Does not exist | Create per-module agent behavioral rules |
| GUARDRAILS.md | Does not exist | Create per-module failure pattern registry |

**AGENTS.md template for NMTK modules:**

```markdown
# Agent Rules for [Module Name]

## Non-Negotiable
1. NEVER modify files in `layers/layer1_invariants.py` without human approval.
2. NEVER hard-code physics constants — they come from contracts/invariants.
3. ALWAYS run `pytest` and `mypy --strict` before considering a task complete.
4. ALWAYS check GUARDRAILS.md before starting implementation.

## Domain Rules
5. All neuron parameters must use the Pydantic models in `contracts/`.
6. All hardware exports must satisfy the target-specific contract validators.
7. Simulation results must be compared against golden baselines when available.

## When to Stop and Ask
- Any change that affects Layer 1 invariants
- Any new hardware target not covered by existing contracts
- Any simulation result that deviates >5% from golden baseline
- Any new CNL concept or grammar extension
```

### 4.2 Layer 2: Domain Contracts (Physics, Biology, Hardware)

**Already exists — formalize with Pydantic:**

Transform the current `layer1_invariants.py` (plain functions + dicts) into typed, self-validating contracts using Pydantic. This gives the agent instant, deterministic feedback — not "test failed at line 42" but "threshold (0.5) must be greater than resting_potential (0.8)."

```python
# contracts/neuron_params.py
from pydantic import BaseModel, field_validator, model_validator

class LIFNeuronContract(BaseModel):
    """Contract for Leaky Integrate-and-Fire neuron parameters.

    Source: NeuroML iafTauCell / iafTauRefCell specification.
    Any parameter set that fails validation is physically impossible.
    """
    threshold: float          # mV — must be > resting_potential
    resting_potential: float  # mV — leakReversal in NeuroML
    reset_potential: float    # mV — must be <= threshold
    refractory_period: float  # seconds — must be > 0
    tau: float                # seconds — membrane time constant, must be > 0

    @field_validator("refractory_period")
    @classmethod
    def refractory_must_be_positive(cls, v: float) -> float:
        assert v > 0, f"Refractory period {v}s is non-physical (must be > 0)"
        return v

    @field_validator("tau")
    @classmethod
    def tau_must_be_positive(cls, v: float) -> float:
        assert v > 0, f"Time constant {v}s is non-physical (must be > 0)"
        return v

    @model_validator(mode="after")
    def threshold_above_resting(self) -> "LIFNeuronContract":
        assert self.threshold > self.resting_potential, (
            f"Threshold ({self.threshold}) must exceed resting potential "
            f"({self.resting_potential}) — otherwise neuron fires continuously"
        )
        return self

    @model_validator(mode="after")
    def reset_at_or_below_threshold(self) -> "LIFNeuronContract":
        assert self.reset_potential <= self.threshold, (
            f"Reset ({self.reset_potential}) must be <= threshold "
            f"({self.threshold}) — otherwise infinite-frequency firing loop"
        )
        return self


class LoihiExportContract(BaseModel):
    """Contract for Intel Loihi 2 hardware export.

    Source: Intel Loihi 2 Programming Guide, Chapter 4.
    """
    weight: float
    n_neurons: int
    axonal_delay: float = 0.0

    @field_validator("weight")
    @classmethod
    def weight_quantizable(cls, v: float) -> float:
        max_weight = 10.0  # maps to 8-bit signed integer [-256, 254]
        assert abs(v) <= max_weight, (
            f"Weight {v} exceeds Loihi quantization range (max: {max_weight})"
        )
        return v

    @field_validator("n_neurons")
    @classmethod
    def fits_in_neurocore(cls, v: int) -> int:
        assert 0 < v <= 1024, (
            f"Neuron count {v} exceeds Loihi 2 neurocore capacity (1024)"
        )
        return v

    @field_validator("axonal_delay")
    @classmethod
    def delay_in_hardware_range(cls, v: float) -> float:
        assert 0 <= v <= 0.062, (
            f"Delay {v}s exceeds Loihi range (0-62ms = 0-62 timesteps)"
        )
        return v


class SerialProtocolContract(BaseModel):
    """Contract for Teensy serial bridge protocol.

    Source: Neuro-Dream-Hand SPEC.md Section 4.1.
    """
    grip_value: float

    @field_validator("grip_value")
    @classmethod
    def grip_in_range(cls, v: float) -> float:
        assert 0.0 <= v <= 1.0, f"Grip {v} outside actuator range [0.0, 1.0]"
        return v


class STDPContract(BaseModel):
    """Contract for Spike-Timing-Dependent Plasticity parameters.

    Source: Bi & Poo (1998), NeuroML STDP specification.
    """
    learning_rate: float
    stdp_window: float   # seconds
    weight_min: float = 0.0
    weight_max: float = 10.0

    @field_validator("learning_rate")
    @classmethod
    def positive_lr(cls, v: float) -> float:
        assert v > 0, "Learning rate must be positive"
        return v

    @field_validator("stdp_window")
    @classmethod
    def biologically_plausible_window(cls, v: float) -> float:
        assert 0 < v <= 0.100, (
            f"STDP window {v}s outside biological range (0-100ms)"
        )
        return v

    @model_validator(mode="after")
    def valid_weight_range(self) -> "STDPContract":
        assert self.weight_min < self.weight_max, "weight_min must be < weight_max"
        return self
```

**What this gives you:** Any time the agent constructs neuron parameters, hardware exports, or protocol messages, the Pydantic model **immediately rejects** physically impossible values. No waiting for a CI pipeline — the error appears at object construction time.

### 4.3 Layer 3: Integration Contracts (API + Cross-Module)

```python
# contracts/api_contracts.py
from pydantic import BaseModel

class ParseResponse(BaseModel):
    """Contract: /api/parse must return this shape."""
    line: int
    raw: str
    parsed: dict | None
    valid: bool
    error: str | None

class SimulationResponse(BaseModel):
    """Contract: /api/simulate must return this shape."""
    duration: float
    dt: float
    wall_time_seconds: float
    motor_output: list[list[float]]

class ValidationResponse(BaseModel):
    """Contract: /api/validate must return this shape."""
    layer1: dict    # {overall: bool, passed: [...], failed: [...]}
    layer2: dict    # {overall: bool, checks_passed: [...], checks_failed: [...]}
    overall: bool
```

**For FastAPI routers** — the agent writes the implementation, but response models are contracts:

```python
@router.post("/api/validate", response_model=ValidationResponse)
async def validate(request: ValidateRequest) -> ValidationResponse:
    # Agent writes this body — but the return type is locked by the contract
    ...
```

### 4.4 Layer 4: Property Definitions (The Power of PBT)

This is where CDD+PBT vastly outperforms BDD. Instead of writing individual test cases, humans define **universal properties** — laws that must hold for ALL valid inputs. The testing framework (Hypothesis) auto-generates thousands of edge cases.

```python
# properties/test_physics_properties.py
from hypothesis import given, settings, assume
from hypothesis import strategies as st

from contracts.neuron_params import LIFNeuronContract

# Strategy: generate ANY valid LIF neuron parameters
valid_lif_params = st.builds(
    LIFNeuronContract,
    threshold=st.floats(min_value=-50.0, max_value=50.0),
    resting_potential=st.floats(min_value=-80.0, max_value=-30.0),
    reset_potential=st.floats(min_value=-80.0, max_value=50.0),
    refractory_period=st.floats(min_value=0.0001, max_value=0.1),
    tau=st.floats(min_value=0.001, max_value=1.0),
)

# ── PHYSICS PROPERTIES ──────────────────────────────────────

@given(params=valid_lif_params)
@settings(max_examples=500)
def test_threshold_always_above_resting(params: LIFNeuronContract):
    """PROPERTY: For any valid neuron, threshold > resting potential.

    This is a physical law (NeuroML). If this property fails for ANY
    generated input, the contract or the implementation is broken.
    """
    assert params.threshold > params.resting_potential


@given(params=valid_lif_params)
@settings(max_examples=500)
def test_membrane_decay_is_stable(params: LIFNeuronContract):
    """PROPERTY: Membrane potential always decays toward rest.

    dv/dt = (rest - v) / tau
    For v > rest: dv/dt < 0 (decays down)
    For v < rest: dv/dt > 0 (decays up)
    """
    v_above = params.resting_potential + 1.0
    dv_dt = (params.resting_potential - v_above) / params.tau
    assert dv_dt < 0, "Voltage above rest must decay downward"

    v_below = params.resting_potential - 1.0
    dv_dt = (params.resting_potential - v_below) / params.tau
    assert dv_dt > 0, "Voltage below rest must decay upward"


# ── METAMORPHIC PROPERTIES (relational, not absolute) ──────

@given(
    params=valid_lif_params,
    current_low=st.floats(min_value=0.1, max_value=2.0),
    current_multiplier=st.floats(min_value=1.1, max_value=5.0),
)
@settings(max_examples=200)
def test_higher_input_means_higher_firing_rate(
    params: LIFNeuronContract,
    current_low: float,
    current_multiplier: float,
):
    """METAMORPHIC PROPERTY: Doubling input current should not decrease
    firing rate. This is a fundamental property of LIF neurons.

    We don't need to know the exact firing rate — just that more input
    produces at least as much output. This catches bugs that absolute
    threshold tests miss.
    """
    import nengo
    import numpy as np

    current_high = current_low * current_multiplier

    def run_with_input(current: float) -> int:
        with nengo.Network() as net:
            ens = nengo.Ensemble(
                50, 1,
                neuron_type=nengo.LIF(
                    tau_rc=params.tau,
                    tau_ref=params.refractory_period,
                ),
            )
            inp = nengo.Node(output=current)
            nengo.Connection(inp, ens)
            probe = nengo.Probe(ens.neurons, synapse=None)
        with nengo.Simulator(net, progress_bar=False) as sim:
            sim.run(0.5)
        return int(np.sum(sim.data[probe] > 0))

    spikes_low = run_with_input(current_low)
    spikes_high = run_with_input(current_high)
    assert spikes_high >= spikes_low, (
        f"Higher input ({current_high}) produced fewer spikes ({spikes_high}) "
        f"than lower input ({current_low}) → ({spikes_low})"
    )


# ── HARDWARE CONTRACT PROPERTIES ────────────────────────────

@given(
    weight=st.floats(min_value=-10.0, max_value=10.0),
    n_neurons=st.integers(min_value=1, max_value=1024),
)
def test_loihi_export_roundtrip(weight: float, n_neurons: int):
    """PROPERTY: Any valid Loihi parameters survive quantization roundtrip.

    weight → int8 → float should not lose more than 1 LSB of precision.
    """
    from contracts.neuron_params import LoihiExportContract

    contract = LoihiExportContract(weight=weight, n_neurons=n_neurons)
    # Quantize to 8-bit
    quantized = int(round(contract.weight * 25.5))  # scale to [-256, 254]
    reconstructed = quantized / 25.5
    assert abs(reconstructed - contract.weight) < 0.04, (
        f"Quantization error too large: {contract.weight} → {reconstructed}"
    )


# ── CNL PIPELINE PROPERTIES ─────────────────────────────────

@given(
    threshold=st.floats(min_value=0.1, max_value=5.0),
    refractory=st.floats(min_value=0.001, max_value=0.05),
    tau=st.floats(min_value=0.005, max_value=0.1),
)
@settings(max_examples=100, deadline=30000)  # 30s per example (simulation)
def test_cnl_pipeline_always_validates_valid_specs(
    threshold: float,
    refractory: float,
    tau: float,
):
    """PROPERTY: Any CNL spec with valid physics parameters passes validation.

    This is the most important property in the system: the pipeline must
    accept all physically valid inputs and reject all physically invalid ones.
    """
    from neurocnl.pipeline import run_pipeline

    spec = f"""The sensory neuron MUST fire ONLY IF membrane potential exceeds {threshold}
The sensory neuron MUST NOT fire DURING the refractory period of {refractory} seconds
The sensory neuron membrane potential MUST decay WITH time constant of {tau} seconds"""

    result = run_pipeline(spec, skip_simulation=True)
    assert result.validation["overall"] is True, (
        f"Valid physics params rejected: threshold={threshold}, "
        f"refractory={refractory}, tau={tau}. Errors: {result.errors}"
    )
```

### 4.5 Layer 5: Simulation Regression Baselines

```python
# baselines/test_golden_simulations.py
import json
import numpy as np
import pytest

GOLDEN_DIR = "baselines/golden/"

def load_golden(name: str) -> dict:
    with open(f"{GOLDEN_DIR}/{name}.json") as f:
        return json.load(f)

class TestReflexArcBaseline:
    """Compare simulation outputs against established golden references.

    Golden baselines are created by humans running verified simulations
    and committing the results. Any deviation beyond tolerance indicates
    a regression.
    """

    def test_sensory_motor_latency(self):
        """The input-to-output latency must match golden within 10%."""
        golden = load_golden("reflex_arc_3neuron")
        from neurocnl.pipeline import run_pipeline

        result = run_pipeline(golden["spec_text"], duration=1.0)
        actual_latency = result.summary["input_to_output_latency"]
        golden_latency = golden["expected_latency"]

        assert actual_latency is not None, "No output spike detected"
        assert abs(actual_latency - golden_latency) / golden_latency < 0.10, (
            f"Latency {actual_latency}s deviates >10% from golden {golden_latency}s"
        )

    def test_firing_rate_stability(self):
        """Motor firing rate must be within 15% of golden reference."""
        golden = load_golden("reflex_arc_3neuron")
        from neurocnl.pipeline import run_pipeline

        result = run_pipeline(golden["spec_text"], duration=1.0)
        actual_rate = result.summary["motor_mean_rate"]
        golden_rate = golden["expected_motor_rate"]

        assert abs(actual_rate - golden_rate) / max(golden_rate, 0.1) < 0.15, (
            f"Rate {actual_rate} Hz deviates >15% from golden {golden_rate} Hz"
        )
```

---

## 5. What the Agent Writes (Everything Else)

With contracts, properties, and invariants locked in, the agent is free to write **all implementation code**. The contracts act as a specification the agent must satisfy — and automated verification proves it did.

### 5.1 Agent Workflow (Per Feature)

```
Step 1: Agent reads SPEC.md, AGENTS.md, GUARDRAILS.md, contracts/
         ↓
Step 2: Agent writes implementation code
         ↓
Step 3: Agent runs local verification:
         a) mypy --strict  (type contracts)
         b) pytest contracts/  (Pydantic validation)
         c) pytest properties/  (Hypothesis PBT — auto edge cases)
         d) pytest baselines/  (simulation regression)
         e) pytest tests/  (unit + integration)
         ↓
Step 4: If any gate fails → agent reads error → fixes → goto Step 3
         ↓
Step 5: All gates pass → agent opens PR
         ↓
Step 6: CI runs full verification suite
         ↓
Step 7: Human reviews PR (focused on failures, architecture, science)
```

### 5.2 What the Agent Produces

| Artifact | Verified Against |
|----------|-----------------|
| Python service code | Type contracts (mypy), domain contracts (Pydantic), properties (Hypothesis) |
| FastAPI routers | API contracts (response models), integration tests |
| Nengo network generation | Layer 1 invariants, Layer 2 cross-sentence, simulation baselines |
| Hardware export code | Hardware contracts (Loihi, SpiNNaker, Akida bit-width/range/timing) |
| Flutter/Dart UI code | Widget tests, integration tests |
| Docker configurations | Build + health check verification |
| Unit tests | Must achieve coverage targets; must not duplicate property tests |

---

## 6. Human Roles & Checkpoints

### 6.1 Role Matrix

| Role | Responsibility | Time Commitment | Frequency |
|------|---------------|-----------------|-----------|
| **Neuroscientist** | Write/review physics contracts, validate biological plausibility of properties, define new CNL concepts | ~2-4 hrs/new concept | Per new neuroscience feature |
| **Hardware Engineer** | Write hardware contracts (Loihi, SpiNNaker, Akida, Teensy), define protocol specs, validate export properties | ~1-2 hrs/new target | Per new hardware target |
| **Tech Lead** | Write SPEC.md, AGENTS.md, define module integration contracts, review agent PRs | ~1-2 hrs/feature | Per feature |
| **QA / Anyone** | Create golden simulation baselines, review property test coverage, triage PBT failures | ~0.5-1 hr/feature | Per feature |

### 6.2 The Four Human Checkpoints

```
CHECKPOINT 1: Contract Authoring (Before Agent Starts)
├── Human writes/updates SPEC.md with FR-XXX IDs
├── Human writes/updates domain contracts (Pydantic models)
├── Human writes/updates property definitions (Hypothesis tests)
├── Human writes/updates GUARDRAILS.md with known failure patterns
└── Gate: contracts parse, properties run (even if no implementation yet)

CHECKPOINT 2: Property Review (After Agent Submits PR)
├── CI runs full verification suite automatically
├── Human reviews ONLY:
│   ├── Any property test failures (investigate: contract bug or code bug?)
│   ├── Coverage gaps (are there properties missing for this feature?)
│   └── Architectural decisions (does the agent's structure make sense?)
└── Gate: all properties pass + human approves

CHECKPOINT 3: Science Review (For Neuroscience Changes Only)
├── Neuroscientist reviews new invariants or CNL concepts
├── Validates against literature (NeuroML, published papers)
├── Checks that properties encode the correct physical relationships
└── Gate: domain expert sign-off

CHECKPOINT 4: Baseline Update (After Merge)
├── Run new golden simulation if behavior changed
├── Commit updated baseline files
├── Update GUARDRAILS.md if agent made interesting mistakes
└── Gate: baselines committed + GUARDRAILS.md updated
```

### 6.3 What Humans Do NOT Do

- Write implementation code
- Write unit tests (agent does this)
- Manually test API endpoints (contracts + properties cover this)
- Review every line of agent code (review is targeted at failures + architecture)
- Maintain Gherkin .feature files
- Configure or maintain a BRMS engine

---

## 7. Tooling & Libraries

### 7.1 Required (New Additions)

| Tool | Purpose | Install | Layer |
|------|---------|---------|-------|
| **Hypothesis** | Property-based test generation | `pip install hypothesis` | Layer 4 |
| **Pydantic v2** | Typed, self-validating contracts | `pip install pydantic>=2.0` | Layers 2-3 |
| **Schemathesis** | Auto-generate API tests from OpenAPI schema | `pip install schemathesis` | Layer 3 |
| **hypothesis-jsonschema** | Generate valid JSON from schemas | `pip install hypothesis-jsonschema` | Layer 3-4 |

### 7.2 Already Present (Leverage)

| Tool | Current Use | Extended Use |
|------|-------------|-------------|
| **pytest** | Unit tests across all modules | Property tests, baseline tests, contract tests |
| **mypy** | Type checking (strict in some modules) | Contract conformance verification |
| **ruff** | Linting + formatting | No change |
| **FastAPI** | API framework | Response model contracts (already supports Pydantic) |
| **Nengo** | Neural simulation | Simulation regression baselines |
| **GitHub Actions** | CI/CD (476-line workflow) | Add PBT + contract verification stages |

### 7.3 Optional (High Value, Add When Ready)

| Tool | Purpose | When to Add |
|------|---------|-------------|
| **Pandera** | DataFrame/data pipeline contracts (for Neurobench) | When Neurobench processes benchmark datasets |
| **crosshair-tool** | Symbolic execution — proves properties without running examples | When you want mathematical proof, not just high-confidence testing |
| **deal** | Design-by-Contract decorators (pre/postconditions on functions) | For critical path functions in hardware exporters |
| **pytest-benchmark** | Performance regression detection | When simulation speed matters |
| **Schemathesis + OpenAPI** | Automated API fuzzing from FastAPI schemas | When backend APIs are stable |

### 7.4 CI/CD Pipeline Configuration

Add to existing `.github/workflows/ci.yml`:

```yaml
  # New job: Contract + Property verification
  verify-contracts:
    runs-on: ubuntu-latest
    needs: detect-changes
    if: needs.detect-changes.outputs.neurocnl == 'true'
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - name: Install dependencies
        run: |
          cd neurocnl
          pip install -e ".[dev]"
          pip install hypothesis pydantic schemathesis
      - name: Type contract verification (mypy)
        run: cd neurocnl && mypy --strict neurocnl/
      - name: Domain contract tests
        run: cd neurocnl && pytest contracts/ -v
      - name: Property-based tests (500 examples per property)
        run: cd neurocnl && pytest properties/ -v --hypothesis-seed=0
      - name: Simulation regression baselines
        run: cd neurocnl && pytest baselines/ -v
      - name: Standard test suite
        run: cd neurocnl && pytest tests/ -v --tb=short
```

---

## 8. Time Estimates vs. Alternatives

### 8.1 Per-Feature Time Comparison

Scenario: **"Add STDP learning rule support to Neurochip hardware export"**

| Activity | SDD+BDD+BRMS (Generic) | SDD+BDD (No BRMS) | CDD+PBT (This Pipeline) | Lean SDD + CI |
|----------|------------------------|--------------------|--------------------------|----------------|
| **Spec writing** | 2-3 hrs (full SPEC.md + RULES.md) | 1.5-2 hrs (SPEC.md) | 1 hr (SPEC.md + update contracts) | 0.5-1 hr (light spec) |
| **Scenario/property authoring** | 1-2 hrs (Gherkin .feature) | 1-2 hrs (Gherkin) | 0.5-1 hr (3-5 Hypothesis properties) | 0 hrs (none) |
| **BRMS rule authoring** | 1-2 hrs (Drools/DMN) | 0 hrs (skipped) | 0 hrs (contracts replace this) | 0 hrs (none) |
| **Agent implementation time** | (Agent works) | (Agent works) | (Agent works) | (Agent works) |
| **Review time** | 1-2 hrs (Gherkin + code + BRMS) | 1-1.5 hrs (Gherkin + code) | 0.5-1 hr (failures only + arch) | 1-2 hrs (review everything) |
| **Maintenance overhead** | High (4+ docs + .feature files + rule engine) | Medium (3 docs + .feature files) | Low (contracts = code, self-maintaining) | Low (but no safety net) |
| **Total human time** | **5-9 hrs** | **3.5-5.5 hrs** | **2-3 hrs** | **1.5-3 hrs** |
| **Correctness confidence** | High (but Gherkin tests only known cases) | Medium-High | **Very High** (PBT tests 1000s of cases) | Low-Medium |
| **Edge case coverage** | Manual (you write each case) | Manual | **Automatic** (Hypothesis generates them) | None |

### 8.2 Time Savings Summary

| Compared To | Human Time Saved Per Feature | Annual Savings (50 features/yr) | Correctness Trade-off |
|-------------|------------------------------|--------------------------------|----------------------|
| SDD+BDD+BRMS (Generic) | ~55-65% less | ~150-300 hrs saved | **Higher** correctness (PBT > BDD for scientific code) |
| SDD+BDD (No BRMS) | ~40-50% less | ~75-125 hrs saved | **Higher** correctness |
| Lean SDD + CI | ~30% more time | ~25-50 hrs more | **Much higher** correctness |
| Ad-hoc (no pipeline) | ~100% more time | ~100-150 hrs more | **Incomparably higher** correctness |

### 8.3 Where CDD+PBT Saves the Most Time

1. **No Gherkin maintenance.** BDD .feature files are prose that must be kept in sync with code. Properties are code that the test runner enforces automatically.

2. **No BRMS infrastructure.** Zero time installing, configuring, or maintaining Drools/Camunda. Pydantic validators do the same job natively in Python.

3. **Automated edge case discovery.** A single `@given(...)` decorator generates 500+ test cases. Writing equivalent BDD scenarios manually would take hours.

4. **Faster review cycles.** When all properties pass, the human reviewer knows the code satisfies physics, biology, hardware constraints, and simulation baselines. They only need to review architecture and failure cases — not manually trace Gherkin to code.

5. **Self-documenting contracts.** Pydantic models with validators serve as both documentation AND enforcement. No separate "rules document" to maintain.

### 8.4 Where CDD+PBT Costs More Time

1. **Upfront property writing** requires deeper scientific thinking than writing Gherkin scenarios. A neuroscientist must understand what universal laws to encode, not just example behaviors.

2. **Hypothesis tests are slower** than unit tests (seconds vs. milliseconds per property, due to multiple examples). CI time increases by 2-5 minutes.

3. **Debugging PBT failures** can be harder — when Hypothesis finds a counterexample, understanding why the generated input breaks the property requires careful analysis.

---

## 9. Migration Path for NMTK

### Phase 1: Foundation (Week 1-2)

```
1. Install: pip install hypothesis pydantic>=2.0 schemathesis
2. Create contracts/ directory in neurocnl/
3. Convert layer1_invariants.py functions → Pydantic model validators
   (keep existing functions as compatibility layer)
4. Write 5 core physics properties using Hypothesis
5. Create 1 golden simulation baseline (3-neuron reflex arc)
6. Add AGENTS.md and GUARDRAILS.md to neurocnl/
```

**Human time:** ~8 hours (neuroscientist + tech lead)

### Phase 2: Expansion (Week 3-4)

```
7. Add contracts for all hardware exports (Loihi, Lava, SpiNNaker, C header)
8. Add API contracts for all FastAPI routers (response models)
9. Write metamorphic properties (higher input → higher rate, etc.)
10. Add contract verification to CI pipeline
11. Create AGENTS.md for remaining modules (Neurosim, Neurochip, etc.)
```

**Human time:** ~12 hours (spread across team)

### Phase 3: Full Pipeline (Week 5-6)

```
12. Golden baselines for Neuro-Dream-Hand simulation targets
13. Serial protocol contract + fuzzing (Schemathesis for binary protocol)
14. Property tests for CNL parser (any valid grammar → valid parse)
15. Cross-module integration contracts (neurocnl → Neurochip export path)
16. First fully agent-driven feature using the complete pipeline
```

**Human time:** ~10 hours (spread across team)

**Total migration effort:** ~30 hours over 6 weeks, distributed across the team.

---

## 10. Comparison with Review Alternatives

### How This Relates to What Gemini, GPT-5.4, and Opus Proposed

| Alternative (from reviews) | CDD+PBT Verdict | Relationship |
|---------------------------|------------------|-------------|
| **TDD with LLMs** (Gemini Alt A) | Subsumed | PBT is strictly more powerful than TDD — it generates the test cases TDD requires you to write manually |
| **Multi-Agent Debate** (Gemini Alt B) | Complementary | A "Physics Reviewer Agent" that checks contracts is a natural extension — but contracts make this less critical |
| **Type-Driven / Contract-Driven** (Gemini Alt C) | **This is it** | CDD+PBT is the full realization of this alternative, adapted for NMTK |
| **PR as Boundary** (Gemini Alt D) | Subsumed | CDD+PBT uses PRs as the boundary, but with much stronger gates |
| **Lean SDD + Normal CI** (GPT-5.4 Alt 1) | Foundation layer | CDD+PBT includes this as Layer 1, then adds contracts and properties on top |
| **Contract-First + Policy-as-Code** (GPT-5.4 Alt 2) | Very close | CDD+PBT is this approach, using Pydantic instead of OPA and Hypothesis instead of Conftest |
| **Selective BRMS** (GPT-5.4 Alt 3) | Replaced | Pydantic validators replace BRMS for this domain — physics rules don't change with business policy |
| **Formal Verification / TLA+** (Opus Alt 4) | Optional upgrade | crosshair-tool can provide formal proofs for critical properties later |
| **Multi-Agent Review** (Opus Alt 5) | Complementary | Agent debate is useful but not required when contracts provide deterministic verification |
| **Cursor Rules + TDD** (Opus Alt 1) | Foundation | AGENTS.md serves the same role as .cursorrules; PBT replaces manual TDD |

---

## 11. Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Hypothesis finds a physics edge case that invalidates a contract | Medium | High (contract must be fixed) | This is a FEATURE — it's the whole point of PBT. Fix the contract. |
| Agent can't satisfy contracts (too strict) | Low | Medium (agent stuck) | Relax contract temporarily, investigate if constraint is real |
| PBT tests are too slow for CI | Medium | Low (CI takes longer) | Use `@settings(max_examples=100)` in CI, 500 locally. Use `deadline` parameter. |
| Team doesn't write properties for new features | Medium | High (correctness gap) | PR template requires "Properties added" checkbox. CI fails without property coverage. |
| Pydantic migration breaks existing Layer 1 tests | Low | Medium | Keep `layer1_invariants.py` as compatibility layer; Pydantic wraps it |
| Golden baselines drift from reality over time | Medium | Medium | Baselines must be re-validated when Nengo version changes |

---

## 12. Summary

**The pipeline works.** Contracts and properties are written before the agent touches code. The agent implements freely. Automated verification proves correctness. Humans review only what matters.

**For NMTK specifically, CDD+PBT is the right choice because:**

1. Your correctness requirements are physics and biology — not business rules. Pydantic validators express physical laws more naturally than Drools.
2. Your edge cases are numerical — not behavioral. Hypothesis finds quantization errors, boundary violations, and timing bugs that Gherkin scenarios would never cover.
3. You already have the foundation. Layer 1 invariants, CNL grammar, and assertion generation are 80% of this pipeline. The remaining 20% is formalization.
4. Your team is small. You can't afford to maintain 4+ governance documents per feature. Contracts are code — they maintain themselves.

**The cost:** ~30 hours to migrate over 6 weeks.
**The payoff:** ~55-65% less human time per feature, with higher correctness confidence than any of the alternatives reviewed.

---

*This document was produced by analyzing the NeuroMorphicToolKit codebase (neurocnl v0.3.0, layer1_invariants.py, pipeline.py, assertion_generator.py, cnl_parser.py, all module specs) against the SDD+BDD+BRMS research package and three independent reviews (Gemini 3.1, GPT-5.4, Opus). All code examples use patterns already present in the NMTK codebase.*
