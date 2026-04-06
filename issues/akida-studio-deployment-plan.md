---
title: "Move BrainChip Akida Deployment from Experimental to Usable Toolkit Workflow"
labels: ["enhancement", "frontend", "backend", "hardware", "akida", "brainchip", "integration", "toolkit"]
---

# Problem Statement
NeuroCNL includes Akida-specific planning, validation, and code generation, so the Studio experience can feel as if Akida deployment is already part of the normal parse/validate/generate/simulate/deploy flow.

That is not yet true.

Today, Akida support is best described as:
- constrained capability modeling
- sequential-topology validation work
- script/package generation scaffolding
- partial Neurochip packaging and SDK-hook points

What does not yet exist is a trustworthy toolkit path from NeuroCNL-authored network to validated Akida deployment and verified execution that is usable beyond narrow experimentation.

The right end goal is:

`author in NeuroCNL -> validate Akida compatibility in NeuroCNL -> map/package/deploy through Neurochip -> optionally benchmark/verify through other toolkit modules -> orchestrate through NMTK`

# What Exists Today
1. NeuroCNL planner and validator already know that many Akida concepts are unsupported.
2. NeuroCNL has an Akida generator that emits sequential-model scaffolding.
3. Neurochip has an Akida backend with SDK import points, package generation, and inference entrypoints.
4. Optional Akida dependency wiring already exists in Neurochip.
5. Neurobench is a natural candidate for post-deployment benchmark/verification in the broader toolkit.

# Gaps Blocking the Goal
1. The NeuroCNL Akida generator is still a scaffold and not a faithful general mapper.
2. The generic Akida path still conflates:
   - export/package generation
   - real SDK model construction
   - actual device execution
3. There is no shared toolkit deployment contract for Akida across NeuroCNL and Neurochip.
4. The frontend does not clearly explain when Akida is:
   - unsupported
   - exportable as scaffolding only
   - deployable with real SDK/device support
5. There is no end-to-end verification that a NeuroCNL network accepted by the planner actually maps cleanly through the Akida SDK.
6. There is no toolkit-level post-deployment verification story for Akida artifacts.

# Proposed Solution
## Phase 1: Make Akida Support Levels Explicit
Replace ambiguous target support with three explicit Akida states:
- `unsupported`
- `exportable_scaffold`
- `sdk_deployable`

This must be surfaced by both the planner and the frontend.

## Phase 2: Define a Toolkit Akida Deployment Contract
Create a contract describing the exact subset of NeuroCNL IR that can be mapped to Akida across NeuroCNL and Neurochip:
- allowed topology patterns
- allowed layer/connection types
- timing assumptions
- quantization limits
- allowed learning rules
- required metadata for Akida 1 vs Akida 2

This contract should be enforced before generation or package creation.

## Phase 3: Replace Scaffolding-Only Mapping with a Real Shared Mapper
Build a dedicated mapping layer from validated NeuroCNL IR to the structured representation Neurochip's Akida backend expects.

That mapper should:
- preserve provenance
- fail closed for unsupported structures
- target the real Akida SDK abstraction model
- separate script generation from SDK deployment

## Phase 4: Make Neurochip the Official Akida Deployment Module
Refactor Neurochip's Akida backend so package generation and inference are driven by the same contract used by NeuroCNL.

This includes:
- model construction from structured mapped input
- simulator/device selection
- package generation with truthful manifests
- inference verification on supported environments

NeuroCNL should not own real SDK deployment itself; it should hand off to Neurochip.

## Phase 5: Add Toolkit-Level Verification Hooks
For Akida-capable environments, add optional verification hooks through the broader toolkit:
- lightweight runtime verification in Neurochip
- optional post-deploy benchmark runs in Neurobench
- environment and artifact provenance stored for comparison/reporting

## Phase 6: Add a Truthful Toolkit Deployment Panel
For Akida, the Studio should present:
- support level
- unsupported concepts and why
- whether the result is only a generated scaffold or an actually deployable Neurochip-managed SDK package
- runtime environment requirements
- handoff destination: Neurochip
- deployment verification results
- optional benchmark destination: Neurobench

