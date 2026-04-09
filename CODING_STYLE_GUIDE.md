# NeuroMorphicToolKit Coding Style Guide

> **Quick Copy Command:**
> To copy this guide to the relevant Python submodules, run the following command from the workspace root:
> ```bash
> for dir in Neuro-Dream-Hand Neurobench Neurochip neurocnl Neurohub Neurosense Neurosim; do cp CODING_STYLE_GUIDE.md "$dir/"; done
> ```

This document outlines the coding style, formatting, and structural guidelines for all Python and Flutter (Dart) submodules within the NeuroMorphicToolKit workspace.

A core focus of this guide is **Maintainability for Agentic Workflows**. With the increasing use of AI coding assistants and autonomous agents, our codebase must be easily parsable, strictly typed, and self-documenting to provide maximum context to both humans and LLMs.

---

## 🤖 General Principles for Agentic Workflows

To optimize the codebase for AI agents (like GitHub Copilot, Devin, etc.):
1. **Strong Typing is Mandatory:** Always use explicit type annotations in both Python and Dart. Agents rely heavily on type signatures to understand data flow and prevent hallucinated method calls.
2. **Small, Focused Files:** Keep files under 500 lines if possible. Agents have limited context windows. If a file gets too large, split it into smaller, logically grouped modules.
3. **Descriptive, Verbose Naming:** Do not abbreviate variable or function names (e.g., use `calculate_neuron_activation` instead of `calc_nrn_act`). Agents decode context from tokens in names.
4. **"Why" over "What" Comments:** Standard code should be readable enough that an agent knows *what* it does. Use comments to explain the *business logic* or *why* a specific approach was taken (especially workarounds).
5. **Standardized Docstrings:** Every public function, class, and method MUST have a docstring/dartdoc.
6. **Predictable Architecture:** Use consistent design patterns (e.g., separating UI, business logic, and data layers). Agents navigate structured architectures much faster.

---

## 🐍 Python Style Guide

Applicable to: `Neuro-Dream-Hand`, `Neurobench`, `Neurochip`, `neurocnl`, `Neurohub`, `Neurosense`, `Neurosim`, `nmtk`.

### 1. Standards & Formatting
* **PEP 8:** The codebase strictly adheres to standard PEP 8.
* **Formatter:** Use [Black](https://black.readthedocs.io/) for uncompromising code formatting. (Line length: 88-100 characters).
* **Linter:** Use [Ruff](https://docs.astral.sh/ruff/) or [Flake8](https://flake8.pycqa.org/) for fast, reliable linting.
* **Import Sorting:** Use [isort](https://pycqa.github.io/isort/) to group imports into standard library, third-party, and first-party.

### 2. Typing & Static Analysis
* **Type Hints:** All function arguments and return types must be type-hinted.
* **Static Checker:** Code must pass `mypy` with `--strict` enabled.
```python
# Good for Agentic Workflows
def process_neural_spike(timestamp: float, channel_id: int) -> bool:
    ...

# Bad
def process_neural_spike(timestamp, channel_id):
    ...
```

### 3. Documentation
* **Docstrings:** Use the **Google Style** docstring format. Required for all public modules, functions, classes, and methods.
* Detail the `Args`, `Returns`, and `Raises` fields explicitly. Agents use these to generate correct test cases and function calls.

### 4. Error Handling
* Avoid bare `except:` clauses. Always catch specific exceptions (`except ValueError:`).
* Raise custom exceptions for domain-specific errors (e.g., `NeuromorphicDeviceError`) to help agents categorize failure states.

---

## 🐦 Flutter / Dart Style Guide

Applicable to: `neuro_toolkit`, `nmtk_ui_core`, and frontend components.

### 1. Standards & Formatting
* **Effective Dart:** Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines.
* **Formatter:** Use `dart format` (default Flutter formatter). Line length max 80 characters.
* **Linter:** Rely on the `flutter_lints` package (preferably the `core` or `recommended` rule sets). Ensure no warnings on `flutter analyze`.

### 2. Typing
* **No `dynamic`:** Strictly avoid using `dynamic` unless interacting with untyped JSON data. Always cast data to strong models as early as possible.
* Use `Object?` instead of `dynamic` if the type is genuinely unknown, forcing explicit runtime type checks.

### 3. Widget Architecture & State Management
* **Extract Widgets, Don't Extract Methods:** When breaking down large UI files, create separate `StatelessWidget` / `StatefulWidget` classes rather than returning helper methods (e.g., `Widget _buildHeader()`). Extracted classes have distinct contexts and element trees, which drastically aids AI agent understanding and Flutter's rendering performance.
* **Separation of Concerns:** Keep business logic *out* of UI components. Use a standard state management solution (e.g., Riverpod, Provider, or BLoC) and maintain this pattern strictly so agents know where to put network/logic code.

### 4. Documentation
* **Dartdoc (`///`):** Use triple slashes for documenting APIs. Document all public members, especially Widget parameters, as agents use these to understand how to compose your custom UI elements.
```dart
/// Represents a customizable neural network visualization node.
///
/// The [activationThreshold] must be a value between 0.0 and 1.0.
class NeuronNodeWidget extends StatelessWidget {
  final double activationThreshold;
  ...
}
```

### 5. File Structure
* Use `lowercase_with_underscores.dart` for file names.
* Keep one class per file unless creating small, tightly-coupled private helper classes.

---

## 🧪 Testing & Quality Assurance

1. **Automated Testing:** All new features must be accompanied by relevant unit and regression tests. Agents should generate tests alongside code using `pytest` (Python) or `flutter test` (Dart).
2. **Test Naming:** Use descriptive names for tests indicating the scenario and expected outcome (e.g., `test_neuron_activation_fails_with_negative_input()`).
3. **Mocking & Fixtures:** Isolate unit tests by mocking external APIs, hardware interfaces, or heavy I/O operations. Provide factory fixtures for common objects.

---

## 🌿 Version Control & Commits

1. **Conventional Commits:** Use standard prefixes: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`. This helps agents automatically generate changelogs.
2. **Atomic Commits:** Each commit should perform one discrete logical change. Agents should not bundle formatting, refactoring, and new feature implementations in a single commit.

---

## 🧩 Enforcing Rules in Isolated Submodules

To ensure AI agents (like Jules, Devin, or GitHub Copilot) adhere to these rules when operating *only* within a specific submodule, do **not** duplicate this entire file. Instead:

1. **Relative Pointers (Monorepo context):** Place a lightweight agent config file (e.g., `.cursorrules`, `.clinerules`, or `agent_instructions.md`) in the submodule root containing a single prompt:
   > "CRITICAL: Always adhere to the global coding standards defined in `../CODING_STYLE_GUIDE.md`. You must read that file before planning or writing any code."
2. **Remote Context (Fully isolated context):** If the agent checks out the submodule entirely separated from the parent repository, include a prompt directive in the submodule to fetch the rules remotely:
   > "CRITICAL: Fetch and strictly adhere to the workspace style guide located at [URL_TO_GITHUB_RAW_CODING_STYLE_GUIDE] before implementing features."

---

## 🚀 Operations, Pre-commit Hooks & CI
To maintain these standards, enforce formatting and linting via `.pre-commit-config.yaml` or CI pipelines (GitHub Actions, GitLab CI). Automated enforcement ensures the baseline quality is uniformly high before an AI agent or human reviews a PR.
