# NeuroHub — Suite Dashboard & Cross-App Orchestration Layer
**Version:** 0.1.0 (spec draft)
**Created:** 2026-03-15

---

## Overview

NeuroHub is the central dashboard and orchestration layer for the Neuro-space suite. It provides a unified entry point for managing projects that span multiple apps (NeuroSim → NeuroChip → NeuroBench), shared asset management, team collaboration, and cross-app workflow automation. It targets team leads, project managers, and any professional who needs to see the full picture of a neuromorphic product development effort without switching between five separate apps.

---

## Repository

`neuro-space/NeuroHub` — independent repo within the Neuro-space GitHub organization.

**Shared dependencies:**
- `neuro-flutter-ui` shared Flutter design system package
- HTTP clients for all suite app APIs (NeuroSim, NeuroChip, NeuroBench, NeuroSense)
- No direct dependency on `neurocnl` or `neurodreamhand` — NeuroHub orchestrates, it doesn't simulate

---

## User Stories

### Dashboard

**NH-D1 · Suite-wide project dashboard**
As a team lead managing a neuromorphic product,
I want a single dashboard showing all my projects with their current status across all suite apps,
so that I can see progress without opening each app separately.

Acceptance criteria:
- Dashboard shows project cards, each displaying: project name, description, last modified, status summary
- Status summary aggregates from all apps: network design status (NeuroSim), deployment target (NeuroChip), latest benchmark score (NeuroBench), active signal sessions (NeuroSense)
- Cards are clickable — opens the project in the relevant app
- Dashboard refreshes status via polling (every 30s) or manual refresh
- Filter/sort: by name, by last modified, by status

**NH-D2 · Activity feed**
As an engineer working in a team,
I want to see a chronological feed of actions across all suite apps,
so that I know what my teammates have been doing without asking.

Acceptance criteria:
- Feed entries: "Alice modified prosthetic_reflex in NeuroSim", "Bob deployed v2 to Teensy via NeuroChip", "Carol ran grip_stability benchmark — 94.2% accuracy"
- Entries include: timestamp, user, action, app, project, link to open the relevant view
- Filterable by: app, user, project, date range
- Feed populated by polling each app's activity log endpoint

### Project Management

**NH-P1 · Create and manage cross-app projects**
As a team lead starting a new neuromorphic product,
I want to create a project that links related assets across all suite apps,
so that the network design, hardware target, benchmark results, and signal recordings are all connected.

Acceptance criteria:
- "New Project" wizard: name, description, team members, initial app setup (which apps to initialize)
- Project links: NeuroSim canvas (network design), NeuroChip target + deployment config, NeuroBench benchmark suite, NeuroSense recording sessions
- Links are bidirectional — opening the project in any app shows related assets from other apps
- Project metadata stored in NeuroHub's own database; asset data stays in each app's storage

**NH-P2 · Project lifecycle tracking**
As a product manager,
I want to define project milestones (design complete, simulation validated, hardware deployed, benchmarks passed) and track progress,
so that I can report status to stakeholders.

Acceptance criteria:
- Milestones are customizable per project; defaults: Design, Simulation, Quantization, Deployment, Benchmark Pass, Production
- Each milestone has: status (not started / in progress / complete), completion criteria (manual or auto-detected), target date, notes
- Auto-detection examples: "Design complete" when NeuroSim project has a valid CNL spec; "Benchmark Pass" when NeuroBench result exceeds baseline
- Timeline view shows milestones on a horizontal bar with completion status
- Export milestone status as PDF or CSV for stakeholder reports

### Asset Management

**NH-A1 · Shared asset library**
As an engineer reusing components across projects,
I want a central library of shared assets (network templates, hardware profiles, benchmark definitions, signal recordings, encoding presets),
so that I don't recreate them for every project.

Acceptance criteria:
- Asset types: CNL specs, NeuroSim templates, hardware profiles, benchmark definitions, NeuroSense recordings, encoding presets
- Each asset has: name, description, type, version, author, tags, creation date
- Search by name, type, or tags
- "Use in project" button copies/links the asset into the active project in the relevant app
- Assets are versioned — updating a shared asset creates a new version, existing projects can choose to upgrade

**NH-A2 · Import/export project bundles**
As an engineer sharing a complete project with an external collaborator,
I want to export my entire project (all linked assets across all apps) as a single archive,
so that they can import it and have a fully working setup.

