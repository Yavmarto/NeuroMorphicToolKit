# Test Fixtures Contract

This document outlines the standard test fixtures used in Neurobench backend tests to ensure consistency and prevent fixture drift.

## Standard Fixtures

Standard fixtures are defined in `neurobench/tests/conftest.py`.

### 1. `benchmark_definition_dict`
- **Purpose**: Provides a raw dictionary representation of a valid `BenchmarkDefinition`.
- **Use Case**: Testing JSON serialization, direct schema validation, or when a modifiable dictionary is needed.
- **Key Fields**: `id`, `name`, `task_type`, `input_spec`, `scoring`, `builtin`.

### 2. `benchmark_result_dict`
- **Purpose**: Provides a raw dictionary representation of a valid `BenchmarkResult`.
- **Use Case**: Testing API response parsing or database insertion logic.
- **Key Fields**: `id`, `benchmark_id`, `network_spec_hash`, `timestamp`, `metrics`, `wall_time_seconds`, `seed`.

### 3. `sample_benchmark_definition`
- **Purpose**: Returns an instantiated `BenchmarkDefinition` Pydantic model.
- **Use Case**: Most service-level tests that operate on benchmark metadata.

### 4. `sample_benchmark_result`
- **Purpose**: Returns an instantiated `BenchmarkResult` Pydantic model.
- **Use Case**: Analysis, comparison, and reporting tests.
- **Tip**: Use `sample_benchmark_result.model_copy(update={"metrics": {...}})` to create variants for specific test scenarios (e.g., regressions).

## Maintenance
- When adding new required fields to schemas, update these fixtures immediately.
- Avoid defining local sample dictionaries in individual test files; prefer using or extending these shared fixtures.
