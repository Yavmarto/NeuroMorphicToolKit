# NMTK Interview Prep Guide

This is the shortlist of NMTK areas worth understanding deeply enough to explain clearly on a whiteboard or in a technical interview.

## 1. The Core Product Story

Know the answer to:

- What problem NMTK solves.
- Why neuromorphic tooling is fragmented.
- Why one workflow-oriented suite is better than disconnected repos and SDKs.
- Who the two main users are: the researcher and the hardware engineer.

If you cannot explain this simply, the rest of the technical detail will sound unfocused.

## 2. Launcher / Control Plane Architecture

Understand:

- `nmtk/neuro_toolkit/assets/modules.json`
- `nmtk/neuro_toolkit/lib/models/module.dart`
- `nmtk/neuro_toolkit/lib/providers/module_provider.dart`
- `nmtk/neuro_toolkit/lib/services/control_api_service.dart`
- `nmtk/launcher_control/server.py`

You should be able to explain:

- why the launcher is manifest-driven
- how module metadata is shared across Dart and Python
- how install/start/stop/status flows work
- why health polling and preflight exist
- how the launcher distinguishes `running`, `degraded`, `error`, and `preflight_failed`

This is one of the strongest parts of your portfolio because it shows product-grade orchestration, not just ML experimentation.

## 3. CNL -> IR -> NIR Compilation

Understand:

- `neurocnl/backend/app/routers/generate.py`
- `neurocnl/backend/app/services/neurocnl_bridge.py`
- `neurocnl.pipeline`
- `neurocnl.export.nir_exporter`

You should be able to explain:

- how plain-English specifications are parsed
- what validation happens before lowering
- what IR is doing conceptually
- why NIR is the key portability layer
- what "fail closed" means in practice
- why parser recognition is not the same as faithful backend support

This is the intellectual center of the project.

## 4. NIR <-> Canvas Conversion

Understand:

- `neurocnl/backend/app/services/nir_graph_serializer.py`

You should be able to explain:

- how generated NIR graphs become editable canvas graphs
- how node types, ports, labels, and metadata are preserved
- what happens when a NIR type is unknown or unsupported
- why serialization and deserialization are important for product usability

This is easy to underestimate, but it is one of the best examples of turning compiler output into a usable interface.

## 5. Truthful Support Semantics

Understand:

- the difference between `supported`, `approximate`, `scaffolded`, `simulator fallback`, and real SDK-backed execution
- why the project goes out of its way not to overclaim hardware support
- where those semantics appear in APIs, runtime status, and docs

Good places to review:

- `neurocnl/AGENTS.md`
- `Neurochip/AGENTS.md`
- `docs/AKIDA_SUPPORT_SEMANTICS.md`
- `docs/PYNQ_SUPPORT_SEMANTICS.md`
- `Neurochip/neurochip/app/services/akida_backend.py`

This is one of the most distinctive and mature ideas in the repo.

## 6. Hardware Runtime Strategy

Understand:

- why optional hardware dependencies must stay optional
- how simulator fallback works
- how Akida environment checks are modeled
- how PYNQ runtime installation and health differ from local software-only execution
- how remote runtimes fit into the launcher design

You do not need to pretend to be a chip or FPGA specialist, but you do need to show that you understand deployment constraints and runtime integrity.

## 7. Suite API / Module-as-Domain Direction

Understand:

- why the system consolidated toward one suite surface instead of many isolated apps
- how multiple domains are now presented through one product shell
- why this matters for usability, state handoff, and deployment consistency

Best sources:

- `docs/unified_toolkit_architecture.md`
- Open Brain notes about the module-as-domain consolidation

This is important because it shows architectural decision-making over time, not just feature accumulation.

## 8. Reliability, Preflight, and Health

Understand:

- why health endpoints matter in a local desktop-plus-backend product
- why preflight checks are treated as product behavior, not just ops behavior
- how startup readiness, dependency checks, and degraded capability reporting work

Best sources:

- `nmtk/launcher_control/server.py`
- `neurocnl/backend/app/main.py`
- `docs/troubleshooting.md`

This is a strong signal for seniority.

## 9. Clear Module Boundaries

Know the role of each major module at a one-sentence and one-paragraph level:

- `neurocnl`: authoring, validation, compilation, NIR handoff
- `Neurochip`: deployment, packaging, runtime diagnostics, hardware execution paths
- `Neurobench`: benchmarking and evaluation
- `Neurosense`: biosignal acquisition and spike encoding
- `Neuro-Dream-Hand`: applied robotics / prosthetic control use case
- `nmtk`: launcher, shell, control plane
- `Neurohub`: sharing and metadata layer, not launcher orchestration

If you mix these up in conversation, the whole platform story gets weaker.

## 10. The Honest Limits

Be ready to say clearly:

- what is production-grade
- what is partial
- what is scaffolded
- what still needs hardware validation
- what depends on external SDK access

This project gets stronger, not weaker, when you talk about its limits precisely.
