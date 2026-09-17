# Neurobench Guardrails

This document defines hard constraints and safety checks for the Neurobench project to ensure quality and consistency.

## 🐍 Backend Guardrails (Python)

1.  **Strict Linting:** All backend code must pass `ruff check .` with a 100-character line limit (`E501`).
2.  **No Exceptions Without Context:** In `except` blocks, always use `raise ... from` (`B904`) to preserve exception context.
3.  **Mandatory Typing:** All function arguments and return values must have explicit type annotations. Use `-> None` for void functions.
4.  **Strict MyPy:** Code must pass `mypy --strict .` to ensure type safety.
5.  **Docstrings:** Every public function, class, and method must have a Google-style docstring.
6.  **Pydantic Contracts:** Changes to benchmark or result data structures *must* be reflected in the Pydantic contracts within `neurobench/contracts/`.
7.  **Resource Management:** Always use `with` statements (context managers) for file operations and database connections.
8.  **Metric Enforcement:** Allowed benchmark metrics are strictly defined by the `BenchmarkSuite` contract. Do not introduce new metrics without updating the contract.

## 🐦 Frontend Guardrails (Flutter/Dart)

1.  **Effective Dart:** Follow the Effective Dart guidelines. Code must pass `flutter analyze` with `flutter_lints`.
2.  **No `dynamic` Types:** Avoid using `dynamic`. Prefer `Object?` if the type is unknown, forcing explicit runtime type checks.
3.  **Widget Extraction:** Extract widgets into separate `StatelessWidget` or `StatefulWidget` classes instead of using helper methods.
4.  **State Management:** All business logic must be placed in Riverpod providers, not in the UI (screens or widgets).
5.  **Naming Conventions:** Files must use `lowercase_with_underscores.dart`.
6.  **Public APIs:** Use Dartdoc (`///`) for all public members.

## 🧪 Testing & Verification

1.  **Coverage:** Maintain high test coverage for core logic (at least 80% for backend services).
2.  **Property-Based Testing:** Complex logic must include property-based tests using `hypothesis`.
3.  **Isolation:** Tests must be independent and not rely on shared state from other tests. Use temporary SQLite files for backend tests.
4.  **CLI Verification:** Verify CLI entry points for any changes affecting benchmark execution.

## 🚀 CI/CD

- All pull requests must pass the `backend-cdd-pbt` job in the CI workflow.
- Breaking changes to benchmark contracts require a corresponding update to the CLI and frontend.
