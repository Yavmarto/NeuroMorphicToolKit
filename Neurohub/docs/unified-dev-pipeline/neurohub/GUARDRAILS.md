# GUARDRAILS.md - NeuroHub Governance & Safety

This document defines strict governance rules and safety guardrails for the NeuroHub repository. These rules are non-negotiable for all developers, including AI agents.

## 1. Contract Integrity

- **No Breaking Changes**: Modification to existing Pydantic contracts in `neurohub/contracts/` must be backward-compatible unless explicitly authorized. Breaking changes require a suite-wide synchronization.
- **Strict Validation**: All contract definitions must include comprehensive validation logic, especially for DAG structures, unique identifiers, and port assignments.
- **No Direct Column Exposure**: Database models (`db.models`) should not be returned directly by API endpoints. Always map to a Pydantic schema for serialization.

## 2. Security Standards

- **No Mass Assignment**: When updating database records, use dedicated Pydantic update models with `Optional` fields. Apply `.model_dump(exclude_unset=True)` in the service layer.
- **Input Sanitization**: All incoming data must be validated against a Pydantic schema before processing or database entry.
- **Port Management**: The suite uses specific ports (8000-8005). Any change to these must be reflected in the `SuiteOrchestration` contract.

## 3. Data Safety

- **Database Isolation**: Unit tests must use an in-memory SQLite database (`sqlite:///:memory:`) with `StaticPool` to ensure isolation and persistence across TestClient requests.
- **Asset Integrity**: SHA-256 checksums must be maintained for all shared assets and exported project bundles.
- **Transient Artifacts**: Build and test artifacts (e.g., `.dart_tool`, `.hypothesis`, `server.log`) must NOT be committed to the repository.

## 4. Mandatory Type-Checking & Linting

- **Python**: All code must pass `mypy --strict` and `ruff check`. Bare `except` blocks are strictly prohibited.
- **Flutter**: No `dynamic` types are allowed (use `Object?` if necessary). All changes must pass `flutter analyze`.

## 5. Test Requirements

- **Test-Driven Development (TDD)**: New features must be accompanied by relevant unit and property tests.
- **CI/CD Compliance**: All PRs must pass the repository's CI pipeline, including unit tests and CDD-PBT property tests.
- **Failure Assertions**: To comply with Ruff rule B011, use `pytest.fail()` instead of `assert False` for deliberate test failures.

## 6. Architecture Constraints

- **Single Class Per File**: For Flutter/Dart code, maintain one class per file with `lowercase_with_underscores.dart` filenames.
- **Extract Widgets**: In Flutter, extract UI components into separate `StatelessWidget` or `StatefulWidget` classes rather than using helper methods.
- **Absolute Imports**: Use absolute imports from the `neurohub` root for all Python code.
