# neurocnl: extract grammar, invariant, and export contracts from the spec plan

**Module:** neurocnl
**Spec Source:** neurocnl/neuromorphic_spec_plan.md#Layer 1 — Physical Invariants, neurocnl/neuromorphic_spec_plan.md#Layer 2 — Behavioral Spec, neurocnl/neuromorphic_spec_plan.md#Layer 3 — Validation Assertions, neurocnl/neuromorphic_spec_plan.md#Step 1 — Define the CNL Grammar for the Reflex Arc Only, neurocnl/neuromorphic_spec_plan.md#Step 2 — Build the Layer 1 → Layer 2 Validator
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Turn the CNL grammar, invariant checker, and export packages into explicit contracts so agent-written compiler code is forced to target a stable model boundary.

## Conversion
- Create contract models for parsed statements, grammar patterns, invariant violations, compiler outputs, and export manifests.
- Separate Layer 1 invariant objects from Layer 2 statements and Layer 3 assertions.
- Route parser and export code through the new contract layer.

## Contract Targets
- neurocnl/neurocnl/contracts/grammar_contracts.py
- neurocnl/neurocnl/contracts/invariant_contracts.py
- neurocnl/neurocnl/contracts/export_contracts.py
- neurocnl/neurocnl/tests/contracts/test_grammar_contracts.py

## Property Targets
- neurocnl/neurocnl/tests/properties/test_parser_contract_properties.py
- neurocnl/neurocnl/tests/properties/test_export_contract_properties.py

## Acceptance Checks
- Parsed statements have a stable typed representation.
- Invariant violations report a typed code and human-readable explanation.
- Export manifests cannot omit target-specific metadata.
