# 2026-04-15 Build Process Efficiency Audit

## Scope

This note covers the current backend and frontend build or install flows for:

- `neurocnl`
- `Neurosim`
- `Neurochip`
- `Neurobench`
- `Neurosense`
- `Neurohub`
- `Neuro-Dream-Hand`
- `nmtk/neuro_toolkit`
- `nmtk_ui_core`

The goal is to describe what the repo does today, how it decides whether something needs to be rebuilt or reinstalled, and which low-risk changes would make the process faster without reducing build quality or skipping required work.

## Short version

The repo currently has three different rebuild models:

1. `scripts/run_ci_local.sh` decides what to verify by looking at changed files in Git.
2. The launcher control plane decides when a backend environment must be reinstalled by hashing environment-defining files.
3. The frontend build scripts do not decide anything at the repo level. Once a frontend is selected, they always run `flutter pub get` and `flutter build web`.

That means the repo already knows how to do selective work in some places, but it does not yet use one shared planner for all backend and frontend builds.

## Current entry points

| Surface | Main entry point | What happens today | Rebuild decision source |
| --- | --- | --- | --- |
| Full local CI | `scripts/run_ci_local.sh` | Selects modules, then runs module CI scripts serially | Git diff against `origin/dev` plus unstaged and staged changes |
| Launcher desktop dev flow | `scripts/run_dev.sh` | Starts launcher control API, builds module frontends, runs `flutter run` for launcher | No repo-level frontend dirtiness check; always rebuilds selected frontends |
| All web frontends | `scripts/build_all_frontends.sh` | Runs `flutter pub get` in `nmtk_ui_core`, then each module frontend serially | None in the script itself |
| One web frontend | `scripts/build_module.sh <module> <port>` | Runs `flutter pub get` and `flutter build web` for one module | None in the script itself |
| Per-module dev web flow | `make dev-web` inside each module | Rebuilds the module web app, then starts backend | None in the Makefile; always rebuilds |
| Launcher-managed backend install | `nmtk/launcher_control/server.py` | Creates venv or Poetry env, installs deps, starts `uvicorn` | Environment fingerprint over Python/runtime metadata plus dependency files |
| Docker image build | `docker compose build` or per-module Docker build | Uses Docker layer cache based on each Dockerfile | Docker cache invalidation from `COPY` order and changed files |

## What is currently done

### Frontend build flow

The root frontend build path is centered on `scripts/build_module.sh` and `scripts/build_all_frontends.sh`.

For every selected frontend, the current flow is:

1. Resolve the backend port and API host.
2. Enter the module's `frontend/` directory.
3. Run `flutter pub get`.
4. Run `flutter build web --release --no-wasm-dry-run` with the right `--dart-define`.

This applies to:

- `neurocnl/frontend`
- `Neurosim/frontend`
- `Neurochip/frontend`
- `Neurobench/frontend`
- `Neurosense/frontend`
- `Neurohub/frontend`

`scripts/build_all_frontends.sh` also runs `flutter pub get` in `nmtk_ui_core` before the app builds because the frontends use it as a local path dependency.

The launcher desktop flow in `scripts/run_dev.sh` uses the same build logic. It calls `scripts/build_module.sh` for each module before starting the launcher. If `--with-web` is passed, it also builds the launcher web app itself from `nmtk/neuro_toolkit`.

### Per-module dev flow

Each major module with a frontend has a `Makefile` target named `dev-web`. The pattern is consistent:

1. Build the Flutter web app.
2. Start the backend with `uvicorn`.

This is convenient, but it means a pure backend change still triggers a frontend rebuild when using `make dev-web`.

### Backend install and launch flow

There is no single root script that "builds all backends" in the same way the root scripts build all frontends. Backend behavior is split into two paths:

- direct local startup via each module's own commands or `Makefile`
- launcher-managed installation and startup through `nmtk/launcher_control/server.py`

