# ADR 0001: Initial Architecture of Neurochip

## Status
Accepted

## Context
Deploying SNNs to physical targets is where portability usually breaks down. Capacity limits, weight formats, transport layers, generator outputs, flashing paths, and validation rules all differ by platform. If those differences are spread everywhere, the repository turns into a pile of vendor-specific conditionals.

The current Neurochip repo shows a more structured intent:
- FastAPI backend in `neurochip/app/`
- Flutter frontend in `frontend/`
- target schemas and route surfaces in `app/schemas/` and `app/routers/`
- target definitions in `neurochip/targets/`
- firmware and deployment templates in `neurochip/firmware_templates/`
- platform-specific backend and generator services in `app/services/`

The service set makes the architecture explicit:
- `constraint_analyzer.py`, `partitioner.py`, and `power_estimator.py` own cross-target reasoning
- `quantizer.py` and `fault_runner.py` own robustness and quantization workflows
- `deployment_store.py`, `flash_service.py`, and `cache_manager.py` own deployment state and execution support
- target-specific modules such as `teensy_generator.py`, `loihi_generator.py`, `pynq_generator.py`, `spinnaker_generator.py`, `brainscales_generator.py`, and backend adapters such as `akida_backend.py`, `lava_backend.py`, `pynq_backend.py`, and `spinnaker2_backend.py` isolate platform-specific logic

This module therefore needs shared abstractions plus explicit platform adapters, not a fake one-size-fits-all deployment path.

## Decision
We will build Neurochip as the hardware deployment, compilation, and target-analysis layer of the toolkit.

### Core architectural model

Neurochip is organized around a common deployment pipeline:
- choose or load a hardware target
- analyze fit and constraints
- quantify modifications such as quantization or partitioning
- generate target artifacts
- verify or simulate where supported
- deploy or flash where supported

The pipeline is shared, but the implementations behind each stage may be target-specific.

### Ownership boundaries

Neurochip owns:
- target profiles and capability metadata
- compatibility and constraint analysis
- quantization and fault-analysis workflows
- artifact generation for supported targets
- deployment records, flashing, and target-specific execution support

Neurochip does not own:
- natural-language model authoring semantics
- simulation-first design UX
- benchmark result interpretation
- biosignal acquisition

It consumes upstream network artifacts and emits deployment-facing artifacts and reports.

### Structural decomposition

Safe changes should preserve the current separation:
- `targets/` is the structured catalog of device capabilities and constraints
- routers expose domain areas such as targets, analysis, quantization, faults, estimation, export, and deployments
- services perform actual compilation, generation, and verification work
- firmware templates remain explicit target assets, not hidden inline strings in services or routers

Target metadata should stay declarative where possible. If a target capability can live in JSON metadata or a contract, it should not be hardcoded only in API handlers or frontend components.

### Architectural rules for safe change

Agents working in this repository should preserve these rules:
- Do not hardcode device capabilities in routers or UI when they belong in target profiles or contracts.
- Do not blur analysis, generation, and flashing into one opaque function. Each stage exists to explain failure before deployment.
- Do not assume that all targets share one artifact shape; preserve explicit target generators and backend modules.
- Do not relax contracts for deployment or runtime artifacts just to accommodate one backend quickly.
- Do not turn simulation helpers into proof of hardware readiness. Verification, simulation, and real deployment are different architectural stages.

### Why it is built this way

The architecture exists to make hardware deployment understandable and auditable. Users need to know whether a model fits, what was changed to make it fit, what artifact was generated, and what deployment path was actually exercised. Explicit target profiles, generators, and verification stages make that possible.

## Consequences
- Users can reason about deployment through a unified target-selection and compatibility flow instead of starting from vendor SDK details.
- Constraint analysis becomes a first-class gate, which reduces late-stage failure but increases the amount of metadata and contract maintenance required.
- New targets can be added incrementally if they fit the target-profile-plus-service model; they become risky when added as special cases scattered across the stack.
- Platform-specific maintenance remains unavoidable. The architecture manages that complexity; it does not eliminate it.
- Honest support labeling remains necessary because generation, simulation, SITL verification, and real flashing are not interchangeable levels of support.
