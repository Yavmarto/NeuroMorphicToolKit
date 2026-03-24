# neurocnl: add property tests for grammar and invariant preservation

**Module:** neurocnl
**Spec Source:** neurocnl/neuromorphic_spec_plan.md#The Honest Risk, neurocnl/neuromorphic_spec_plan.md#Step 4 — Validate Against Nengo Simulation
**Labels:** feature, cdd-pbt, migration, properties

## Objective
Add 12+ Hypothesis property tests covering physics invariants, contract rejection, Loihi export, metamorphic relations, and CNL pipeline consistency. Reference implementation in docs/unified-dev-pipeline/neurocnl/properties/.

## Conversion Steps
- [ ] Copy test_physics_properties.py — TestPhysicsInvariants (500 examples each), TestContractRejection, TestLoihiProperties, TestMetamorphicProperties, TestCNLPipelineProperties
- [ ] Configure Hypothesis CI profile (200 examples, deterministic seed)

## Contract Targets

## Property Targets
- `neurocnl/neurocnl/tests/properties/test_physics_properties.py`

## Acceptance Checks
- [ ] pytest neurocnl/properties/ -v --hypothesis-seed=0 passes
- [ ] At least 5000 total test cases generated across all properties
- [ ] No existing tests broken

## Dependencies
- blocked-by: `CNL-CDD-001`