## Phase 7: Add NMTK Orchestration
Expose Akida deployment as a guided toolkit operation:
- validate in NeuroCNL
- deploy through Neurochip
- optionally verify/benchmark through Neurobench

This keeps the user experience unified without forcing all logic into NeuroCNL.

## Phase 8: Add Verification Matrix and CI Coverage
Introduce a test matrix for:
- planner/validator rejection cases
- scaffold generation cases
- SDK-mapped package generation cases
- optional inference execution when Akida SDK is available

This keeps the Studio honest as the mapping evolves.

# Recommended Build Order and Agent Assignment
This is the highest-risk of the three plans. The mapping semantics and support-level model should be owned by the strongest agents.

Use the following agent tiers:
- **Top-tier agent**: `Opus 4.6` or `GPT-5.4 Pro`
- **Second-tier agent**: `GPT-5.4`, `Sonnet 4.6`, or `Gemini 3.1 Pro`

## Step 1: Define Akida support levels and product semantics
- Scope:
  - `unsupported`
  - `exportable_scaffold`
  - `sdk_deployable`
  - planner/frontend meaning of each
- Recommended agent: **Top-tier**
- Why: this determines what the toolkit is allowed to claim.

## Step 2: Define the shared Akida deployment contract
- Scope:
  - accepted IR subset
  - topology constraints
  - quantization rules
  - Akida1 vs Akida2 distinctions
- Recommended agent: **Top-tier**

## Step 3: Build the shared NeuroCNL -> Akida mapping layer
- Scope:
  - validated IR to structured deployment representation
  - provenance retention
  - fail-closed unsupported cases
- Recommended agent: **Top-tier**
- Why: this is the core semantic mapping problem.

## Step 4: Align Neurochip package generation and inference with the shared mapper
- Scope:
  - SDK-side model construction
  - package generation
  - truthful manifests
  - runtime verification entrypoints
- Recommended agent: **Top-tier**

## Step 5: Build frontend and orchestration around the support model
- Scope:
  - readiness UX
  - scaffold vs deployable labeling
  - environment requirements
  - handoff destination display
- Recommended agent: **Second-tier**
- Review: **Top-tier review recommended**

## Step 6: Add optional benchmark/verification toolkit hooks
- Scope:
  - Neurochip runtime verification
  - optional Neurobench benchmarking flow
  - artifact/environment provenance
- Recommended agent: **Second-tier**

## Step 7: Final end-to-end review and test-matrix tightening
- Scope:
  - unsupported cases
  - scaffold-only cases
  - SDK-deployable cases
  - documentation truthfulness
- Recommended agent: **Top-tier**

## Suggested Parallelization
- After Steps 1 and 2 are complete:
  - one second-tier agent can work on Step 5
  - one second-tier agent can work on Step 6
- Steps 3 and 4 should stay with top-tier agents; they are the hardest parts of this plan.

# Acceptance Criteria
- [ ] NeuroCNL planner exposes explicit Akida support levels rather than implying generic deployment support.
- [ ] A formal Akida deployment contract exists and is enforced before generation/export.
- [ ] NeuroCNL maps validated IR into a shared Akida deployment representation used by Neurochip.
- [ ] Neurochip is the official toolkit module for Akida package generation and inference.
- [ ] The NeuroCNL frontend exposes Akida-specific readiness, limitations, and toolkit deployment mode clearly.
- [ ] The toolkit can optionally route deployed Akida artifacts into benchmark/verification flows.
- [ ] NMTK can present the cross-module Akida deployment flow as one guided workflow.
- [ ] Tests cover unsupported, scaffold-only, and SDK-deployable cases.

# Out of Scope
- Claiming all NeuroCNL networks can be deployed to Akida.
- Requiring NeuroCNL alone to own the Akida SDK runtime.
- Treating generated Python scaffolding as equivalent to hardware deployment.
- Hiding Akida SDK/platform constraints from the user.