Acceptance criteria:
- "Export Project Bundle" produces a `.neurospace` archive (ZIP) containing: project metadata, CNL specs, NeuroSim canvas files, hardware profiles, benchmark definitions + baselines, NeuroSense recordings (optional, can be large), encoding presets
- "Import Project Bundle" creates a new project and populates all linked apps
- Bundle format is documented and versioned for forward compatibility
- Large recordings can be excluded with a checkbox to keep bundle size manageable

### Cross-App Workflows

**NH-W1 · Design-to-deploy pipeline**
As an engineer doing end-to-end development,
I want to trigger a full pipeline (design → validate → quantize → benchmark → deploy) from a single button,
so that I can go from network design to running hardware without manually invoking each app.

Acceptance criteria:
- "Run Pipeline" button on a project with a configured workflow
- Pipeline steps: 1) Validate CNL spec (neurocnl), 2) Run NeuroSim preview, 3) Quantize for target (NeuroChip), 4) Run benchmark (NeuroBench), 5) Generate firmware (NeuroChip), 6) Flash to device (NeuroChip)
- Each step shows: status (pending/running/passed/failed), duration, output summary
- Pipeline halts on failure with clear error message and link to the failing app
- Steps are configurable — skip steps or add custom ones
- Pipeline can be triggered via API for CI/CD integration

**NH-W2 · Configurable workflow templates**
As a team with a specific development process,
I want to define custom workflow templates that match our process,
so that every project follows the same steps.

Acceptance criteria:
- Workflow template editor: define steps, each referencing an API endpoint in a suite app
- Step configuration: name, app, endpoint, parameters, success criteria, on-failure action (halt/warn/skip)
- Built-in templates: "Quick Prototype" (design → preview → deploy), "Full Validation" (design → benchmark → fault sweep → deploy), "CI Gate" (validate → benchmark with regression check)
- Templates are saved and reusable across projects

**NH-W3 · Live signal → simulation integration**
As an engineer testing a prosthetic controller with real EMG input,
I want to route live NeuroSense data through NeuroSim and see motor output in real time,
so that I can do closed-loop testing from the dashboard.

Acceptance criteria:
- "Live Test" mode: select NeuroSense device → select NeuroSim network → connect
- Dashboard shows: input signal (from NeuroSense), spike encoding, network activity (from NeuroSim), motor output
- Latency indicator: end-to-end from sensor to motor command
- Works with both live hardware and replayed sessions
- Stop button cleanly disconnects all streams

### Suite Health & Configuration

**NH-H1 · Suite service health monitor**
As an admin setting up the Neuro-space suite,
I want to see which suite apps are running, healthy, and reachable,
so that I can troubleshoot connectivity issues.

Acceptance criteria:
- Health panel shows each app: NeuroSim, NeuroChip, NeuroBench, NeuroSense, neurocnl backend
- Per app: URL, status (online/offline/degraded), response time, version, last health check
- "Check Now" button forces an immediate health check
- Offline apps show troubleshooting guidance: "NeuroChip backend not reachable at localhost:8002 — is it running?"

**NH-H2 · Suite configuration**
As an admin deploying the suite,
I want to configure app URLs, shared database connections, and default settings from one place,
so that I don't need to edit config files in each app separately.

Acceptance criteria:
- Configuration panel for: app URLs (NeuroSim, NeuroChip, NeuroBench, NeuroSense, neurocnl), shared storage path, default project settings
- Changes are validated (URL reachability check) before saving
- Configuration stored in NeuroHub's config file and propagated to apps via their config endpoints (where supported)
- Reset to defaults button

### Team Collaboration

**NH-TC1 · User roles and permissions**
As a team lead,
I want to assign roles (admin, engineer, viewer) to team members,
so that viewers can see dashboards and reports without accidentally modifying designs.

Acceptance criteria:
- Roles: Admin (full access + configuration), Engineer (create/edit projects + run pipelines), Viewer (read-only dashboards + reports)
- Roles are per-project — a user can be Admin on one project and Viewer on another
- Role assignment via project settings panel
- Unauthorized actions show a clear "permission denied" message

**NH-TC2 · Annotations and notes**
As an engineer documenting a design decision,
I want to attach notes to any project asset (network, benchmark result, deployment),
so that the reasoning is preserved for the team.

