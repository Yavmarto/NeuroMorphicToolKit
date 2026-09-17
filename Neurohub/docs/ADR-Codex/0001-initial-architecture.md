# ADR 0001: Initial Architecture of Neurohub

## Status
Accepted

## Context
The toolkit needs a reusable artifact layer so models, datasets, hardware profiles, presets, and benchmark baselines can be shared without every module having to invent its own storage, indexing, or interchange system. The public README and spec describe Neurohub primarily as that artifact registry and reuse layer.

The codebase, however, already shows a broader but still coherent application boundary:
- a FastAPI backend in `neurohub/app/`
- a Flutter frontend in `frontend/`
- persistent database state in `neurohub/db/` with Alembic migrations applied on startup
- routers and services for assets, projects, milestones, notes, activity, config, members, dashboard, and workflows
- support services such as `asset_library.py`, `bundle_service.py`, `project_service.py`, `milestone_tracker.py`, `activity_collector.py`, `suite_client.py`, and `workflow_engine.py`

This means the real architecture is not "just a file bucket". It is a registry-centered application that stores and organizes reusable assets and also provides collaboration- and workflow-oriented surfaces around them. Even so, other NMTK modules should still interact with Neurohub through stable APIs and artifacts, not through direct coupling to its internal database or service code.

## Decision
We will establish Neurohub as the suite's registry-centered collaboration and asset-management service, with typed artifacts as its core concern and workflow/project features built around those assets rather than replacing the rest of the suite.

### Core architectural model

Neurohub is built around a durable asset and metadata core:
- ingest assets and metadata
- version and organize them
- expose them via search, retrieval, and bundle surfaces
- relate them to projects, milestones, notes, activity, and workflows
- allow other modules to import or reference them through service APIs

Assets remain the center of gravity. Project and workflow features exist to organize and consume assets, not to make Neurohub the in-process owner of other modules' behavior.

### Ownership boundaries

Neurohub owns:
- asset metadata, bundling, and retrieval
- registry-facing user and organization surfaces
- project, milestone, note, and activity state that lives inside Neurohub
- workflow records and background workflow execution for Neurohub-managed flows

Neurohub does not own:
- the internal persistence of other modules
- their runtime execution semantics
- their private service implementations

Where cross-module interaction exists, it should happen over explicit APIs, bundles, or imported artifacts. The presence of `suite_client.py` and the workflow engine does not justify tight coupling to other codebases.

### Structural decomposition

Safe changes should preserve the current layering:
- routers expose domain-specific HTTP surfaces
- services implement registry, bundle, project, workflow, and activity behavior
- schemas define stable request/response and stored-data contracts
- `db/` owns the durable relational state and migrations
- the workflow worker remains a background application concern, not a hidden side effect of arbitrary request handlers

The startup path matters here: migrations and worker-loop startup are part of application architecture, not incidental boot code.

### Architectural rules for safe change

Agents working in this repository should preserve these rules:
- Do not bypass schemas and services with direct database writes from routers.
- Do not couple other modules to Neurohub internals; use APIs, bundles, or well-defined client boundaries.
- Do not turn workflow features into hard runtime dependencies for the whole suite.
- Do not let project- or dashboard-oriented features overshadow the core asset and metadata model.
- Do not make startup-only behavior such as migrations or workflow workers implicit in random service code paths.

### Why it is built this way

The suite needs one place where reusable neuromorphic assets can live, be described, versioned, and imported. Neurohub adds surrounding project and workflow features because assets are more useful when they can be organized and acted on, but it is still architected as a service boundary, not as a monolithic replacement for the rest of NMTK.

## Consequences
- Reusable neuromorphic assets gain a dedicated home with stable metadata, versioning, and discovery semantics.
- Other modules can use Neurohub as an upstream asset service without inheriting its internal persistence model.
- Workflow and project features can add value, but they also create a risk of scope drift if they stop serving the registry-centered model.
- The architecture now depends on durable schema evolution, database migration hygiene, background worker reliability, and disciplined service boundaries.
