# Agentic Execution Guide

> This section is written for execution by an agentic workflow such as Claude Code or GitHub Copilot CLI. Each task is self-contained with explicit inputs, outputs, success criteria, and constraints. No task should be started before its dependencies are confirmed complete.

---

## How to Use This Section

Run tasks sequentially. Each task block contains:
- **Prompt** — what to give the agent verbatim
- **Input** — what must exist before the agent starts
- **Output** — what the agent must produce
- **Gate** — the condition that must be true before moving to the next task

If a gate fails, do not proceed. Return to the current task, adjust inputs or constraints, and retry.

---

## Task 0 — Environment Setup

**Prompt:**
```
Install the following Python packages in a new virtual environment called `neurocnl-env`:
nengo, nengo-loihi, neuroml, pytest, mujoco, numpy, lxml

Verify each installs without conflict. Output a requirements.txt and a brief install log confirming
each package version. Flag any version conflicts explicitly.
```

**Input:** Clean Python 3.10+ environment

**Output:**
- `requirements.txt`
- `install_log.txt` confirming versions

**Gate:** All packages import without error. Run `python -c "import nengo, neuroml, mujoco"` and confirm no exceptions.

---

## Task 1 — CNL Grammar Definition

**Prompt:**
```
Create a file called `cnl_grammar.md` that defines a Controlled Natural Language (CNL) grammar
for describing a simple sensory-motor reflex arc in neuromorphic computing.

Rules for the grammar:
- Every sentence must use one of these verbs: MUST, MUST NOT, ONLY IF, DURING, AFTER, WITH
- Every sentence must be parseable into a subject, condition, and action
- The grammar must cover exactly these four biological concepts:
    1. Threshold firing: when a neuron emits a spike
    2. Refractory period: when a neuron ignores input
    3. Membrane potential decay: how voltage changes over time
    4. Synaptic weight: how strongly one neuron influences another

For each concept, provide:
- 3 to 5 valid example sentences
- 2 invalid example sentences with an explanation of why they are invalid
- The formal mapping (what Nengo construct this sentence compiles to)

Do not add any concepts beyond these four. Do not allow free-form sentences.
```

**Input:** None

**Output:** `cnl_grammar.md`

**Gate:** The grammar contains exactly 4 concepts, each with valid examples, invalid examples, and a Nengo mapping. A human domain expert must review and sign off before Task 2 starts.

---

## Task 2 — Layer 1 Invariants File

**Prompt:**
```
Create a file called `layer1_invariants.py` that defines physical invariants for a
leaky integrate-and-fire (LIF) neuron model, sourced from NeuroML's LIF definition.

Each invariant must be a Python function that:
- Accepts a dictionary of neuron parameters as input
- Returns True if the parameters are physically valid, False otherwise
- Includes a docstring explaining the biological law it encodes

Required invariants:
1. Threshold must be greater than resting membrane potential
2. Refractory period must be greater than zero
3. Time constant tau must be greater than zero
4. Reset potential must be less than or equal to threshold
5. Membrane potential must not decrease during active depolarization

Each function must include a reference to the NeuroML parameter name it validates.
Write a pytest test for each invariant covering at least one pass case and one fail case.
```

**Input:** `cnl_grammar.md` (confirmed complete from Task 1)

**Output:**
- `layer1_invariants.py`
- `test_layer1_invariants.py`

**Gate:** `pytest test_layer1_invariants.py` passes with zero failures.

---

## Task 3 — CNL Parser

**Prompt:**
```
Create a Python module called `cnl_parser.py` that parses sentences written in the CNL
grammar defined in `cnl_grammar.md`.

The parser must:
- Accept a plain text string as input
- Identify which of the four grammar concepts (threshold firing, refractory period,
  membrane potential decay, synaptic weight) the sentence describes
- Extract the subject, condition, and action as structured fields
- Return a Python dictionary with keys: concept, subject, condition, action, raw
- Raise a ParseError with a clear message for any sentence that does not match the grammar
- Not use an LLM for parsing — use regex or a grammar library only

Write a test file `test_cnl_parser.py` using the valid and invalid examples from
`cnl_grammar.md` as test cases.
```

**Input:** `cnl_grammar.md`

**Output:**
- `cnl_parser.py`
- `test_cnl_parser.py`

**Gate:** `pytest test_cnl_parser.py` passes. All valid examples parse correctly. All invalid examples raise ParseError.

---

## Task 4 — Layer 1 Validator

**Prompt:**
```
Create a Python module called `layer1_validator.py` that checks parsed CNL sentences
against the physical invariants defined in `layer1_invariants.py`.

The validator must:
- Accept the output of `cnl_parser.py` (a list of parsed sentence dictionaries)
- Accept a dictionary of neuron parameters (tau, threshold, reset_potential, refractory_period)
- Run every relevant invariant from `layer1_invariants.py` against the parsed spec
- Return a validation report as a dictionary with keys:
    passed: list of invariant names that passed
    failed: list of invariant names that failed, each with a reason string
    overall: True if all passed, False if any failed

Write `test_layer1_validator.py` with at least:
- One test where all invariants pass
- One test where threshold invariant fails
- One test where refractory period invariant fails
```

**Input:**
- `cnl_parser.py`
- `layer1_invariants.py`

**Output:**
- `layer1_validator.py`
- `test_layer1_validator.py`

**Gate:** `pytest test_layer1_validator.py` passes with zero failures.

---

## Task 5 — Nengo Code Generator