The launcher path is the most structured one:

1. Read module metadata from `nmtk/neuro_toolkit/assets/modules.json`.
2. Detect whether the module should use plain `venv` or Poetry.
3. Create the environment if it does not exist.
4. Install local sibling dependencies first when configured, for example `Neuro-Dream-Hand` for `neurocnl`.
5. Install the module itself with `pip install .` or `poetry install`.
6. Start the module with `python -m uvicorn <target>`.

### CI verification flow

`scripts/run_ci_local.sh` is the only root-level script that already has explicit changed-module selection logic.

It:

1. Computes a base ref with `git merge-base HEAD origin/dev`, falling back to `HEAD~1`.
2. Collects:
   - committed differences from the base ref to `HEAD`
   - unstaged changes
   - staged changes
3. Maps changed paths to module names.
4. Runs the selected module CI scripts in `scripts/ci/`.

This script scopes verification, not build artifact generation.

## How the repo currently decides something needs to be rebuilt

### 1. Root frontend build scripts

The root frontend build scripts do not have a changed-file or fingerprint-based decision layer.

Once a module is selected, the script treats it as dirty and rebuilds it:

- `flutter pub get`
- `flutter build web`

Any reuse here comes only from Flutter's own caches in `.dart_tool` and the shared pub cache. The repo-level script itself does not skip unchanged modules.

### 2. Local CI changed-module selection

`scripts/run_ci_local.sh` uses Git path matching as its rebuild or retest decision model.

Current notable rules:

- If `neurocnl/**` changed, select `neurocnl`.
- If `Neurosim/**` changed, select `Neurosim`.
- If `Neurochip/**` changed, select `Neurochip`.
- If `Neurobench/**` changed, select `Neurobench`.
- If `Neurosense/**` changed, select `Neurosense`.
- If `Neurohub/**` changed, select `Neurohub`.
- If `nmtk_ui_core/**` changed, also select all Flutter consumers:
  - `neuro_toolkit`
  - `neurocnl_frontend`
  - `Neurochip_frontend`
  - `Neurohub_frontend`
  - `Neurosense_frontend`
  - `Neurobench_frontend`
- If launcher-control files changed, enable launcher guardrails.
- If `nmtk/neuro_toolkit/assets/modules.json` or the root integration tests changed, also run launcher integration coverage.

This is the best existing coarse-grained change detector in the repo.

### 3. Launcher backend reinstall detection

The launcher control service uses a more precise environment fingerprint.

It hashes:

- Python version
- Python path
- install directory
- run directory
- install strategy
- start strategy
- `uvicorn` target
- hashes of environment-defining files, including:
  - `pyproject.toml`
  - `poetry.lock`
  - `requirements.txt`
  - `backend/requirements.txt`
  - `requirements-dev.txt`

If that fingerprint changes, the launcher treats the environment as stale and requires a reinstall before launch.

This is already a solid answer to the question "how does it decide something needs to be rebuilt if something has changed?" for backend environments:

- source-only edits generally mean restart the process
- dependency or environment-definition edits mean reinstall the environment

That distinction is useful and worth reusing elsewhere.

### 4. Docker image rebuild decisions

Docker builds rely on Docker's layer cache, so rebuild behavior depends on each Dockerfile's `COPY` order.

Current state:

- Good cache behavior:
  - `neurocnl/backend/Dockerfile`
  - `Neurochip/Dockerfile`
  - `Neurobench/Dockerfile`
- Weaker cache behavior because source is copied before dependency installation:
  - `Neurosim/Dockerfile`
  - `Neurosense/Dockerfile`
  - `Neurohub/Dockerfile`
  - `Neuro-Dream-Hand/Dockerfile`
  - `Neurosim/frontend/Dockerfile`
  - `Neurohub/frontend/Dockerfile`
- Special case:
  - `Neurosense/Dockerfile.frontend` runs `flutter run -d web-server` instead of producing a build-once release artifact

