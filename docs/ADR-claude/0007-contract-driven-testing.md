# ADR 0007: Contract-Driven Testing

## Status
Accepted

## Context
NMTK modules communicate via REST APIs with Pydantic models defining the data contracts at service boundaries. Contract violations between modules (e.g., neurocnl producing output that Neurochip cannot consume) are the most dangerous class of bugs because they cross team boundaries and are not caught by unit tests within a single module.

## Decision
Define Pydantic BaseModel contracts in each module's `contracts/` directory (e.g., `deployment_contracts.py`, `design_contracts.py`, `pipeline_contracts.py`). Contract invariant tests (`test_contract_invariants.py`) verify that models enforce field-level constraints (value ranges, enum membership, regex patterns). Cross-module handoff contracts (neurocnl -> Neurochip, Neurosense -> Neurobench) are validated via integration tests that instantiate both producer and consumer contracts. Contracts are versioned implicitly by the module's release version.

## Consequences
- **Positive:** Pydantic contracts catch data integrity issues at deserialization time with clear error messages; contract invariant tests serve as executable documentation of API boundaries.
- **Negative:** Contracts are versioned implicitly with no backward-compatibility guarantees; adding a required field to a contract can break all downstream consumers without compile-time warning.
