# ADR 0003: Invariant Constraint Checking

## Status
Accepted

## Context
When an LLM attempts to generate complex systems like sensory-motor reflexes or spiking networks, it often violates physical and biological laws (e.g., negative refractory periods, excitatory inhibitory weights). Depending on prompt engineering to fix these issues is non-deterministic.

## Decision
We implemented an explicitly deterministic invariant-constraint validation layer (`contracts` and `validation` submodules). It mathematically enforces layer 1 biological constraints (like bounds on `tau_rc` or `tau_ref`) before and after the intermediate representation generation phase.

## Consequences
- **Positive:** Pre-emptively stops broken execution states; guarantees generated SNNs adhere strictly to defined biological laws.
- **Negative:** Hardcoding biological principles may limit novel experimental network parameters that theoretically violate standard rules but produce interesting SNN phenomena.

## Status Update (2026-07-16 audit)
This ADR says invariant checking lives in "contracts and validation submodules." There is no `validation` submodule under `neurocnl/neurocnl/` — invariant enforcement actually lives in `layers/` (`layer1_invariants.py`, `layer1_validator.py`, `layer2_validator.py`). `contracts/` is a separate concern (typed export/deployment contracts like `akida_deployment_contract.py`, `pynq_deployment_contract.py`), not the invariant-checking module.