For Docker, the repo already has selective rebuilds, but they are only as efficient as the Dockerfile layout.

## Where time is currently wasted

### 1. Frontends are rebuilt serially even when independent

`scripts/build_all_frontends.sh` and `scripts/run_dev.sh` build module frontends one after another. These builds are mostly independent once shared inputs such as `nmtk_ui_core` are ready.

### 2. Frontend build scripts do not reuse the existing changed-module selector

The repo already knows how to answer "which modules changed?" in `scripts/run_ci_local.sh`, but that logic is not reused by `scripts/build_all_frontends.sh` or `scripts/run_dev.sh`.

### 3. `make dev-web` always rebuilds the frontend

That makes backend-only edits slower than they need to be.

### 4. Some Dockerfiles invalidate dependency layers too early

When the full source tree is copied before `pip install .`, `poetry install`, or `flutter pub get`, a normal code edit can force a full dependency or build layer rebuild.

### 5. The backend reinstall fingerprint is good, but isolated

The launcher has a strong notion of "environment changed" versus "code changed". The rest of the repo does not share that distinction.

## Safe efficiency improvements

These changes preserve the same quality bar and the same overall actions:

- rebuild everything when explicitly requested
- rebuild only changed targets when asked for changed-only work
- keep the same test and guardrail coverage

### 1. Add one shared build planner

Create one root planner script, for example `scripts/build_targets.py` or `scripts/build_targets.sh`, with two explicit modes:

- `all`
- `changed`

The planner should own target selection for:

- backend environment reinstall
- backend restart
- frontend rebuild
- launcher rebuild
- optional Docker image rebuild

The existing scripts can then become thin wrappers around the same planner.

### 2. Reuse the current dirty signals instead of inventing new ones

Use the current mechanisms as the foundation:

- Use the `scripts/run_ci_local.sh` Git diff mapping for coarse module selection.
- Use the launcher environment fingerprint logic for backend reinstall decisions.
- Add a comparable frontend fingerprint per app.

Recommended frontend fingerprint inputs:

- `frontend/pubspec.yaml`
- `frontend/pubspec.lock` if present
- `frontend/lib/**`
- `frontend/web/**`
- `frontend/assets/**`
- `frontend/test/**` if test artifacts are part of the build gate
- `nmtk_ui_core/**` for apps that import it by local path
- relevant `--dart-define` values such as `API_BASE_URL`, `NEUROCHIP_BASE_URL`, and launcher control API defines
- Flutter SDK version

Recommended backend restart or reinstall split:

- Reinstall if dependency metadata changed.
- Restart only if runtime source changed but dependency metadata did not.

### 3. Parallelize independent frontend builds with bounded concurrency

After dependency warmup, module frontend builds can run in parallel with a small worker pool.

Recommended default:

- `NMTK_BUILD_JOBS=2` on laptops
- `NMTK_BUILD_JOBS=3` on stronger machines

Suggested dependency graph:

1. Prepare `nmtk_ui_core` first.
2. Build module frontends in parallel:
   - `neurocnl/frontend`
   - `Neurosim/frontend`
   - `Neurochip/frontend`
   - `Neurobench/frontend`
   - `Neurosense/frontend`
   - `Neurohub/frontend`
3. Build `nmtk/neuro_toolkit` separately when launcher web output is needed.

This preserves the same build work but changes the schedule.

### 4. Let backend verification and unrelated module CI run in parallel

`scripts/run_ci_local.sh` currently runs module scripts serially. For changed-only work, many of the selected modules are independent.

Low-risk improvement:

- keep launcher guardrails as a dedicated stage
- run non-overlapping module CI scripts in parallel with bounded concurrency
- aggregate results at the end exactly as today

This improves throughput without weakening checks.

### 5. Standardize Dockerfiles for cache efficiency

For Python backends:

1. Copy only dependency metadata first.
2. Install dependencies.
3. Copy the application source.
4. Install the project itself only when needed.