Acceptance criteria:
- "Add Note" available on any asset card or result view
- Notes support Markdown formatting
- Notes are timestamped and attributed to the author
- Notes are visible in the activity feed
- Notes are included in project bundle exports

---

## Backend Spec

### API Endpoints

All NeuroHub-specific endpoints live under `/api/neurohub/`.

| Method | Path | Purpose |
|---|---|---|
| **Dashboard** | | |
| GET | `/api/neurohub/dashboard` | Get aggregated project status for dashboard |
| GET | `/api/neurohub/activity` | Get cross-app activity feed |
| **Projects** | | |
| GET | `/api/neurohub/projects` | List all projects |
| POST | `/api/neurohub/projects` | Create a new project |
| GET | `/api/neurohub/projects/{id}` | Get project details + linked assets |
| PUT | `/api/neurohub/projects/{id}` | Update project metadata |
| DELETE | `/api/neurohub/projects/{id}` | Delete a project |
| GET | `/api/neurohub/projects/{id}/milestones` | Get project milestones |
| PUT | `/api/neurohub/projects/{id}/milestones` | Update milestones |
| POST | `/api/neurohub/projects/{id}/export` | Export project bundle (.neurospace) |
| POST | `/api/neurohub/projects/import` | Import project bundle |
| **Assets** | | |
| GET | `/api/neurohub/assets` | List shared assets (filterable by type, tags) |
| POST | `/api/neurohub/assets` | Add an asset to the shared library |
| GET | `/api/neurohub/assets/{id}` | Get asset metadata + download link |
| PUT | `/api/neurohub/assets/{id}` | Update asset (creates new version) |
| DELETE | `/api/neurohub/assets/{id}` | Remove asset from library |
| **Workflows** | | |
| GET | `/api/neurohub/workflows` | List workflow templates |
| POST | `/api/neurohub/workflows` | Create a workflow template |
| PUT | `/api/neurohub/workflows/{id}` | Update a workflow template |
| POST | `/api/neurohub/workflows/{id}/run` | Execute a workflow on a project |
| GET | `/api/neurohub/workflows/runs/{run_id}` | Get workflow run status |
| POST | `/api/neurohub/workflows/runs/{run_id}/cancel` | Cancel a running workflow |
| **Health** | | |
| GET | `/api/neurohub/health` | Suite-wide health check (all apps) |
| GET | `/api/neurohub/config` | Get suite configuration |
| PUT | `/api/neurohub/config` | Update suite configuration |
| **Team** | | |
| GET | `/api/neurohub/projects/{id}/members` | List project members + roles |
| PUT | `/api/neurohub/projects/{id}/members` | Update member roles |
| POST | `/api/neurohub/projects/{id}/notes` | Add a note to a project asset |
| GET | `/api/neurohub/projects/{id}/notes` | List notes for a project |

### Data Models

**Project**
```python
class Project(BaseModel):
    id: str
    name: str
    description: str
    created_at: str                      # ISO 8601
    updated_at: str
    owner: str                           # User ID
    members: list[ProjectMember]
    links: ProjectLinks
    milestones: list[Milestone]
    tags: list[str]

class ProjectMember(BaseModel):
    user_id: str
    name: str
    role: Literal["admin", "engineer", "viewer"]

class ProjectLinks(BaseModel):
    neurosim_project_id: str | None = None
    neurochip_target_id: str | None = None
    neurochip_deployment_ids: list[str] = []
    neurobench_benchmark_ids: list[str] = []
    neurobench_baseline_ids: list[str] = []
    neurosense_session_ids: list[str] = []
    cnl_spec_hash: str | None = None
```

**Milestone**
```python
class Milestone(BaseModel):
    id: str
    name: str                            # e.g., "Design Complete"
    status: Literal["not_started", "in_progress", "complete"]
    target_date: str | None              # ISO 8601 date
    completed_date: str | None
    auto_detect: AutoDetectConfig | None
    notes: str | None

class AutoDetectConfig(BaseModel):
    app: str                             # e.g., "neurosim", "neurobench"
    condition: str                       # e.g., "cnl_spec_valid", "benchmark_pass"
    parameters: dict[str, Any] = {}      # e.g., {"benchmark_id": "grip_stability", "threshold": 0.90}
```

