# Neurohub — Registry & Metadata Module Spec
**Version:** 0.2.0
**Updated:** 2026-05-11

---

## Overview

Neurohub is the **registry and metadata module** for the NeuroMorphic ToolKit (NMTK) suite. It provides project metadata management, workflow metadata and history, bundle inspection and sharing, asset library curation, and a sharing surface for bundles and artefacts.

Neurohub is **not** the suite launcher or runtime orchestration layer — that role belongs to `nmtk`. Neurohub is a **registry and metadata service**: a local and future-hostable source of project references, workflow metadata, shared assets, and reusable components.

> **Future Vision:** Neurohub may eventually grow into a full public community registry (akin to HuggingFace Hub for neuromorphic computing). That vision is documented separately at the end of this spec. The current scope is deliberately local and product-real.

---

## Module Identity

Neurohub owns:
- Project metadata (CRUD, members, milestones, tags, cross-module links)
- Workflow metadata and execution history (templates, run records, DAG definitions)
- Bundle inspection, export, and import
- Shared asset library (curation, feed, personal shares)
- Activity aggregation (cross-module activity metadata)
- Dashboard as a registry entry point
- Frontend surfaces: dashboard, feed, my shares, team, bundle inspection, project detail, new project

Neurohub does NOT own:
- Suite startup, install, repair, or workspace hosting (nmtk)
- Runtime health monitoring of sibling services (nmtk)
- Suite orchestration, port assignment, or routing control (nmtk)
- Cross-module execution or service lifecycle (nmtk)

---

## Architecture

### Backend Stack

- **Python 3.11+** with FastAPI
- **SQLAlchemy** ORM with SQLite (local) / PostgreSQL (future)
- **Pydantic v2** for contracts and schemas
- **httpx** for outgoing cross-module HTTP calls

### Frontend Stack

- **Flutter** / Dart with Riverpod for state management
- **nmtk_ui_core** design system package
- Material 3 theming

### Ownership Boundaries

- `nmtk` owns launcher, install/startup, runtime health, workspace hosting, and suite orchestration
- `Neurohub` owns registry metadata, sharing flows, bundles, project metadata, and local views
- Cross-app HTTP calls stay centralized in `neurohub/app/services/suite_client.py`
- Neurohub never calls another module's health endpoint — that is nmtk's domain

---

## Artefact Types (Current Scope)

| Type | Description | Storage |
|---|---|---|
| `cnl_spec` | Reusable CNL specification templates | Shared asset store |
| `neurosim_template` | NeuroSim project templates | Shared asset store |
| `hardware_profile` | Target device specifications and quantisation configs | Shared asset store |
| `benchmark_definition` | Benchmark definitions and baselines | Shared asset store |
| `studio_workspace` | Shared workspace files and benchmark-result bundles | Shared asset store |
| `neurosense_recording` | Sensor recording metadata | Shared asset store |
| `encoding_preset` | Spike encoding configurations | Shared asset store |
| `nir` | Neural Intermediate Representation files | Shared asset store |

> Full public-registry artefact types (snn_model, dataset, etc.) are deferred to the future vision.

---

## Backend API Endpoints

All Neurohub endpoints live under the root FastAPI app prefix.