For Flutter frontends:

1. Copy `pubspec.yaml` and `pubspec.lock` first.
2. Copy local path dependency manifests needed for resolution, especially `nmtk_ui_core`.
3. Run `flutter pub get`.
4. Copy the remaining frontend source.
5. Run `flutter build web`.

This keeps Docker's changed-target behavior but makes it more effective.

### 6. Add persistent build fingerprints for frontends

Store frontend fingerprints under a root cache directory such as:

`./.cache/nmtk-build/`

Per target, keep:

- last fingerprint
- last build timestamp
- build command inputs
- build output path

Then:

- `build all` ignores the cache and rebuilds everything
- `build changed` compares the new fingerprint with the saved one and only rebuilds dirty targets

That gives the frontend side the same clarity the launcher already has for backend environments.

### 7. Split "install", "build", and "serve" commands

Today several commands combine these concerns:

- `make dev-web`
- `scripts/run_dev.sh`

Separating them would make it easier to skip unnecessary work:

- `install` or `sync-env`
- `build-web`
- `serve`
- `run-dev`

This does not reduce quality. It only avoids doing all steps when only one step is needed.

## Recommended target model

The cleanest way to keep behavior correct is to model the repo as explicit targets.

| Target | Dirty when | Action |
| --- | --- | --- |
| `backend-env:<module>` | `pyproject.toml`, lockfile, requirements, Python runtime, local deps changed | reinstall env |
| `backend-run:<module>` | backend source changed and env target is clean | restart process |
| `frontend:<module>` | frontend sources, `nmtk_ui_core`, or `dart-define` inputs changed | `flutter build web` |
| `launcher-web` | `nmtk/neuro_toolkit/**`, `nmtk_ui_core/**`, or control API defines changed | `flutter build web` |
| `docker-backend:<module>` | Docker dependency layers or backend source layers changed | `docker build` |
| `docker-frontend:<module>` | Flutter dependency layers or frontend source layers changed | `docker build` |

Examples:

- If only `Neurohub/neurohub/app/services/...` changes, do not rebuild `Neurohub/frontend`; restart the backend and rerun the selected checks.
- If only `Neurohub/frontend/lib/...` changes, rebuild only `Neurohub/frontend`.
- If `nmtk_ui_core/**` changes, rebuild every frontend that uses it, plus the launcher.
- If `Neurochip/pyproject.toml` changes, reinstall the `Neurochip` backend environment before launch.
- If `nmtk/neuro_toolkit/assets/modules.json` changes, run launcher guardrails and rebuild launcher surfaces that depend on the manifest.

## Suggested implementation order

### Phase 1

Reuse the current Git diff mapping from `scripts/run_ci_local.sh` inside a shared helper so build scripts and CI use the same changed-module selector.

### Phase 2

Add frontend fingerprints and a `changed` mode to the root frontend build flow.

### Phase 3

Add bounded parallel execution for independent frontend builds and independent module CI scripts.

### Phase 4

Refactor Dockerfiles with poor cache boundaries so Docker rebuilds become selective in practice, not just in theory.

### Phase 5

Unify `run_dev`, launcher build, frontend build, and changed-only build behind one planner command.

## Bottom line

The repo already contains the core pieces needed for efficient selective rebuilds:

- Git-based changed-module selection in `scripts/run_ci_local.sh`
- backend environment fingerprinting in `nmtk/launcher_control/server.py`
- Docker layer caching in module Dockerfiles

The biggest missing piece is a shared build planner that applies those ideas consistently to frontend builds and schedules independent work in parallel.

The lowest-risk path is:

1. reuse the existing changed-module selector
2. add frontend fingerprints
3. run independent builds with bounded parallelism
4. fix the Dockerfiles that currently invalidate caches too early

That would keep the same quality bar while making both "rebuild everything" and "rebuild only what changed" materially faster.
