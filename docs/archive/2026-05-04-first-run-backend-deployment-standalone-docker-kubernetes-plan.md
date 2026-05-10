# First-Run Backend Deployment Plan

Date: 2026-05-04

## Goal

Make first-run backend setup feel like a guided one-click install from the launcher:

- `Standalone`: deploy backend processes directly on the selected machine
- `Docker`: deploy backend services with Docker or Docker Compose
- `Kubernetes`: deploy backend services to a selected cluster namespace
- `Remote server targeting`: let the user choose local machine or remote host, enter IP or hostname, and authenticate with SSH key, SSH password, or service username/password where appropriate
- `Visible progress`: keep the user informed while install or deployment is still running

The product goal is not "more deployment options"; it is "a seamless first-open experience that gets the backend reachable with the fewest decisions and the clearest recovery path."

## Current Baseline

The repo already has the right control-plane foundation, but it is fragmented:

- `nmtk/neuro_toolkit/lib/services/launcher_control_bootstrap_service.dart` already bootstraps a local launcher control API and distinguishes `ready` from `preflightFailed`
- `nmtk/launcher_control/server.py` already owns module lifecycle state, remote host records, and remote provisioning flows for Akida and PYNQ
- `nmtk/launcher_control/provisioning_helpers.py` already knows how to build remote install bundles and run multi-step host setup
- `nmtk/neuro_toolkit/assets/modules.json` is already the source of truth for launcher module metadata and runtime contract fields
- `nmtk/neuro_toolkit/lib/screens/onboarding.dart` already provides a first-run surface, but it only explains the toolkit; it does not orchestrate backend deployment

The missing piece is a single first-run deployment workflow that generalizes the existing control-plane patterns beyond special-purpose hardware provisioning.

## Product Outcome

On first open, the launcher should do this:

1. Detect that no backend deployment target is configured yet.
2. Redirect the user into a `Backend Setup` flow before they land in the normal workspace.
3. Ask where the backend should run:
   - `This machine`
   - `Remote server`
   - `Existing Kubernetes cluster`
4. Ask how it should run:
   - `Standalone`
   - `Docker`
   - `Kubernetes`
5. Gather only the fields required for that combination.
6. Run a preflight.
7. Start the installation or deployment.
8. Show a live progress screen with current stage, logs, estimated next action, and recovery guidance.
9. When complete, automatically health-check the deployed backend and mark the toolkit ready.

## Recommended Scope Split

Do not implement all permutations as a single undifferentiated feature. Ship it in three layers:

### Layer 1: Shared deployment framework

Add a generic launcher-owned deployment contract, deployment job model, preflight model, and progress event stream.

### Layer 2: Standalone and Docker

Ship local machine and SSH-based remote server deployment for `Standalone` and `Docker` first. This will cover the highest-probability user path and validate the UX.

### Layer 3: Kubernetes

Add Kubernetes after the shared workflow and progress UI are proven, because it needs a different credential model, richer validation, and stronger rollback semantics.

## Deployment Modes

### Standalone

Use for:

- local desktop install on the same machine as the launcher
- remote Linux host setup over SSH

Behavior:

- create or validate a Python runtime
- install the backend package and local module dependencies
- write service config
- create a durable service entrypoint
- run health checks against the deployed backend

### Docker

Use for:

- users who want isolation without learning the internals
- remote servers where Docker is easier than Python environment repair

Behavior:

- validate Docker availability
- fetch or build the required images
- write environment and compose or run config
- start containers
- poll health endpoints

### Kubernetes

Use for:

- teams deploying to a cluster rather than a single host
- environments where ingress, namespace separation, and secrets management already exist

Behavior:

- validate kubeconfig, context, namespace, and permissions
- render manifests or Helm values from launcher-owned templates
- create or update Secrets, ConfigMaps, Deployments, Services, and optional Ingress
- wait for rollout readiness and backend health

## Target Architecture

### 1. New generic deployment domain in launcher control

Add a launcher-owned deployment abstraction in `nmtk/launcher_control/server.py` backed by typed helpers rather than embedding mode-specific logic directly into handlers.

Recommended units:

- `DeploymentTarget`
  - local
  - remote_host
  - kubernetes_cluster
- `DeploymentMode`
  - standalone
  - docker
  - kubernetes
- `DeploymentAuthMode`
  - ssh_key
  - ssh_password
  - username_password
  - kubeconfig
  - bearer_token
- `DeploymentJob`
  - queued
  - preflight_running
  - awaiting_confirmation
  - installing
  - verifying
  - completed
  - failed
  - cancelled