**SharedAsset**
```python
class SharedAsset(BaseModel):
    id: str
    name: str
    description: str
    type: Literal["cnl_spec", "neurosim_template", "hardware_profile",
                   "benchmark_definition", "neurosense_recording", "encoding_preset"]
    version: int
    author: str
    tags: list[str]
    created_at: str
    file_path: str                       # Path to asset file in shared storage
    file_size_bytes: int
    metadata: dict[str, Any]             # Type-specific metadata
```

**WorkflowTemplate**
```python
class WorkflowTemplate(BaseModel):
    id: str
    name: str                            # e.g., "Full Validation Pipeline"
    description: str
    steps: list[WorkflowStep]
    builtin: bool

class WorkflowStep(BaseModel):
    id: str
    name: str                            # e.g., "Validate CNL Spec"
    app: str                             # e.g., "neurocnl", "neurochip", "neurobench"
    endpoint: str                        # e.g., "/api/neurocnl/validate"
    method: Literal["GET", "POST"]
    parameters: dict[str, Any]           # Static params; dynamic params injected from project context
    success_criteria: str                # e.g., "status == 'valid'" or "accuracy > 0.90"
    on_failure: Literal["halt", "warn", "skip"]
    timeout_seconds: int = 300
```

**WorkflowRun**
```python
class WorkflowRun(BaseModel):
    id: str
    workflow_id: str
    project_id: str
    started_at: str
    completed_at: str | None
    status: Literal["running", "completed", "failed", "cancelled"]
    steps: list[WorkflowStepResult]

class WorkflowStepResult(BaseModel):
    step_id: str
    step_name: str
    status: Literal["pending", "running", "passed", "failed", "skipped"]
    started_at: str | None
    completed_at: str | None
    duration_seconds: float | None
    output_summary: str | None           # Human-readable result
    error: str | None
    result_data: dict[str, Any] | None   # Full API response for downstream steps
```

**ActivityEntry**
```python
class ActivityEntry(BaseModel):
    id: str
    timestamp: str
    user: str
    app: str                             # "neurosim", "neurochip", etc.
    project_id: str | None
    action: str                          # e.g., "modified_network", "deployed_firmware", "ran_benchmark"
    description: str                     # Human-readable: "Alice modified prosthetic_reflex in NeuroSim"
    link: str | None                     # Deep link to the relevant view in the app
```

**SuiteConfig**
```python
class SuiteConfig(BaseModel):
    neurosim_url: str = "http://localhost:8001"
    neurochip_url: str = "http://localhost:8002"
    neurobench_url: str = "http://localhost:8003"
    neurosense_url: str = "http://localhost:8004"
    neurocnl_url: str = "http://localhost:8000"
    shared_storage_path: str = "./shared_assets"
    default_project_settings: dict[str, Any] = {}
```

**ServiceHealth**
```python
class ServiceHealth(BaseModel):
    services: list[ServiceStatus]

class ServiceStatus(BaseModel):
    name: str                            # e.g., "NeuroSim Backend"
    url: str
    status: Literal["online", "offline", "degraded"]
    response_time_ms: float | None
    version: str | None
    last_checked: str
    error: str | None
```

### Service Architecture

```
NeuroHub Frontend (Flutter)
       |
       | HTTP
       |
NeuroHub Backend (FastAPI)
       |
       ├── SQLite / PostgreSQL (projects, milestones, assets, activity, config)
       ├── HTTP clients → NeuroSim API
       ├── HTTP clients → NeuroChip API
       ├── HTTP clients → NeuroBench API
       ├── HTTP clients → NeuroSense API
       └── HTTP client  → neurocnl API
```

NeuroHub's backend is lightweight — it primarily stores metadata and orchestrates calls to the other suite apps. It does not run simulations, quantization, or encoding itself.

### Activity Feed Collection

NeuroHub collects activity by polling each app's activity endpoint:

```
Every 30 seconds:
  GET neurosim_url/api/neurosim/activity?since={last_check}
  GET neurochip_url/api/neurochip/activity?since={last_check}
  GET neurobench_url/api/neurobench/activity?since={last_check}
  GET neurosense_url/api/neurosense/activity?since={last_check}
  → Merge, deduplicate, store in NeuroHub database
```

Each suite app must implement an `/activity` endpoint returning recent actions in the `ActivityEntry` format. This is a shared contract across all apps.

### Workflow Engine

The workflow engine is a simple sequential executor:

```python
async def run_workflow(workflow: WorkflowTemplate, project: Project):
    context = {"project": project, "results": {}}
    for step in workflow.steps:
        params = inject_dynamic_params(step.parameters, context)
        response = await call_app_api(step.app, step.endpoint, step.method, params)
        if evaluate_success(response, step.success_criteria):
            context["results"][step.id] = response
        else:
            if step.on_failure == "halt":
                raise WorkflowFailed(step, response)
            elif step.on_failure == "warn":
                log_warning(step, response)
            # "skip" continues silently
```

Future enhancement: parallel step execution for independent steps.

---

## Frontend Spec

### Screen Layout

```
┌──────────────────────────────────────────────────────┐
│ Nav: [Dashboard] [Projects] [Assets] [Workflows] [⚙] │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌─ Projects ──────────────────────────────────────┐ │
│  │                                                  │ │
│  │  ┌─ Prosthetic Reflex v2 ───────────────────┐   │ │
│  │  │ NeuroSim: design complete ✅              │   │ │
│  │  │ NeuroChip: Teensy 4.1, 8-bit ⚠ quantized │   │ │
│  │  │ NeuroBench: 94.2% grip (+1.3%) ✅        │   │ │
│  │  │ NeuroSense: 3 EMG sessions recorded       │   │ │
│  │  │ Last modified: 2h ago by Alice             │   │ │
│  │  └──────────────────────────────────────────┘   │ │
│  │                                                  │ │
│  │  ┌─ BCI Alpha Detector ─────────────────────┐   │ │
│  │  │ NeuroSim: in progress 🔄                  │   │ │
│  │  │ NeuroChip: not configured                  │   │ │
│  │  │ NeuroBench: no results yet                 │   │ │
│  │  │ Last modified: 1d ago by Bob               │   │ │
│  │  └──────────────────────────────────────────┘   │ │
│  │                                                  │ │
│  └──────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Activity Feed ─────────────────────────────────┐ │
│  │ 14:32  Alice ran benchmark grip_stability ✅     │ │
│  │ 14:15  Alice quantized to 8-bit in NeuroChip    │ │
│  │ 13:50  Bob modified alpha_detector in NeuroSim  │ │
│  │ 13:20  Carol recorded EMG session (2m 15s)      │ │
│  └──────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─ Suite Health ──────────────────────────────────┐ │
│  │ NeuroSim ✅  NeuroChip ✅  NeuroBench ✅        │ │
│  │ NeuroSense ✅  neurocnl ✅                      │ │
│  └──────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

### Key Widgets

| Widget | Purpose |
|---|---|
| `ProjectDashboard` | Grid of project cards with aggregated status |
| `ProjectCard` | Single project summary: per-app status, last modified, team |
| `ProjectDetailView` | Full project view: milestones, linked assets, notes, pipeline |
| `MilestoneTimeline` | Horizontal timeline of project milestones |
| `ActivityFeed` | Chronological feed of cross-app actions |
| `AssetLibrary` | Searchable/filterable grid of shared assets |
| `AssetCard` | Single asset: name, type, version, tags, actions |
| `WorkflowEditor` | Visual step editor for workflow templates |
| `WorkflowRunner` | Pipeline execution view with per-step status |
| `PipelineStepCard` | Single step: status, duration, output summary |
| `SuiteHealthBar` | Compact row of service status indicators |
| `ConfigPanel` | Suite configuration editor with URL validation |
| `MemberManager` | Project member list with role assignment |
| `NoteEditor` | Markdown editor for asset annotations |
| `LiveTestDashboard` | Combined NeuroSense + NeuroSim real-time view |
| `BundleExportDialog` | Configure project bundle export options |

### Providers (Riverpod)

| Provider | State |
|---|---|
| `projectsProvider` | List of all projects with summary status |
| `activeProjectProvider` | Currently selected project with full details |
| `milestonesProvider` | Milestones for active project |
| `activityFeedProvider` | Cross-app activity feed entries |
| `assetsProvider` | Shared asset library (filterable) |
| `workflowTemplatesProvider` | Available workflow templates |
| `activeWorkflowRunProvider` | Currently executing workflow run status |
| `suiteHealthProvider` | Service health status for all apps |
| `suiteConfigProvider` | Suite configuration |
| `projectMembersProvider` | Members + roles for active project |
| `notesProvider` | Notes for active project |
| `liveTestProvider` | Live test session state (NeuroSense → NeuroSim bridge) |

### Navigation

```
Dashboard (home)
├── Projects
│   ├── Project Detail
│   │   ├── Milestones
│   │   ├── Linked Assets
│   │   ├── Notes
│   │   ├── Pipeline Runner
│   │   └── Live Test
│   └── New Project Wizard
├── Assets
│   └── Asset Detail / Versions
├── Workflows
│   ├── Template Editor
│   └── Run History
└── Settings
    ├── Suite Configuration
    └── Health Monitor
