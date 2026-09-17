# Neuromorphic Spec Translation Layer
### A Realistic Build Plan — March 2026

---

## Core Premise

Treat the behavioral spec as the source of truth. Code and hardware configurations are compilation artifacts. The spec is what humans and agents reason about.

This is the same paradigm shift that OpenAPI/Swagger made for REST APIs — the spec became the canonical artifact that generated server stubs, client SDKs, and documentation simultaneously. The goal here is identical, applied to neuromorphic models.



## The Architecture: Three Layers

### Layer 1 — Physical Invariants (The Constitution)

Non-negotiable biological and physical laws. Expressed as formal constraints that can be automatically checked. Nobody edits these without triggering a violation. Borrowed directly from NeuroML's existing ontology rather than invented from scratch.

*This layer is the validation backstop. No compiled output is accepted if it violates Layer 1.*

### Layer 2 — Behavioral Spec (The Human Layer)

Written in Controlled Natural Language (CNL). Constrained enough to be unambiguous, loose enough for a neuroscientist to write without a CS degree. This is the layer humans review, version-control, and debate. It is also what AI agents receive as instruction.

Example statements:

```
A neuron MUST emit a spike IF membrane potential exceeds threshold.
A neuron MUST NOT accept input DURING the refractory period.
Membrane potential MUST decay exponentially with time constant τ.
```

### Layer 3 — Validation Assertions

Auto-generated from Layer 2 by an LLM, then human-ratified. A formal test suite in readable language. The LLM does not generate hardware code until every assertion passes against Layer 1. The assertion format is designed to feel familiar to engineers coming from PyTorch or TensorFlow.

Hardware-specific compilation happens only after Layer 3 clears.

---

## How Existing Tools Fit In

### Nengo

Nengo sits at roughly the right abstraction level — above hardware, below pure neuroscience notation. It has NengoLoihi as a backend, meaning code written in Nengo can be compiled to Intel's Loihi without touching the hardware layer directly.

Compilation target:

```
CNL Spec → Nengo Python → NengoLoihi backend → Loihi hardware
```

The task is writing a CNL that compiles to Nengo's API — a much narrower, more achievable problem. Nengo's API is clean enough that an LLM can generate it reliably from structured input.

### MuJoCo

MuJoCo provides a closed validation loop. The neuromorphic controller needs an environment to act in:

```
Neuromorphic SNN (CNL spec → Nengo) → controls agent → simulated in MuJoCo
```

Without MuJoCo, the spec can only be validated against itself. With it, the spec is validated against physical behavior in simulation — does the arm move correctly, does it overshoot, does the refractory rule hold under load.

### NeuroML

Provides the existing neuroscience ontology that Layer 1 is built on. No need to reinvent the biological constraint vocabulary. The CNL in Layer 2 maps to NeuroML constructs rather than raw mathematics.

---

## The Full Compilation Pipeline

```
CNL Spec (Layer 2)
  ↓  LLM translation
Nengo Python model
  ↓  checked against Layer 1 (NeuroML invariants)
Validation Assertions (Layer 3) — human-ratified
  ↓  NengoLoihi backend
Loihi hardware configuration
  ↓  physical output tested in
MuJoCo simulation
  ↓  results verified against Layer 1
```

---

## First Use Case: The Reflex Arc

Start with one use case only. The CNL grammar is shaped by the domain it describes — starting broad means the language tries to accommodate too many constraint types at once and ends up serving none well.

The correct first use case is a simple sensory-motor reflex arc: sensory input driving a motor response.

| Property | Why It Works Here |
|---|---|
| Neuroscience | Well-understood, minimal ambiguity |
| Engineering | Documented Nengo implementation exists |
| Validation | MuJoCo can simulate the physical output |
| CNL Scope | Only threshold rules, refractory constraints, basic synaptic weighting |

Once this works end-to-end, it becomes the template for expanding the CNL to more complex cases: learning rules, network topology, multi-region circuits.

---

## Build Sequence

### Step 1 — Define the CNL Grammar for the Reflex Arc Only

The hardest step. Define exactly which English sentence structures map to which formal constructs. The grammar must be tight enough that an LLM cannot produce plausible-sounding but physically wrong output.

**Deliverable:** A documented grammar with ~15–20 sentence patterns covering threshold firing, refractory constraints, and basic synaptic rules.

### Step 2 — Build the Layer 1 → Layer 2 Validator

An LLM-assisted check that a behavioral spec does not contradict the NeuroML physical invariants. This is the core safety mechanism. Without it the system is a prompt wrapper, not a spec layer.

**Deliverable:** A validation function that accepts a CNL spec and returns pass/fail with specific violation messages.

### Step 3 — Prototype the Layer 2 → Layer 3 Pipeline

LLM takes the CNL spec and generates testable assertions. Human reviews them. Format the assertions to resemble something an ML engineer already recognizes — pytest-style or similar.

**Deliverable:** Auto-generated assertion suite for the reflex arc spec, covering the key behavioral rules.

### Step 4 — Validate Against Nengo Simulation

Compile the CNL spec through Nengo (not Loihi yet) and run the MuJoCo simulation. Prove that the spec produces correct physical behavior before touching hardware.

**Deliverable:** A working end-to-end pipeline from CNL spec to simulated physical output, with all Layer 3 assertions passing.

### Step 5 — Hardware Compilation

Only after Step 4 is stable: compile via NengoLoihi to Loihi. Verify the same assertions hold on hardware that held in simulation.

**Deliverable:** Confirmed spec-to-hardware pipeline for the reflex arc use case.

---

## What Is Explicitly Out of Scope

- Your own neuroscience ontology — use NeuroML
- Your own hardware compiler — use Lava / NengoLoihi
- A general-purpose SDD platform
- Support for multiple neuron models in v1
- A freeform natural language interface — the CNL is constrained, not open-ended

---

## The Honest Risk

The CNL grammar definition in Step 1 is where this most likely breaks down.

| Failure Mode | Consequence |
|---|---|
| Grammar too loose | LLM hallucinates valid-sounding but physically wrong specs. Layer 1 validator catches some, not all. |
| Grammar too rigid | Neuroscientists won't use it. Adoption fails regardless of technical correctness. |

There is no clean solution to this tradeoff. It requires iterative testing with actual domain experts — neuroscientists who can read the CNL output and identify when it is physically wrong but grammatically valid.

**Everything else in this plan is an engineering problem with known tools and known solutions. The CNL grammar is the only genuine unknown.**

---

---