Recommended file split:

- `nmtk/launcher_control/deployment_contracts.py`
- `nmtk/launcher_control/deployment_store.py`
- `nmtk/launcher_control/deployment_preflight.py`
- `nmtk/launcher_control/deployment_executors/standalone.py`
- `nmtk/launcher_control/deployment_executors/docker.py`
- `nmtk/launcher_control/deployment_executors/kubernetes.py`
- `nmtk/launcher_control/deployment_progress.py`

This keeps the existing launcher server as the orchestrator while moving per-mode behavior into clear execution units.

### 2. Manifest-backed deployment capability metadata

Extend `nmtk/neuro_toolkit/assets/modules.json` with launcher-visible deployment capability metadata so the deployment flow remains manifest-driven.

Recommended new contract shape per deployable backend module:

- supported deployment modes
- health endpoint path
- required environment variables
- default container image
- optional compose fragment or chart template id
- startup timeout
- readiness timeout
- required ports
- secret fields

If `modules.json` changes, update:

- `nmtk/neuro_toolkit/lib/models/module.dart`
- launcher tests
- any helper scripts that assume install or start semantics

### 3. Saved backend target registry

Generalize the existing paired-host pattern into a reusable target registry:

- local machine target
- SSH host target
- Kubernetes cluster target

Each saved target should include:

- display name
- host or cluster address
- deployment mode
- auth mode
- username
- SSH port if relevant
- namespace if relevant
- secret references rather than raw plaintext where possible
- last known readiness
- last deployed version
- last failure reason

This should live beside the current launcher state files rather than inside module-specific product state.

### 4. Job-based progress reporting

Do not model deployment as a single blocking request. Add job records plus progress events.

Each job should expose:

- current stage
- percent complete
- stage label
- last log line
- started at
- last updated at
- blocking input needed
- terminal outcome

This is the key enabler for a trustworthy "installation still in progress" UI.

## First-Run UX Plan

### Entry condition

On startup, after `LauncherControlBootstrapService.ensureReady()`, the launcher should check whether a valid backend target exists and whether its most recent health check passes.

If not, route to a dedicated first-run setup flow instead of the generic onboarding completion path.

### New first-run flow

Replace the current final onboarding step with a setup wizard:

1. `Choose where to run the backend`
2. `Choose deployment mode`
3. `Enter server or cluster details`
4. `Validate connection`
5. `Review and deploy`
6. `Installing`
7. `Ready`

### Fields by path

#### Local + Standalone

- install location
- backend port
- auto-start preference

#### Local + Docker

- backend port
- image tag or release channel
- optional data directory

#### Remote + Standalone

- display name
- IP address or hostname
- SSH port
- username
- SSH key or password
- install root
- backend port

#### Remote + Docker

- display name
- IP address or hostname
- SSH port
- username
- SSH key or password
- Docker availability check
- exposed backend port
- optional domain

#### Kubernetes

- cluster display name
- API server or kubeconfig source
- context
- namespace
- auth method
- ingress host or load balancer preference
- image tag or release channel

## UI Plan

The UI must prove that work is still progressing, not just that a spinner exists.

### A. Backend setup wizard

Add a launcher-owned wizard screen under `nmtk/neuro_toolkit/lib/screens/` with command-shell styling and explicit mode copy.

Required characteristics:

- one primary decision per screen
- progressive disclosure
- inline validation
- "recommended" defaults
- explicit explanation of the chosen mode

Recommended copy:

- `Standalone runs the backend directly on the machine you choose.`
- `Docker runs the backend in containers and is easier to move and reset.`
- `Kubernetes is best when you already operate a cluster.`

### B. Installation progress screen

Add a dedicated progress view instead of a modal spinner.

Required elements:

- current stage title
- checklist of completed, active, and pending stages
- progress bar with determinate progress when possible
- live log tail
- server target summary
- elapsed time
- next automatic action
- "retry", "cancel", and "view details" actions

Recommended stages:

1. `Validating connection`
2. `Checking prerequisites`
3. `Preparing runtime`
4. `Transferring files or pulling images`
5. `Starting services`
6. `Running health checks`
7. `Saving configuration`

### C. Long-running feedback rules

The UI must update at least every few seconds while a job is active, even if the stage has not changed.

Recommended behavior:

- show timestamped heartbeat text such as `Still installing. Last activity 6s ago.`
- surface the exact current command family, not the full shell command if it exposes secrets
- collapse noisy logs by default and let the user expand them
- preserve progress state if the app is restarted

### D. Completion and failure states

On success:

