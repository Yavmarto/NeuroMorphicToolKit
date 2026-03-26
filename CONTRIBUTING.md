# Contributing to NeuroMorphicToolkit (NMTK)

Welcome! We are excited that you want to contribute to the NeuroMorphicToolkit. NMTK is a multidisciplinary project bridging neuroscience, software engineering, and hardware robotics. To maintain high quality and enable efficient collaboration between humans and AI agents, we follow a strict **Contract-Driven Development (CDD)** process.

---

## 🚀 Getting Started

1.  **Read the [README.md](./README.md)** to understand the project vision and architecture.
2.  **Follow the [SETUP_GUIDE.md](./SETUP_GUIDE.md)** to configure your local environment (Docker, Python, Flutter).
3.  **Explore the Submodules**: NMTK is a monorepo containing 7 specialized submodules. Ensure you understand how to manage them via `git submodule`.

---

## 🧬 Contract-Driven Development (CDD) & PBT

We use **Contract-Driven Development** combined with **Property-Based Testing (PBT)** to ensure mathematical rigor and biological accuracy.

### The CDD Workflow
1.  **Define the Science (Human):** Architects define the physical/biological invariants in `contracts/` (using Pydantic for Python) and `properties/` (using Hypothesis/Glados).
2.  **Implement the Logic (Agent/Human):** Implementation is guided by these contracts. AI agents (like Jules) use these boundaries to self-correct.
3.  **Verify (CI):** Every PR is tested against thousands of randomized inputs to ensure no edge cases break the defined properties.

### Tooling
*   **Python:** `Pydantic` (Contracts), `Hypothesis` (PBT), `pytest` (Runner).
*   **Flutter/Dart:** Strong types (Contracts), `glados` (PBT), `flutter test` (Runner).

For a deeper dive into this philosophy, see [Antigravity's CDD-PBT Pipeline](./Antigravity-CDD-PBT.md).

---

## 🌲 Branching & PR Strategy

### Branching Model
*   **`main`**: Stable production-ready code.
*   **`dev`**: Integration branch for active development.
*   **Feature Branches**: Created from `dev` (e.g., `feat/neurocnl-latency-fix` or `jules/task-007`).

### Commit Guidelines
We follow [Conventional Commits](https://www.conventionalcommits.org/):
*   `feat(...)`: New feature
*   `fix(...)`: Bug fix
*   `docs(...)`: Documentation
*   `test(...)`: Adding tests
*   `refactor(...)`: Code cleanup

**Atomic Commits**: Each commit should perform one discrete logical change.

### Pull Requests
*   Always target the `dev` branch.
*   Fill out the [PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md).
*   **Mandatory Status Checks**:
    *   `ci-passed`: Standard unit/integration tests pass.
    *   `contracts-passed`: All CDD/PBT property tests pass.
*   **Auto-Merge**: PRs from authorized agents that pass all CI and do not modify "protected files" (architecture/contracts) may be auto-merged.

---

## 🎨 Coding Style Guide

All code must adhere to the [CODING_STYLE_GUIDE.md](./CODING_STYLE_GUIDE.md).

### Key Pillars for Agentic Workflows
1.  **Strong Typing**: Mandatory for Python (`mypy --strict`) and Dart.
2.  **Small Files**: Keep files under 500 lines to fit agent context windows.
3.  **Self-Documenting**: Use Google-style docstrings for Python and Dartdoc for Flutter.
4.  **Predictable Architecture**: Separate UI, business logic, and data layers.

---

## 🛠 Development Workflow

### Managing Submodules
When working across modules:
1.  Make changes in the submodule directory.
2.  Commit and push inside the submodule.
3.  Return to the root and commit the updated submodule pointer.

### Local Testing
Before submitting a PR, run the local verification:
```bash
# Python (in module root)
pytest

# Flutter (in frontend root)
flutter test
flutter analyze
```

For more details on the unified pipeline scripts, see [docs/unified-dev-pipeline/](./docs/unified-dev-pipeline/README.md).

---

## 🤝 Questions?
If you're unsure about a contract or architectural decision, open a GitHub Issue or reach out to the project maintainers.