| Method | Path | Purpose |
|---|---|---|
| **Dashboard** | | |
| GET | `/dashboard` | Aggregated registry dashboard (projects + activity) |
| **Projects** | | |
| GET | `/projects` | List projects (filterable, paginated) |
| POST | `/projects` | Create a new project |
| GET | `/projects/{id}` | Get project detail |
| PUT | `/projects/{id}` | Update a project |
| DELETE | `/projects/{id}` | Delete a project |
| POST | `/projects/{id}/export` | Export project as bundle |
| POST | `/projects/import` | Import project from bundle |
| **Project Members** | | |
| GET | `/projects/{id}/members` | List project members |
| PUT | `/projects/{id}/members` | Update project members |
| **Project Milestones** | | |
| GET | `/projects/{id}/milestones` | List project milestones |
| PUT | `/projects/{id}/milestones` | Replace project milestones |
| **Workflows** | | |
| GET | `/workflows` | List workflow templates |
| POST | `/workflows` | Create a workflow template |
| PUT | `/workflows/{id}` | Update a workflow template |
| POST | `/workflows/{id}/run` | Execute a workflow for a project |
| GET | `/workflows/runs/{run_id}` | Get workflow run detail |
| POST | `/workflows/runs/{run_id}/cancel` | Cancel a running workflow |
| **Sharing** | | |
| GET | `/feed` | Public feed of recently shared assets |
| GET | `/feed/unread-count` | Count of new feed items since last check |
| GET | `/shares` | Assets shared by the current user |
| **Assets** | | |
| GET | `/assets` | List shared assets (filterable) |
| POST | `/assets` | Upload a new shared asset |
| GET | `/assets/{id}` | Get asset detail |
| **Activity** | | |
| GET | `/activity` | List activity entries (filterable) |
| POST | `/activity/collect` | Trigger activity collection from suite apps |
| **Health** | | |
| GET | `/health` | Self-health check (NeuroHub's own database + version) — NOT suite-wide |
| **Auth** | | |
| POST | `/auth/login` | Authenticate user |
| GET | `/auth/me` | Get current user info |
| **Config** | | |
| GET | `/config` | Get NeuroHub configuration |
| PUT | `/config` | Update NeuroHub configuration |
| **Notes** | | |
| GET | `/notes` | List notes |
| POST | `/notes` | Create a note |
| GET | `/notes/{id}` | Get note detail |
| PUT | `/notes/{id}` | Update a note |
| DELETE | `/notes/{id}` | Delete a note |

---

## Contracts (Pydantic Models)

### Project Contracts (`neurohub/contracts/project_contracts.py`)

- `ProjectMember(user_id, name, role)` — role: admin | engineer | viewer
- `ProjectLinks(neurosim_project_id, neurochip_target_id, neurochip_deployment_ids, neurobench_benchmark_ids, neurobench_baseline_ids, neurosense_session_ids, cnl_spec_hash)` — cross-module references as metadata, not code dependencies
- `AutoDetectConfig(app, condition, parameters)` — automatic milestone detection config
- `Milestone(id, name, status, target_date, completed_date, auto_detect, notes)` — status: not_started | in_progress | complete
- `Project(id, name, description, created_at, updated_at, owner, members, links, status, milestones, tags)` — status: not_started | in_progress | complete | archived
- `ProjectConfig(name, owner, module_list)` — used during creation

### Workflow Contracts (`neurohub/contracts/workflow_contracts.py`)

- `ContractWorkflowStep(id, depends_on)` — basic DAG step
- `WorkflowDefinition(steps, execution_order)` — basic DAG with reference and cycle validation
- `WorkflowStep(id, name, app, endpoint, method, parameters, success_criteria, on_failure, depends_on, timeout_seconds, retries, retry_delay_seconds)` — detailed step
- `WorkflowTemplate(id, name, description, steps, builtin, schedule)` — reusable template with DAG and isolation validation

### Bundle Contracts (`neurohub/contracts/bundle_contracts.py`)

- `BundleFormat(ZIP, TAR, NEUROSPACE)`
- `SharedAsset(id, name, description, type, version, author, tags, created_at, file_path, file_size_bytes, sha256, metadata)` — shared asset with validated paths and sha256
- `ExportBundle(format, contents, bundle_hash, target, project_id, workflow_id)` — export bundle with integrity validation

---

## Frontend Screens

### Primary Navigation Surfaces

| Screen | Purpose | Shell Section |
|---|---|---|
| `DashboardScreen` | Registry entry point: project overview, activity feed | projects |
| `FeedScreen` | Public feed of recently shared assets | feed |
| `MySharesScreen` | Current user's shared assets | myShares |
| `TeamScreen` | Collaboration and team view (stub) | team |
| `BundleInspectionScreen` | Bundle and asset inspection | bundles |
| `ProjectDetailScreen` | Project metadata, milestones, members | projects |
| `NewProjectScreen` | Create a new project | projects |
| `AssetLibraryScreen` | Browse shared asset library | — |

### Supporting Widgets

| Widget | Purpose |
|---|---|
| `ProjectCard` | Project summary card |
| `ActivityFeed` | Activity stream widget |
| `AssetCard` | Asset summary card |
| `SuiteHealthBar` | **DEPRECATED** — orchestration-era, to be removed |

### Shell

| Component | Purpose |
|---|---|
| `NeurohubRouteState` | Route state model with target, section, selectedProjectId |
| `NeurohubShellSection` | Navigation sections (feed, myShares, projects, bundles, team, settings) |
| `NeurohubRouteTarget` | Route destinations (projectOverview, projectDetail, bundleInspection, newProject, feed, myShares, team) |
| `NeurohubModuleDeepLink` | Deep link parser from URI locations |
| `NeurohubRestorationSnapshot` | State persistence for app restoration |
| `NeurohubWorkspaceController` | ChangeNotifier managing route state and persistence |

> **Note:** `NeurohubShellSection.registry` is kept for backward compatibility but is NOT shown in navigation. Deep links referencing `/orchestration` or `/workflow/editor` paths remap to surviving surfaces.

---

## File Structure

```
Neurohub/
├── neurohub/                          # Python backend
│   ├── contracts/
│   │   ├── __init__.py
│   │   ├── project_contracts.py       # Project, Milestone, ProjectLinks
│   │   ├── workflow_contracts.py      # WorkflowDefinition, WorkflowTemplate
│   │   └── bundle_contracts.py        # ExportBundle, SharedAsset, BundleFormat
│   ├── app/
│   │   ├── main.py
│   │   ├── auth.py
│   │   ├── limiter.py
│   │   ├── routers/
│   │   │   ├── activity.py
│   │   │   ├── assets.py
│   │   │   ├── auth.py
│   │   │   ├── config.py
│   │   │   ├── dashboard.py
│   │   │   ├── health.py
│   │   │   ├── members.py
│   │   │   ├── milestones.py
│   │   │   ├── notes.py
│   │   │   ├── projects.py
│   │   │   ├── sharing.py
│   │   │   └── workflows.py
│   │   ├── schemas/
│   │   │   ├── activity.py
│   │   │   ├── assets.py
│   │   │   ├── bundles.py
│   │   │   ├── config.py
│   │   │   ├── dashboard.py
│   │   │   ├── health.py
│   │   │   ├── milestones.py
│   │   │   ├── notes.py
│   │   │   ├── projects.py
│   │   │   ├── users.py
│   │   │   └── workflows.py
│   │   └── services/
│   │       ├── activity_collector.py
│   │       ├── asset_library.py
│   │       ├── auth_service.py
│   │       ├── bundle_service.py
│   │       ├── config_service.py
│   │       ├── health_checker.py          # TO BE REMOVED
│   │       ├── milestone_tracker.py
│   │       ├── model_zoo_manifest.py
│   │       ├── project_service.py
│   │       ├── suite_client.py
│   │       └── workflow_engine.py
│   ├── db/
│   │   ├── database.py
│   │   ├── models.py                      # Includes SuiteConfigDB (review for removal)
│   │   └── migrations/
│   ├── pyproject.toml
│   └── tests/
│       ├── conftest.py
│       ├── test_contracts.py
│       ├── test_contract_invariants.py
│       ├── test_projects.py
│       ├── test_workflow_router.py
│       ├── test_workflow_engine.py
│       ├── test_workflow_engine_v2.py
│       ├── test_asset_library.py
│       ├── test_assets_router.py
│       ├── test_all_endpoints.py
│       ├── test_smoke.py
│       ├── test_prod_integration.py
│       ├── test_config_service.py
│       ├── test_suite_client.py
│       ├── test_auth.py
│       ├── test_auth_service.py
│       ├── test_cors.py
│       ├── test_rate_limiting.py
│       ├── test_concurrency.py
│       ├── test_export_import.py
│       ├── test_handoff_integration.py
│       ├── test_alembic_migrations.py
│       ├── test_activity_collector.py
│       ├── test_milestone_tracker.py
│       ├── mock_suite_server.py
│       ├── properties/
│       │   ├── test_project_properties.py
│       │   ├── test_workflow_properties.py
│       │   ├── test_bundle_properties.py
│       │   └── test_orchestration_properties.py  # TO BE REMOVED
│       └── SMOKE_TESTS.md
├── frontend/                             # Flutter frontend
│   ├── lib/
│   │   ├── screens/
│   │   ├── widgets/
│   │   ├── shell/
│   │   ├── models/
│   │   ├── providers/
│   │   └── view_models/
│   └── test/
│       ├── screens/
│       └── shell/
├── AGENTS.md
├── neurohub_spec.md
└── pyproject.toml
```

---

## Cross-Module HTTP Calls

Neurohub makes outbound HTTP calls to other suite modules for:
- **Bundle handoff:** Sending export bundles to target module APIs
- **Activity fetching:** Aggregating activity metadata from suite modules
- **General API calls:** Cross-module API communication

Neurohub does NOT:
- Monitor health of other modules (nmtk's responsibility)
- Control startup or shutdown of other modules
- Store or validate port assignments for other services

---

## Responsive Requirements

| Viewport Width | Layout |
|---|---|
| >= 1440 | Full two-column dashboard, all nav destinations |
| >= 1024 | Two-column dashboard, full navigation |
| >= 768 | Full navigation bar, single-column content |
| >= 600 | Compact navigation (4 items), single column |
| >= 390 | Compact navigation, single column, condensed cards |

No `RenderFlex overflow` at any supported width. Primary actions remain visible and accessible.

---

## Validation Commands

### Backend
```bash
PYTHONPATH=. pytest neurohub/tests/ -v
ruff check neurohub
mypy neurohub
```

### Frontend
```bash
cd frontend && flutter test
```

### High-Signal Responsive Checks
- `frontend/test/screens/neurohub_responsive_audit_test.dart`
- `frontend/test/screens/dashboard_screen_test.dart`
- `frontend/test/screens/bundle_inspection_screen_test.dart`
- `frontend/test/screens/project_detail_screen_test.dart`

---

## Future Vision: Public Community Registry

The following capabilities are intentionally deferred beyond the current mission scope. They are preserved here as a design direction for future work.

### Future Artefact Types
- `snn_model` — Pre-trained SNN weights + architecture
- `dataset` — Neuromorphic datasets (event streams, spike recordings, EMG, DVS)
- `hardware_profile` — Extended public hardware profiles with community data
- `encoding_preset` — Public spike encoding presets
- `benchmark_baseline` — Community benchmark result sets

### Future Infrastructure
- PostgreSQL production database
- MeiliSearch full-text search index
- S3-compatible object storage (MinIO)
- Next.js web UI for public discovery
- CLI tool (`neurohub push/pull/search`)
- Docker Compose deployment stack

### Future Community Features
- Full-text search with filters (artefact type, hardware, neuron model, licence)
- User/organisation namespaced artefacts (`{owner}/{slug}`)
- Semantic versioning for artefacts
- Star and bookmark system
- Discussion threads on artefact pages
- NeuroBench score submission and moderation
- Trending and featured content

### Future NMTK Integration
- In-app browser panel for NeuroSim, NeuroCNL, NeuroSense, NeuroChip
- One-click import of registry artefacts into active project
- Publish-to-Neurohub from within NMTK modules
- NeuroBench auto-publish

### Future API Surface
Extended `/api/neurohub/` prefix with artefact CRUD, versioning, file upload/download, community endpoints, user/org management, and discovery endpoints.

### Future URI Scheme
```
neurohub://{type}/{owner}/{slug}@{version}
```
