# neurocnl: add property tests for grammar and invariant preservation

**Module:** neurocnl
**Spec Source:** neurocnl/neuromorphic_spec_plan.md#The Honest Risk, neurocnl/neuromorphic_spec_plan.md#Step 3 — Prototype the Layer 2 → Layer 3 Pipeline, neurocnl/neuromorphic_spec_plan.md#Step 4 — Validate Against Nengo Simulation
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add property suites for parser stability and biological invariant preservation so the compiler cannot silently drift from the spec plan.

## Conversion
- Add parser and serializer round-trip properties for the constrained grammar.
- Add invariant-preservation properties for threshold, refractory, and time-constant rules.
- Add export properties that keep target configuration consistent after conversion.

## Contract Targets
- neurocnl/neurocnl/contracts/assertion_contracts.py

## Property Targets
- neurocnl/neurocnl/tests/properties/test_parser_roundtrip_properties.py
- neurocnl/neurocnl/tests/properties/test_invariant_preservation_properties.py
- neurocnl/neurocnl/tests/properties/test_export_properties.py

## Acceptance Checks
- Round trips preserve the intended grammar structure for valid reflex-arc statements.
- The compiler rejects contradictory or physically impossible specs.
- Generated outputs never report negative time constants or invalid refractory windows.

## Dependencies
- blocked-by local issue id: CNL-CDD-001
