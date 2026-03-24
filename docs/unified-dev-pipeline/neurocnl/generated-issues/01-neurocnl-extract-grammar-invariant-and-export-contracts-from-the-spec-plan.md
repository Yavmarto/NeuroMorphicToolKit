# neurocnl: extract grammar, invariant, and export contracts from the spec plan

**Module:** neurocnl
**Spec Source:** neurocnl/neuromorphic_spec_plan.md#Layer 1 — Physical Invariants, neurocnl/neuromorphic_spec_plan.md#Layer 2 — Behavioral Spec, neurocnl/neuromorphic_spec_plan.md#Layer 3 — Validation Assertions
**Labels:** feature, cdd-pbt, migration, contracts

## Objective
Create Pydantic v2 contracts for LIF neurons (18 Layer 1 invariants), hardware exports (Loihi, SpiNNaker, Teensy), and the CNL parse → validate → simulate pipeline. Reference implementation in docs/unified-dev-pipeline/neurocnl/contracts/.

## Conversion Steps
- [ ] Copy neuron_params.py — LIFNeuronContract, SynapticContract, STDPContract, PopulationContract
- [ ] Copy hardware_export.py — LoihiExportContract, SpiNNakerExportContract, TeensyExportContract
- [ ] Copy pipeline_contracts.py — CNLParseResultContract, ValidationResultContract, SimulationResultContract, API contracts
- [ ] Route parser and export code through the new contract layer

## Contract Targets
- `neurocnl/neurocnl/contracts/__init__.py`
- `neurocnl/neurocnl/contracts/neuron_params.py`
- `neurocnl/neurocnl/contracts/hardware_export.py`
- `neurocnl/neurocnl/contracts/pipeline_contracts.py`

## Property Targets

## Acceptance Checks
- [ ] All contract classes importable: from neurocnl.contracts import LIFNeuronContract
- [ ] Invalid physics params raise ValidationError with descriptive messages
- [ ] Existing layer1_invariants.py tests still pass (contracts are additive)
- [ ] mypy --strict neurocnl/contracts/ passes