**Prompt:**
```
Create a Python module called `nengo_generator.py` that translates a validated CNL spec
into a working Nengo network for a sensory-motor reflex arc.

The generator must:
- Accept the output of `cnl_parser.py` (validated list of parsed sentence dictionaries)
- Accept a neuron parameter dictionary (tau, threshold, reset_potential, refractory_period,
  synaptic_weight)
- Generate a Nengo network with:
    - One sensory input ensemble
    - One motor output ensemble
    - A connection between them using the parsed synaptic weight
    - LIF neuron parameters set from the parsed spec
- Return the nengo.Network object (do not run the simulation in this module)
- Raise a GeneratorError if any required concept is missing from the parsed spec

Write `test_nengo_generator.py` that:
- Builds a network from a minimal valid CNL spec
- Confirms the network contains the expected ensembles and connections
- Confirms neuron parameters match the input spec
```

**Input:**
- `cnl_parser.py`
- `layer1_validator.py`

**Output:**
- `nengo_generator.py`
- `test_nengo_generator.py`

**Gate:** `pytest test_nengo_generator.py` passes. The generated network runs for 1 second in Nengo's default simulator without errors.

---

## Task 6 — Layer 3 Assertion Generator

**Prompt:**
```
Create a Python module called `assertion_generator.py` that uses the Anthropic API
to generate a pytest assertion suite from a validated CNL spec.

The module must:
- Accept the output of `cnl_parser.py` as input
- Send the parsed spec to claude-sonnet-4-20250514 with a system prompt that instructs it
  to generate pytest test functions only — no prose, no explanation
- Each generated test must:
    - Be a standalone pytest function
    - Test exactly one behavioral rule from the spec
    - Include a docstring stating which CNL sentence it validates
    - Use only nengo and numpy as dependencies
- Write the generated tests to `test_layer3_assertions.py`
- After writing, run a syntax check with `py_compile` and raise an error if it fails

The system prompt must explicitly forbid:
- Tests that always pass
- Tests that test implementation details not present in the CNL spec
- Any use of mock objects
```

**Input:**
- `cnl_parser.py`
- Anthropic API key in environment as `ANTHROPIC_API_KEY`

**Output:**
- `assertion_generator.py`
- `test_layer3_assertions.py` (generated)

**Gate:** `py_compile test_layer3_assertions.py` succeeds. A human reviews the generated assertions and confirms each maps to a real CNL sentence before Task 7 starts.

---

## Task 7 — End-to-End Simulation

**Prompt:**
```
Create a script called `run_simulation.py` that executes the full pipeline from CNL spec
to MuJoCo simulation and produces a validation report.

The script must:
1. Accept a CNL spec file path as a command-line argument
2. Parse the spec using `cnl_parser.py`
3. Validate against Layer 1 using `layer1_validator.py` — halt and print report if validation fails
4. Generate a Nengo network using `nengo_generator.py`
5. Run the Nengo network for 1 second using nengo.Simulator
6. Pass the motor output signal to a MuJoCo pendulum environment (use the InvertedPendulum-v4
   model from mujoco) as a control signal
7. Run the MuJoCo environment for 200 steps
8. Run `test_layer3_assertions.py` against the simulation output using pytest
9. Write a JSON report to `simulation_report.json` containing:
    layer1_validation: the validation report from step 3
    simulation_duration: total seconds simulated
    mujoco_steps: number of steps completed
    assertions_passed: number of pytest assertions passed
    assertions_failed: number of pytest assertions failed
    overall_pass: True only if layer1 passed AND all assertions passed

The script must exit with code 0 on overall pass and code 1 on any failure.
```

**Input:**
- All modules from Tasks 1–6 confirmed passing
- A CNL spec file for the reflex arc (write a minimal one as `reflex_arc.cnl` if none exists)

**Output:**
- `run_simulation.py`
- `simulation_report.json`

**Gate:** `python run_simulation.py reflex_arc.cnl` exits with code 0. `simulation_report.json` shows `overall_pass: true`.

---

## Task 8 — Repository Structure and README

**Prompt:**
```
Organise all files produced in Tasks 0–7 into the following directory structure:

neurocnl/
  cnl/
    cnl_grammar.md
    cnl_parser.py
    test_cnl_parser.py
  layers/
    layer1_invariants.py
    test_layer1_invariants.py
    layer1_validator.py
    test_layer1_validator.py
  generation/
    nengo_generator.py
    test_nengo_generator.py
    assertion_generator.py
  simulation/
    run_simulation.py
    reflex_arc.cnl
  requirements.txt
  README.md

Write README.md that contains:
- One paragraph describing what this project does
- Prerequisites section (Python version, environment setup command)
- Usage section showing exactly how to run the full pipeline with one command
- A section called "Extending the CNL" explaining how to add a new grammar concept
  (point to cnl_grammar.md, cnl_parser.py, and layer1_invariants.py as the three files to edit)
- No marketing language, no roadmap, no future work section
```

**Input:** All files from Tasks 0–7

**Output:** Organised `neurocnl/` directory with `README.md`

**Gate:** `pytest neurocnl/` discovers and passes all tests. `python neurocnl/simulation/run_simulation.py neurocnl/simulation/reflex_arc.cnl` runs successfully from the repo root.

---

## Execution Notes for the Agent

- Run all tests after every task before marking it complete. Do not skip the gate.
- If a gate fails, report the failure explicitly with the error output. Do not silently proceed.
- Do not install packages outside `neurocnl-env`.
- Do not modify `layer1_invariants.py` after Task 4 without re-running all downstream tests.
- The CNL grammar in `cnl_grammar.md` is the source of truth. If generated code contradicts it, fix the code, not the grammar.
- Tasks 1 and 6 have human review gates. Pause and wait for explicit confirmation before continuing.
