# Deployment Architecture Overhaul

## Verified Implementation Status (2026-07-04)

**Status: DONE**

Both proposed architectures described in this plan are implemented in the current codebase:

- **Registry-based production deployment.** `.github/workflows/release-docker.yml` builds a full matrix of
  service images (neurocnl, neurochip, neurobench, neurosense, neurohub, suite-api, neurosense-hw-worker,
  neurobench-runner-worker, neurochip-hw-worker, neurocnl-physics-worker, lava-backend, launcher-control,
  jupyter-server) and pushes them to `ghcr.io/${{ github.repository }}/...` on tag push. `docker-compose.prod.yml`
  uses `image: ghcr.io/yavmarto/neuromorphictoolkit/<service>:latest` for every service (confirmed for
  `suite_api`, `neurosense-hw-worker`, `neurobench-runner-worker`, `neurochip-hw-worker`,
  `neurocnl-physics-worker`, `lava-backend`, etc.) instead of local `build:` contexts.
  `Makefile:181-193` has a `deploy-prod` target that rsyncs only `docker-compose.yml` +
  `docker-compose.prod.yml` to the remote host, then runs `docker compose pull && ... up -d --wait`.
- **Rapid dev deployment (rsync + bind mounts).** `docker-compose.dev.yml` mounts `.:/repo` and per-service
  source dirs, and runs `uvicorn ... --reload` for `suite_api` and the workers. `Makefile:196-207` has a
  `dev-sync` target that rsyncs the full source tree (excluding build artifacts) and brings the dev compose
  stack up without a rebuild step, relying on `--reload` for live updates.

Note: the plan's exact wording ("only rsync compose files" for prod, live-reload for dev) matches the
implementation closely; no gaps found. The `docker-ex-m`/`docker-ex-deploy` legacy rsync-based prod path
(the "User Review Required" question about deprecating it) still exists alongside the new `deploy-prod`
target — both paths currently coexist, so that open question was resolved by keeping both rather than
deprecating the old one.

**Missing / not verified:** No evidence of an actual GHCR image being pulled end-to-end from a clean remote
host in this session (would require live infra access); code-level wiring is complete and consistent.

This plan covers implementing two distinct deployment architectures to optimize both the end-user production experience and the internal developer rapid iteration loop.

## User Review Required
> [!IMPORTANT]
> - Do we want to deprecate the current `rsync`-based production deployment (`make docker-ex-m`) in favor of the registry deployment, or maintain it as an offline fallback?
> - For rapid development, the plan skips rebuilding containers on every sync. Is your local machine matching the architecture of the remote development server, or do we need to account for multi-arch compilation (e.g., Apple Silicon vs x86_64 Ubuntu)?

## Open Questions
> [!NOTE]
> - Are there any private/proprietary pip packages or assets that should NOT be pushed to the public GitHub Container Registry?
> - What should the default Docker image tag be? (e.g., `latest` for master branch, and `v1.x` for releases?)

## Proposed Changes

### 1. Registry-Based Production Deployment
Shift from source-sync deployment to pulling pre-built Docker images for production.

#### [MODIFY] [release-docker.yml](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/.github/workflows/release-docker.yml)
- Update the GitHub Actions matrix to build all services defined in `docker-compose.yml` (e.g., `suite_api`, `launcher-control`, `lava-backend`, `jupyter-server`, etc.).
- Tag and push these images to `ghcr.io/yavmarto/neuromorphictoolkit/`.

#### [MODIFY] [docker-compose.prod.yml](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docker-compose.prod.yml)
- Modify the service definitions to use `image: ghcr.io/...` instead of `build: context: .`. This ensures `docker compose up` pulls the pre-built images rather than looking for local Dockerfiles.

#### [MODIFY] [Makefile](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/Makefile)
- Create a new `make deploy-prod` target that transfers *only* the `docker-compose.yml` and `docker-compose.prod.yml` (and `.env`), then executes `docker compose pull && docker compose up -d` on the remote server.

---

### 2. Rapid Development Deployment (Rsync + Bind Mounts)
Optimize the remote development loop by bypassing Docker builds and leveraging live-reloading.

#### [MODIFY] [docker-compose.dev.yml](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/docker-compose.dev.yml)
- Expand the current `volumes` configuration to ensure all backend services have their source code mapped directly into the containers (e.g., `.:/repo` or `./suite_api:/repo/suite_api`).
- Ensure `uvicorn --reload` or equivalent live-reloading commands are active in the `command` or `environment` blocks for dev.

#### [MODIFY] [Makefile](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/Makefile)
- Add a new `make dev-sync` target (or modify the existing `docker-ex-deploy`) to run `rsync` without running `docker compose build` afterward. The containers will remain running, and the Python hot-reloader will automatically restart the processes internally.

## Verification Plan

### Automated Tests
- Trigger the updated `.github/workflows/release-docker.yml` on a test branch to verify it correctly builds and pushes all service images to GHCR without errors.

### Manual Verification
- **Production Workflow:** Run the new `make deploy-prod` to a clean remote server and verify it successfully pulls the images and starts the app without needing the source code.
- **Development Workflow:** Run `make dev-sync`, make a minor text change to a `suite_api` endpoint, re-run `make dev-sync`, and verify the endpoint updates instantly without a full Docker build cycle.
