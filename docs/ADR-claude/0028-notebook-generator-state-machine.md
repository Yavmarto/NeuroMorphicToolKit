# ADR-0028: Programmatic Notebook Generator State Machine and Invariants

**Status:** Accepted  
**Date:** 2026-07-09

## Context

The generation of Jupyter Notebooks for training and evaluating neuromorphic models (`neurocnl`) has historically been prone to errors stemming from implicit state management, inconsistent execution environments, and complex branching based on canvas inputs. The introduction of SNN-MLIR compilation targets and the increasing complexity of deployment modes required a more formal approach to generating notebooks programmatically.

A fix playbook (`notebook_generator_fix_playbook.md`) was developed to address recurring bugs, which fundamentally refactored the notebook generation process.

## Decision

We formally adopt a State Machine approach for programmatic Jupyter Notebook generation. The generation pipeline is now strictly bound by the following invariants:

1. **Explicit Phase Transitions:** The generation of a notebook must follow a strict, immutable sequence of phases (e.g., Environment Setup $\rightarrow$ Dataset Loading $\rightarrow$ Network Architecture Definition $\rightarrow$ Training Loop $\rightarrow$ Evaluation $\rightarrow$ Export). A notebook cell cannot be generated out of order.
2. **Deterministic Inputs:** The input to the state machine is the exact state of the `PipelinePhaseCanvas` and `NetworkCanvas`. Implicit fallbacks or "best guesses" for missing components are prohibited (as previously established in ADR-0026).
3. **Execution Context Isolation:** Every generated cell must be completely self-contained or explicitly declare its dependencies on prior cells.
4. **SNN-MLIR Integration:** The state machine must natively support generating cells for SNN-MLIR compilation pipelines, distinguishing between standard PyTorch/snnTorch execution and MLIR graph lowering.

## Rationale

- **Predictability:** A formal state machine makes the generated notebook structure predictable and verifiable through unit tests before it is ever sent to the Jupyter kernel.
- **Extensibility:** Integrating new targets like SNN-MLIR is vastly simplified when the generation pipeline is explicitly phased. New targets simply implement the interface for each phase.
- **Bug Reduction:** By prohibiting implicit state and enforcing execution context isolation, we eliminate the class of bugs where variable scoping or missing imports cause downstream cells to crash.

## Consequences

- All future enhancements to notebook generation (e.g., adding support for a new hardware backend or framework) must be modeled as state transitions within this pipeline.
- The generator code must be maintained as a formal state machine rather than procedural string concatenation.
