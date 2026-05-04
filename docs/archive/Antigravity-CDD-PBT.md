# Antigravity's CDD-PBT Pipeline for Scientific Computing

**Contract-Driven and Property-Based Testing (CDD-PBT)** replaces the heavy enterprise SDD/BDD/BRMS stack with a mathematically rigorous, exhaustive, and agent-native pipeline tailored for the NeuroMorphicToolKit (NMTK) and hardware engineering invariants.

---

## 1. Where Humans Come Into Play (The Human Role)

In the CDD-PBT pipeline, human effort shifts entirely away from implementation and micromanagement toward **invariant architecture** and **constraint design**.

### The Architect (Human)
*   **Defining the Intent (`SPEC.md`):** Writing the natural language intent and architectural diagrams.
*   **Defining the Math/Physics (Property Tests):** Translating the biological/physics rules into parameterized tests. You write *properties* instead of static *Given/When/Then* scenarios. You define the bounds of the universe your simulation runs in.
*   **Defining the Data Boundaries (Contracts):** Writing strict type schemas or interfaces (e.g., this input *must* be an array of positive floats, this output *must* conform to this specific memory layout).

### The Coder (Agent)
*   **Writing the Implementation:** Generating the actual Python/Dart/C++ logic.
*   **Auto-Correction Loop:** Running the property framework. If the framework finds a randomized edge case that breaks the contract, the agent reads the exact failing inputs, self-corrects the logic, and tries again.

### The Reviewer (Human)
*   **Code Reviewing the Final Output:** Because the agent is mathematically proven to have satisfied all invariants across thousands of randomized inputs, the human stops looking for functional logic bugs. Instead, the human reviews for **readability, performance optimization, and architectural cleanliness**.

---

## 2. Tooling and Libraries Needed

You need exactly three lightweight, developer-native tools per ecosystem. There are no heavy server components (like Drools) or parsing layers (like Cucumber).

### A. Python Ecosystem (`Neurosim`, `Neurosense`, `Neurochip`)
*   **Contracts/Types:** `Pydantic` or strict Python `TypedDict` and `Protocol`. Enforced by `mypy` or `pyright`.
*   **Property Testing:** `hypothesis` (The industry standard for property-based testing in Python).
*   **Test Runner:** `pytest`.

### B. Flutter/Dart Ecosystem (`NMTK Desktop Client`)
*   **Contracts/Types:** Built-in strong Dart types, complemented by `freezed` or `json_serializable` for strict data class guarantees.
*   **Property Testing:** `glados` (a fast property-based testing framework for Dart).
*   **Test Runner:** `flutter test`.

### C. The Orchestrator
*   **CI/CD Pipeline:** Standard GitHub Actions running testing workflows on PRs.
*   **Agent Sandbox:** `Aider`, `Antigravity`, or your existing LangGraph setup, configured to automatically execute the `pytest`/`flutter test` suite and read the stdout errors.

---

## 3. Hands-On Time Savings Estimation

Comparing the CDD-PBT approach to the original SDD/BDD/BRMS approach:

### The Old Way: SDD + BDD + BRMS (Per substantial feature)
*   **Writing Spec:** 2 hours
*   **Writing/Translating Gherkin (`.feature`):** 2–3 hours
*   **Configuring BRMS (Drools/Camunda):** 4–6 hours (Writing DMN tables, exposing APIs, mapping states)
*   **Agent Execution:** ~1 hour
*   **Human Review & Debugging Gherkin Mismatches:** 3–5 hours
*   **Total Human Time:** **~11 to 16 hours per feature**

### The New Way: CDD-PBT (Per substantial feature)
*   **Writing Spec:** 2 hours
*   **Writing Contracts (`Pydantic` types):** 0.5 hours
*   **Writing Properties (`hypothesis` tests):** 1–1.5 hours (Properties take slightly more mental effort to design than a single static test, but you write far fewer of them).
*   **Agent Execution & Auto-Correction Loop:** 0 hours (Fully hands-off. The agent loops until the test goes green across 10,000 randomized inputs).
*   **Human Review:** 0.5–1 hour (Reviewing clean, mathematically proven code).
*   **Total Human Time:** **~4.0 to 5.0 hours per feature**

### The ROI conclusion
*   **Hands-on time reduction:** **~65% to 75%** faster time-to-market per feature.
*   **Bug reduction:** Massively higher catch rate for edge cases because you are evaluating 10,000 randomized variables per test run, compared to the 3 or 4 static hardcoded variables defined in a BDD `.feature` file.
*   **Maintenance:** Elimination of external BRMS deployment servers and Gherkin syntax parsers.
