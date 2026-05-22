# NeuroMorphicToolKit (NMTK) Portfolio Sheet

## What It Is

**NeuroMorphicToolKit (NMTK)** is a cross-platform desktop suite for neuromorphic and edge AI workflows. It is designed to make spiking neural network development more usable end to end: from plain-English model authoring, to validation, to visual graph inspection, to hardware-facing deployment and benchmarking.

At a high level, NMTK is trying to solve a real problem in neuromorphic computing: the field is fragmented across research code, hardware-specific SDKs, simulator-specific APIs, and tooling that often assumes deep domain knowledge from every user. NMTK turns that into one workflow-oriented product.

## What I Built

- A **launcher/control plane** in Flutter that treats the toolkit as one application instead of a loose pile of services.
- A **manifest-driven module system** that keeps module metadata, runtime behavior, health checks, and launcher state synchronized.
- A **CNL -> IR -> NIR compilation workflow** in NeuroCNL, so higher-level specifications can lower into a hardware-agnostic intermediate representation.
- A **canvas/NIR bridge** that makes generated networks inspectable and editable as structured graph data rather than opaque export artifacts.
- A **hardware-facing deployment layer** in Neurochip that handles runtime truthfulness, deployment packaging, diagnostics, and optional SDK-backed flows for targets like Akida and PYNQ.
- A workflow architecture where **authoring, deployment, benchmarking, and hardware verification are separate concerns** but still feel like one coherent product.

## Why This Is Technically Interesting

NMTK is not a toy demo or a single-model experiment. It is a systems project with real product and architecture concerns:

- **Hybrid desktop architecture:** Flutter frontend plus Python/Docker backend services.
- **Typed orchestration:** launcher state, module metadata, deployment targets, and runtime health are modeled explicitly rather than passed around ad hoc.
- **Fail-closed compilation:** unsupported or approximate semantics are surfaced deliberately instead of being silently claimed as working.
- **Truthful support semantics:** optional runtimes like Akida, PYNQ, and Lava are treated as optional capabilities with explicit degraded states rather than fake "supported" checkboxes.
- **Cross-module contracts:** the toolkit is organized so authoring, deployment, simulation, and benchmarking have clear boundaries but shared handoff formats.

## What Makes It Relevant To Employers

NMTK demonstrates the kind of work deep-tech and edge AI teams often need but do not always have enough of:

- turning advanced hardware or research capability into usable developer workflows
- building platform and tooling layers around difficult technical domains
- connecting product UX with deployment reality
- handling real-world constraints like environment isolation, health checks, startup sequencing, and support truthfulness
- bridging model design, systems integration, and hardware-facing execution

## Current Positioning

The strongest story in NMTK today is not "I built a chip." It is:

**I build the software and workflow layer that makes advanced neuromorphic and edge hardware usable.**

That is the value this project proves:

- product-grade systems thinking
- cross-stack ownership
- edge AI and neuromorphic deployment literacy
- architecture that respects real hardware constraints
- strong fit for platform, tooling, deployment, and applied deep-tech software roles
