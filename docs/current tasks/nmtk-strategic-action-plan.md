# NMTK Strategic Action Plan & Priority Tasks

This document contains the prioritized strategic action plan for the NeuroMorphicToolKit (NMTK), directly derived from a comprehensive viability and architecture assessment.

## Source Assessments & Context

This plan is based on the following assessment documents, which analyze the project from both critical and affirmative perspectives to produce an unbiased strategic direction.

### Original Source Documents
- **[The Critique](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/assessment/nmtk-critique.md)**: Argues that the field is immature, the audience is small, the UI/product scope is overstated, and several modules are unvalidated.
- **[The Positive Case](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/assessment/nmtk-positive-case.md)**: Argues that the problem of R&D environment setup is real, the team-server deployment model elegantly solves coordination issues, and the systems-level infrastructure (manifests, typed contracts) is a rare and highly valuable contribution.

### Synthesis & Final Verdicts
- **[Viability Synthesis](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/assessment/nmtk-viability-synthesis.md)**: Concludes that the positive case for systems-level value outweighs the critique of the small addressable audience. The immediate value lies in the team-server deployment model and reproducible simulation workflows.
- **[Evaluation Synthesis](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/assessment/nmtk-evaluation-synthesis.md)**: Recommends pivoting the product narrative from a "low-barrier universal compiler" to a "Neuromorphic Workstation & Reproducible Research Control Plane."
- **[Final Assessment](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/assessment/nmtk-final-assessment.md)**: A conditionally positive verdict. NMTK addresses a real problem with strong architecture, but its completion status and scientific claims need to be framed more honestly.

> **Final Strategic Verdict**: NMTK is a well-architected, research-quality infrastructure prototype for neuromorphic workflows. Simulation pipelines are functional; hardware integration is scaffolded but not physically validated at scale. Its most defensible value is in simulation-first workflows for students and researchers using the team/server deployment model.

---

## Priority 1: High Impact / Low Effort (Documentation & Framing)

These tasks immediately align the project's stated goals with its realistic utility, mitigating the strongest criticisms without requiring significant code rewrites.

- [ ] **Update Project Framing & Persona (README and Docs)**
  - **Action**: Reframe NMTK as a "Neuromorphic Workstation & Reproducible Research Control Plane" emphasizing the **team/server deployment model** as the primary, frictionless path.
  - **Action**: Acknowledge that *simulation-first workflows* are the core immediate value, while physical hardware deployment is an advanced, optional tier.
- [ ] **Temper Scientific Claims in `neurocnl` and `Neurosense`**
  - **Action**: Globally replace claims of "biological validation" with more accurate terms like "architectural invariant verification" or "structural invariant checking" in `neurocnl` docs and UI.
  - **Action**: Add disclaimers in `Neurosense` clarifying that spike encoding presets are empirical starting points for research, not definitive biological models.
- [ ] **Clarify Local Installation Prerequisites**
  - **Action**: Update the Launcher's Guided Backend Wizard and the installation documentation to explicitly highlight Docker as a hard prerequisite for local deployment (including enterprise/university licensing caveats for Docker Desktop).

---

## Priority 2: Medium Impact / Medium Effort (Manifest & Launcher Adjustments)

These tasks address the "scope vs. reality" gap by removing unvalidated or unimplemented modules from the core suite manifest, ensuring NMTK presents an honest completion status.

- [ ] **De-list `neurocli` from Core Manifests**
  - **Action**: Remove `neurocli` from `nmtk/neuro_toolkit/assets/modules.json` and any related remote manifests.
  - **Action**: Update Launcher Dart models and tests to ensure the UI no longer displays it as a peer module. Move its documentation to a "Planned Roadmap" section.
- [ ] **Reclassify `Neuro-Dream-Hand` as an Example/Demo**
  - **Action**: Move the `Neuro-Dream-Hand` module out of the core peer launcher manifest (`modules.json`).
  - **Action**: Relocate its codebase and documentation into an `examples/` or `demos/` directory. Frame it explicitly as an end-to-end reference application demonstrating the pipeline, rather than a core infrastructure module.
- [ ] **Refine Neurochip Feature Scope**
  - **Action**: Update the Neurochip roadmap and UI mockups/documentation to prune advanced hardware engineering features (e.g., fault tolerance, dead-neuron injection).
  - **Action**: Refocus the stated scope on stable deployment telemetry, logging, and basic structural constraint checks.

---

## Priority 3: High Impact / High Effort (UI Clarifications & Infrastructure)

These tasks require UI updates and infrastructure changes to ensure researchers are not misled by simulated data or discovery friction.

- [ ] **Demarcate Simulated vs. Real Hardware in Neurobench UI**
  - **Action**: Update the Neurobench UI and reporting layers to explicitly and visibly label CPU-estimated metrics, ensuring they are not confused with physical on-chip execution results.
- [ ] **Pivot Neurohub to a Team-First Artifact Store**
  - **Action**: Update the Neurohub UI and documentation to prioritize the "Private Lab / Team Repository" use case.
  - **Action**: Highlight the "open in studio" deep-linking feature as its primary differentiator from generic Git repositories.

---

*Note: Any changes to `nmtk/neuro_toolkit/assets/modules.json` must be accompanied by updates to Launcher Dart models, launcher tests, and a successful run of `bash scripts/run_launcher_guardrails.sh --with-integration`.*
