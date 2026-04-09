# Contract-Driven & Property-Based Testing (CDD-PBT) Pipeline
### Tailored for the NeuroMorphic Toolkit (NMTK)

This document outlines the pipeline for governing AI coding agents using **Contract-Driven Development (CDD)** and **Property-Based Testing (PBT)**. This replaces semantic/text-based guardrails (like BDD/Gherkin and BRMS) with strict mathematical and structural boundaries.

---

## 1. The Pipeline: Contract-First, Agent-Second

The pipeline operates on a strict sequence where humans define the boundaries (physics, biology, hardware specs) mathematically, and the AI agent is trapped in an automated loop until it satisfies those bounds.

### Phase 1: Boundary Definition (Human-Led)
1. **Define Contracts (Schemas):** Human writes strict data models representing inputs and outputs. For example, using Pydantic to ensure a `SpikeTrain` never exceeds maximum hardware frequency.
2. **Define Invariants (Property Tests):** Human writes property-based tests (e.g., using Hypothesis) that throw thousands of randomized edge cases (fuzzing) at an empty interface. These tests enforce the laws of physics and hardware continuity.
3. **Commit Bounds:** The contracts and failing tests are committed to the branch.

### Phase 2: Autonomous Implementation (AI-Led)
1. **Agent Prompting:** The AI Agent is pointed at the empty functions and told: *"Implement this logic until all property tests pass."*
2. **The Execution Loop:**
   - Agent writes implementation.
   - Orchestrator runs type-checking (`mypy`) and property tests (`pytest` + `hypothesis`).
   - If a test fails, the stack trace and failing randomized input are piped directly back to the Agent.
   - Agent self-corrects the code.
3. **Pass Gate:** The loop continues autonomously without human intervention until the code compiles, type-checks, and sustains 10,000+ randomized fuzz tests without breaking physics boundaries.

### Phase 3: Review & Merge (Human-Led)
1. The AI opens a Pull Request with the passing implementation.
2. Human reviews the *approach, algorithmic efficiency, and readability*, knowing structurally that the logic complies with domain constraints.

---

## 2. Human Roles & Responsibilities

In this pipeline, the human shifts entirely from writing syntax to acting as the **Domain Architect** and **Constraint Designer**.

| Role | Responsibilities | Time Spent On |
| :--- | :--- | :--- |
| **Neuroscientist / Hardware Engineer** | - Defines biological constraints and hardware specs.<br>- Writes `Pydantic` schemas.<br>- Writes `Hypothesis` invariant rules. | Conceptualizing the actual science and formulating constraints. |
| **Tech Lead / Code Reviewer** | - Reviews the AI's PR for readability, security, and integration architecture (the "art" of the code). | Reading Code (not writing it). |
| **AI Agent** | - Writes all business logic, algorithms, array manipulations, and boilerplate. | Syntax, iteration, debugging logic. |

---

## 3. Required Tooling & Libraries

To implement this on the NMTK stack (heavy Python usage for simulation and hardware abstraction), the following stack is required:

### The Constraints Stack
* **`Pydantic`**: For runtime validation of data structures (e.g., hardware pin bounds, membrane voltage limits).
* **`mypy` (Strict Mode)**: For static type analysis. Ensures the agent cannot pass an `int` where a `torch.Tensor` is expected.

### The Testing Stack
* **`pytest`**: The standard test runner.
* **`Hypothesis`**: Property-based testing framework for Python. Generates randomized inputs to break the AI's code mathematically.

### The Agentic Orchestration Stack
* **`Aider` (CLI)**: Recommended. It natively supports the "run tests and auto-heal based on stderr" loop.
* *Alternative:* **GitHub Copilot / Cline / Cursor**: Used interactively by the engineer, leaning on the test suite for immediate feedback.
* *Alternative:* **Custom CI/CD Loop (GitHub Actions)**: A script that runs `pytest`, captures failure logs, sends them to the Anthropic/OpenAI API, commits the fixes, and repeats up to 5 times.

---

## 4. Time Savings Estimation vs. Previous Pipelines

Comparing this CDD-PBT pipeline against the heavyweight **SDD + BDD (Gherkin) + BRMS (Drools)** pipeline proposed in the previous research:

| Metric | SDD/BDD/BRMS Pipeline | CDD-PBT Pipeline | Net Savings |
| :--- | :--- | :--- | :--- |
| **Setup & Boilerplate** | High (Maintaining `.feature` lists, configuring BRMS engines) | Low (Just Python files and `@given` decorators) | **~80% reduction** in setup time |
| **Human Constraint Writing** | 2-3 Hours (Translating biology to Gherkin & Drools rules) | 30-45 Mins (Writing native Python contracts/formulas) | **~75% reduction** in constraint definition |
| **AI Debugging / Hallucination Rework** | 1-2 Hours (Agent gets confused by text-heavy specs) | 0.5 Hours (Typing/Math failures give exact debug strings) | **~60% faster** AI auto-healing |
| **Total Hands-on Human Time (per Feature)** | **~3 to 6 Hours** | **~1 to 2 Hours** | **🚀 ~66% Time Saved** |

### Qualitative Advantages
1. **Zero "Translation Loss":** You don't have to translate differential equations into English text for a BDD engine, just to have an AI translate it back into Python. You write Python math; AI writes Python logic.
2. **Infinite Coverage:** A human writing BDD scenarios writes maybe 5 test cases. `Hypothesis` will generate 50,000 test cases while the human is getting coffee, uncovering edge cases the AI hallucinated that humans would never think of.
3. **No Domain Mismatch:** NMTK is a scientific toolkit. CDD-PBT feels native to scientists and data engineers; Gherkin/Drools feels like enterprise Java bureaucracy.