```

---

## File Structure

```
NeuroHub/
├── neurohub/                        # Python backend
│   ├── app/
│   │   ├── main.py
│   │   ├── routers/
│   │   │   ├── dashboard.py
│   │   │   ├── projects.py
│   │   │   ├── milestones.py
│   │   │   ├── assets.py
│   │   │   ├── workflows.py
│   │   │   ├── activity.py
│   │   │   ├── health.py
│   │   │   ├── config.py
│   │   │   ├── members.py
│   │   │   └── notes.py
│   │   ├── schemas/
│   │   │   ├── projects.py
│   │   │   ├── milestones.py
│   │   │   ├── assets.py
│   │   │   ├── workflows.py
│   │   │   ├── activity.py
│   │   │   ├── health.py
│   │   │   └── config.py
│   │   └── services/
│   │       ├── project_service.py       # CRUD + linked asset resolution
│   │       ├── milestone_tracker.py     # Auto-detection logic
│   │       ├── asset_library.py         # Shared asset storage + versioning
│   │       ├── workflow_engine.py       # Sequential step executor
│   │       ├── activity_collector.py    # Polls suite apps for activity
│   │       ├── health_checker.py        # Pings all app health endpoints
│   │       ├── bundle_exporter.py       # Project bundle ZIP creation
│   │       ├── bundle_importer.py       # Project bundle ZIP extraction
│   │       └── suite_client.py          # HTTP client wrappers for all suite apps
│   ├── db/
│   │   ├── models.py                    # SQLAlchemy models
│   │   └── migrations/                  # Alembic migrations
│   ├── pyproject.toml
│   └── tests/
├── frontend/                        # Flutter frontend
│   ├── lib/
│   │   ├── app.dart
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart
│   │   │   ├── project_detail_screen.dart
│   │   │   ├── new_project_screen.dart
│   │   │   ├── asset_library_screen.dart
│   │   │   ├── workflow_editor_screen.dart
│   │   │   ├── workflow_run_screen.dart
│   │   │   ├── live_test_screen.dart
│   │   │   └── settings_screen.dart
│   │   ├── widgets/
│   │   │   ├── project_card.dart
│   │   │   ├── milestone_timeline.dart
│   │   │   ├── activity_feed.dart
│   │   │   ├── asset_card.dart
│   │   │   ├── workflow_step_card.dart
│   │   │   ├── suite_health_bar.dart
│   │   │   ├── config_panel.dart
│   │   │   ├── member_manager.dart
│   │   │   ├── note_editor.dart
│   │   │   ├── live_test_dashboard.dart
│   │   │   └── bundle_export_dialog.dart
│   │   ├── providers/
│   │   ├── models/
│   │   └── services/
│   │       └── api_client.dart
│   ├── pubspec.yaml
│   └── test/
├── docker-compose.yml
├── Dockerfile
└── README.md
```

---

## Cross-App Contract: Activity Endpoint

Every suite app (NeuroSim, NeuroChip, NeuroBench, NeuroSense) must implement:

```
GET /api/{app}/activity?since={iso_timestamp}&limit={int}
```

Response format:
```json
[
  {
    "timestamp": "2026-03-15T14:32:00Z",
    "user": "alice",
    "action": "ran_benchmark",
    "description": "Ran grip_stability benchmark — 94.2% accuracy",
    "project_id": "prosthetic_reflex_v2",
    "link": "/benchmark/results/abc123"
  }
]
```

This is the only cross-app contract required for NeuroHub integration. All other cross-app communication (e.g., NeuroSim → NeuroChip deploy) is handled by direct app-to-app HTTP calls.

---

## Cross-App Port Assignments

| App | Backend Port | Frontend Dev Port |
|---|---|---|
| neurocnl | 8000 | 3000 |
| NeuroSim | 8001 | 3001 |
| NeuroChip | 8002 | 3002 |
| NeuroBench | 8003 | 3003 |
| NeuroSense | 8004 | 3004 |
| NeuroHub | 8005 | 3005 |