- show backend URL
- show deployment mode
- show how to reopen or change the target later
- offer `Open Toolkit`

On failure:

- show the failing stage
- show operator-safe error text
- distinguish:
  - `preflight failed`
  - `installation failed`
  - `degraded optional capability`

This language should match the existing launcher doctor terminology.

## Backend API Plan

Add generic launcher-control endpoints for deployment setup:

- `GET /api/launcher/deployment/targets`
- `POST /api/launcher/deployment/targets`
- `PUT /api/launcher/deployment/targets/{id}`
- `POST /api/launcher/deployment/preflight`
- `POST /api/launcher/deployment/jobs`
- `GET /api/launcher/deployment/jobs/{id}`
- `POST /api/launcher/deployment/jobs/{id}/cancel`
- `POST /api/launcher/deployment/jobs/{id}/retry`

Optional but recommended:

- `GET /api/launcher/deployment/jobs/{id}/events`

The event stream can start as polling and later move to SSE if needed.

## Security Plan

Credentials are part of the feature, so credential handling must be part of the first design, not a later cleanup.

Rules:

- never log plaintext passwords, SSH private keys, bearer tokens, or kubeconfig secrets
- store credentials outside `modules.json`
- prefer OS keychain or a launcher-owned secret store abstraction
- redact secret-bearing command arguments in job logs
- support SSH key auth before adding convenience password flows for production guidance
- gate Kubernetes secret writes behind explicit review in the final confirmation step

## Implementation Phases

### Phase 0: Discovery and contract design

Target dates: 2026-05-04 to 2026-05-06

- map current launcher install, start, and remote provisioning code paths
- define generic deployment contracts and target models
- define `modules.json` deployment metadata extension
- decide secret storage approach for desktop launcher

### Phase 1: Shared deployment framework

Target dates: 2026-05-07 to 2026-05-12

- add typed deployment models to launcher control and launcher Dart models
- add target persistence and job persistence
- add preflight and progress APIs
- add UI route guards for first-run backend setup

### Phase 2: Standalone deployment

Target dates: 2026-05-13 to 2026-05-19

- implement local standalone executor
- implement remote SSH standalone executor
- add service health verification
- add progress screen wiring

### Phase 3: Docker deployment

Target dates: 2026-05-20 to 2026-05-27

- implement local Docker executor
- implement remote Docker executor
- add image and compose validation
- add recovery flow for missing Docker daemon or port conflicts

### Phase 4: Kubernetes deployment

Target dates: 2026-05-28 to 2026-06-06

- implement cluster target model
- add kubeconfig and context validation
- add manifest or Helm rendering path
- add rollout and health verification

### Phase 5: Polish and hardening

Target dates: 2026-06-07 to 2026-06-12

- improve copy and failure recovery
- persist and resume in-progress jobs across app restarts
- add audit logging and redaction tests
- tune progress granularity and timeout messaging

## Validation Plan

### Launcher control verification

For any launcher behavior change:

- `python3 scripts/launcher_control_service.py --doctor --json`
- `bash scripts/run_launcher_guardrails.sh`

Use:

- `bash scripts/run_launcher_guardrails.sh --with-integration`

when the feature changes suite-visible startup behavior or manifest contracts.

### New tests required

Backend:

- deployment contract parsing tests
- target persistence tests
- preflight result tests
- standalone executor tests
- Docker executor tests
- Kubernetes executor tests
- secret redaction tests
- progress event tests

Launcher UI:

- onboarding route guard tests
- wizard validation tests
- progress screen rendering tests
- restart-resume tests
- failure-state copy tests

Cross-module:

- `python3 -m pytest tests/integration/test_cross_module.py`
- `python3 -m pytest tests/integration/test_teensy_e2e.py`

Run the root integration tests if manifest contracts or suite-visible startup semantics change.

## Key Decisions To Lock Early

These should be decided before implementation starts:

1. Is Kubernetes support limited to existing clusters in v1, or does v1 also create namespaces and ingress automatically?
2. Will the launcher build Docker images locally, or only pull published images in v1?
3. Will remote standalone support Linux only in v1?
4. What credential store is acceptable on macOS, Windows, and Linux?
5. Is progress transport polling-only for v1, or do we want SSE immediately?

## Recommendation

Build this as a launcher-owned generic deployment workflow, but ship in this order:

1. Shared deployment job framework
2. Local and remote `Standalone`
3. Local and remote `Docker`
4. `Kubernetes`

That path gives the product a real first-run one-click story quickly while keeping Kubernetes from distorting the core UX before the progress, preflight, and target-selection model is stable.
