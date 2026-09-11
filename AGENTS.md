# NeuroMorphicToolKit Agent Router

This checkout contains the suite control plane plus the individual product modules. Default to one writable top-level module per task; if a change crosses a contract boundary, read both modules' `AGENTS.md` files and both sides' spec or ADR docs before writing.

## Talking to the User — Plain English, Short

Write to the user the way you would explain it to a competent colleague who has not read the
code. Aim for under 150 words for a normal task. The work can be deep; the write-up is short.

Do:

- **Lead with the answer.** First sentence says what was wrong or what changed. No preamble, no
  restating the request back.
- **Plain English.** If you must name a symbol, file, or error code, say what it does in ordinary
  words in the same sentence: "the per-NP check (the thing that caps a layer at 256 neurons)".
- **Say the user-visible effect**, not the internal mechanism, unless asked. "Every MNIST network
  was rejected" beats "the population iterator lacked a role predicate".
- **One clickable link per file** you changed, not a tour of every hunk.
- **Report failures plainly.** "3 tests fail, here's the output" — never imply green when it is
  not. If you skipped part of the scope, say which part and why.
- **Give commands in a fenced `bash` block**, one command per block.

Do not:

- Pad with "Great question", "You're absolutely right", "Let me explain", or a summary of what
  you are about to say.
- List every file you read, every search you ran, or every option you rejected.
- Re-explain something already established earlier in the conversation.
- Narrate self-correction. Fix it and move on.
- Use a table or nested bullets where two sentences would do.

Example — too long:

> I've completed a thorough investigation of the Akida deployment pipeline. After examining the
> planner, the capability checkers, and the contract layer, I discovered that the root cause of
> the issue you're experiencing is that `plan_akida_exportability` iterates over
> `ir.populations.values()` and compares each `pop.size` against `AKIDA_LIMITS.MAX_NEURONS_PER_NP`
> without first filtering on `PORT_POPULATION_TYPES`, which means...

Same thing, right length:

> The 784-pixel MNIST input was being counted as a layer of neurons, so it blew the 256-per-layer
> Akida limit and every MNIST network was rejected — no setting could fix it. Input and output
> ports are now skipped in that check. Rebuild and `784 → 256 → 10` works.

The `<end_of_task_reporting>` block in `CLAUDE.md` still applies: close with the problem, the
fix, and where to look, two sentences each, plain English.

## End-User Convenience — Top Priority

**End-user convenience is the highest product priority in this codebase.**

When multiple valid solutions exist, always choose the one that requires the least action from the end user. Concretely:
- Prefer auto-detection and auto-configuration over requiring the user to set anything up manually.
- Prefer sensible defaults that work out of the box over options that require the user to know internal port numbers, service names, or deployment details.
- When a service can be discovered automatically, do so — never require the user to type in a URL or port they shouldn't need to know.
- Prefer changes to config files (docker-compose, modules.json, server defaults) over changes that require UI interaction or user knowledge.
- Error messages must be actionable: say what failed, why, and exactly what to do — never expose raw exception strings to the end user.
- When choosing between a simple UI action and a code fix that makes the action unnecessary, fix the code.

Read before edit:

- Before writing code anywhere in this repo, read `CODING_STYLE_GUIDE.md`.
- If editing `neurocnl/**`, read `neurocnl/AGENTS.md`.
- If editing `Neurochip/**`, read `Neurochip/AGENTS.md`.
- If editing `Neurobench/**`, read `Neurobench/AGENTS.md`.
- If editing `Neuro-Dream-Hand/**`, read `Neuro-Dream-Hand/AGENTS.md`.
- If editing `Neurosense/**`, read `Neurosense/AGENTS.md`.
- If editing `Neurohub/**`, read `Neurohub/AGENTS.md`.
- If editing `nmtk/**`, read `nmtk/AGENTS.md`.
- If editing `nmtk/neuro_toolkit/lib/ui_core/**`, read `nmtk/neuro_toolkit/lib/ui_core/AGENTS.md`.
- If editing `neurocli/**`, read `neurocli/AGENTS.md`.
- If editing root-owned `docs/**`, `scripts/**`, `tests/**`, `monitoring/**`, or root config files, stay in the root repo and read the owning module `AGENTS.md` for every contract you touch.
- If editing more than one top-level module, name the write set explicitly and run the owning checks plus `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py`.

Backend endpoint smoke testing:

- For backend endpoint work, use `docs/agents/nmtk-backend-smoke.md` and `python3 scripts/backend_endpoint_smoke.py` to probe `/health`, inspect `/openapi.json`, and call changed endpoints against the manifest-defined module ports.
- Treat `nmtk/neuro_toolkit/assets/modules.json` as the source of truth for module ids, ports, run paths, and uvicorn targets; do not maintain a separate static endpoint catalog.

Launcher and control-plane guardrails:

- For changes under `nmtk/**`, root launcher manifests such as `nmtk/neuro_toolkit/assets/modules.json`, `nmtk/neuro_toolkit/assets/remote_modules.json`, and root compose files, `scripts/**`, or root `tests/**` that affect launcher behavior, module lifecycle behavior, or suite-visible startup semantics, run `python3 scripts/launcher_control_service.py --doctor --json`.
- Use `bash scripts/run_launcher_guardrails.sh` as the canonical local enforcement wrapper for launcher and control-plane work. Use `bash scripts/run_launcher_guardrails.sh --with-integration` when the change alters module contracts or suite-visible startup behavior.
- Treat launcher doctor `fatalCount > 0` as a blocker unless the task is explicitly to diagnose or fix that failure.
- Launcher work is not complete until launcher doctor and launcher unit coverage pass.
- Report launcher doctor outcomes explicitly as either `preflight failed` or `degraded optional capability`; do not collapse both into a generic startup error.
- Keep launcher UI state changes, module manifest changes, and launcher verification updates in the same change when they describe the same behavior. If a launcher-visible state transition depends on manifest metadata, update both surfaces together.
- If `nmtk/neuro_toolkit/assets/modules.json` changes, update the launcher Dart models, launcher tests, and any consuming helper scripts in the same change.
- Do not introduce a new install or startup strategy without doctor or preflight coverage.

Knowledge Management (Open Brain):

- **Always check Open Brain** (Knowledge Items and Brain logs) at the start of a task to retrieve relevant context, architectural decisions (ADRs), and historical workstreams.
- **Update Open Brain** after completing a task if new durable knowledge, decisions, or important context were established. Use the `capture_thought` tool if available, or manually update Knowledge Items (KIs).
- Refer to `docs/archive/open-brain-import.md` for guidelines on how to organize and categorize knowledge for the Open Brain.
- **Cross-file invariant rule**: After any change that creates or relies on a cross-file invariant
  (two lists that must stay in sync, a naming convention, a state-machine contract, a parallel
  enum + string list), write a GBrain entry:
  ```bash
  gbrain write --title "<what must stay in sync>" --body "<why and how>"
  ```
  This is in addition to code-level asserts and tests — it surfaces intent during future AI-assisted
  searches before any code is read. Example invariants that were missed until caught by review:
  `kStudioPipelineStepNames` ↔ `SnnWorkflowPhase` enum, launcher module IDs ↔ `modules.json`.

## Code Search

Use `semble search` to find code by describing what it does or naming a symbol/identifier, instead of grep:

```bash
semble search "authentication flow" ./my-project
semble search "save_pretrained" ./my-project
semble search "save model to disk" ./my-project --top-k 10
```

Use `semble find-related` to discover code similar to a known location (pass `file_path` and `line` from a prior search result):

```bash
semble find-related src/auth.py 42 ./my-project
```

`path` defaults to the current directory when omitted; git URLs are accepted.

If `semble` is not on `$PATH`, use `uvx --from "semble[mcp]" semble` in its place.

## Workflow

1. **Check Open Brain** for existing context and relevant Knowledge Items.
2. **Check the `current tasks` folder** at the root of the repository for ongoing or past dated tasks. When saving or creating new tasks, always place them in this directory under a subfolder named with the current date.
3. Start with `semble search` to find relevant chunks.
4. Inspect full files only when the returned chunk is not enough context.
5. Optionally use `semble find-related` with a promising result's `file_path` and `line` to discover related implementations.
6. Use grep only when you need exhaustive literal matches or quick confirmation of an exact string.
7. **Apply autofixers and run tests** for the language you are working in (e.g., `ruff check --fix .` and `ruff format .` for Python, `dart fix --apply` and `dart format .` for Dart) to ensure the codebase remains green before finishing a task.
8. **Clean up workspace**: Always delete any temporary scripts, patch files, or intermediate artifacts (like `patch_*.py`) created during execution. Leave the repository clean.
9. **Update Open Brain** with any new durable knowledge or architectural changes upon task completion.
<end_of_task_reporting>
10. **End of Task Reporting**: When you finish a task, always report back to the user with the following exact format. Every answer must include:
   - A short description of what the problem is (exactly 2 sentences).
   - How it was solved (exactly 2 sentences).
   - Where to notice the difference and restart info (exactly 2 sentences).
   All in plain English.
</end_of_task_reporting>

## Remote Testing Configuration

For dev, `REMOTE_HOST=moosebun2@192.168.2.90` can be used. The server address is `192.168.2.90`.

To run the app, use:
```
flutter run -d macos
```
This runs the Flutter macOS app directly, matching the end-user experience as closely as possible. Do not suggest or use `make docker-ex-m` or `scripts/run_dev.sh` — those workflows are no longer used.

## Updating the backend

**End users never touch a terminal. There is no supported end-user path involving SSH,
`make`, a shell script, `docker` commands, or systemd.** The app owns the entire lifecycle:
Backend Setup deploys it, and an "Update backend" banner appears there when a newer release
is published. Never write an end-user instruction that starts with a command.

If an in-app path is missing for something a user needs, that is a gap to build in the app —
not a reason to hand them a command.

### End-user path (in-app only)

The app pushes the compose bundle in `nmtk/neuro_toolkit/assets/deployment/` over SSH with
`dartssh2` and runs `install.sh` on the host: `compose down` → `pull` → `up -d` →
health-verify. Credentials and trusted host keys are already persisted per target in
`FlutterSecureStorage`, so an update needs no re-entry and no re-typing of a host.

- `client_deployment_service.dart:335` — `deploy(DeploymentRequest)`, the single entry point.
- `backendUpdateProvider` (`lib/providers/riverpod_providers.dart`) — compares the release
  the backend reports at `/api/suite/health` against the newest GitHub release, via
  `UpdateService.checkForBackendUpdate`.
- `cleanInstall` must stay **false** for an update. It is the flag that turns
  `compose down` into `down -v`, which takes the user's workspaces and notebooks with it.
- A backend built from source reports version `"dev"` and is deliberately never offered an
  update — there is no release to compare it with.

### Developer paths (terminal, unreleased source only)

These exist to push *unreleased* source to a dev host. They are not end-user instructions.

The dev backend runs on `192.168.2.90`, not locally — a local edit to any Python file under
`neurocnl/backend/`, `suite_api/`, or `workers/` does nothing until it is synced there.

```bash
make dev-update
```

One command for the daily loop. It runs the changed-module tests **first** (a failure aborts
before anything reaches the host), syncs, then does the *minimum* to make the change live.
Defaults to `moosebun2@192.168.2.90`; override with `REMOTE_HOST=`. Flags go through
`ARGS=`, e.g. `ARGS='--skip-tests'` or `ARGS='--dry-run'`.

**The dev topology is not uniform, which is the whole reason this script exists:**

| What you edited | What happens | Why |
|---|---|---|
| `suite_api/**`, `neurocnl/backend/**` | nothing needed | bind-mounted into `suite_api`; `uvicorn --reload` picks it up |
| `neurocnl/neurocnl/**`, `Neurohub/**`, `Neurosense/**`, `Neurobench/neurobench/**` | rebuilds `suite_api` | pip-installed non-editable (`suite_api/Dockerfile:30,35,42,50-51`) — rsync moves the source but Python never sees it |
| `workers/<name>/**` | rebuilds that one worker | workers get `--reload` but **no** bind mount, so the reloader watches the baked-in code |
| `nmtk/launcher_control/**`, `nmtk/neuro_toolkit/assets/**` | restarts `launcher-control` | bind-mounted, applied on restart |
| any `Dockerfile` | rebuilds that service | |
| `docker-compose*.yml` | recreates the stack | and warns that the app's asset bundle needs re-syncing |

**Only backend runtime paths reach the host.** `scripts/rsync-excludes.txt` is an
*allowlist*: it ends in `- *`, so a path is synced only if a `+` rule above names it. The
included set is `docker-compose*.yml`, `Dockerfile*`, `.dockerignore`, `suite_api/`,
`workers/`, `docker/`, `neurocnl/`, `Neurochip/`, `Neurohub/`, `Neurosense/`,
`Neurobench/neurobench/`, `nmtk/launcher_control/`, `nmtk/neuro_toolkit/assets/` and
`scripts/launcher_control_service.py` — every one of them traced to a Dockerfile `COPY`, a
compose bind mount, or a path the backend reads at runtime. The `Makefile`, this file, all
docs, `tests/`, `tools/`, the Flutter app and the rest of `scripts/` never
leave your machine. Rules are first-match-wins, so the junk block must stay above the `+`
block. Adding a new backend directory means adding a `+` rule, or it silently never ships.

Unlisted paths are also protected from `rsync --delete`, which is deliberate: host-owned
state (`.env` from `make secrets-init`, `shared_assets/` uploads, `*.db`, `logs/`) survives
every sync. Do **not** add `--delete-excluded` to get a tidy deploy dir — it would delete
exactly those. To clear files a previous, wider filter left behind, list the host's deploy
dir and remove the stale entries by name:

```bash
ssh moosebun2@192.168.2.90 'ls -A ~/nmtk-deploy'
```

It needs no state file — `rsync --itemize-changes` reports exactly which paths differed from
the host. To ask why it decided something, or to check the table without touching a host:

```bash
make dev-update ARGS='--explain neurocnl/neurocnl/training/dag_topology.py'
```

`make docker-ex-deploy REMOTE_HOST=…` still exists for the rare case where you want every
image rebuilt from scratch. `make dev-update` supersedes it for everyday work, and replaced
the older `make backend-update`.

**If a change still doesn't appear after a sync**, restart the `suite_api` container before
assuming the patch is wrong — that distinguishes a stale reloader from a bad fix.

**Build Android APK and copy to Box** (developer-only; not an end-user path):

```bash
scripts/build_and_deliver_apk.sh
```

Builds `nmtk/neuro_toolkit` as a **profile** build by default (`--debug` and `--release` are
also available as flags) and copies the Android APK into the local Box sync folder (default
`~/Library/CloudStorage/Box-Box/NMTK/Builds`; override with `--box-dir` or `NMTK_BOX_DIR`).
Pass `--with-dmg` to also build the macOS DMG installer, or `--dmg-only` for DMG only.
Use `--skip-build` to copy existing artifacts without rebuilding.
If Box is not installed or synced, the copy is skipped with a warning and the script still exits 0.
A DMG build failure does not block APK delivery when `--with-dmg` is used.
The macOS DMG path (`make build-macos-dmg-signed` → `create-dmg.sh`) uses the same Box copy
helper and the same `NMTK_BOX_DIR` default.

#### Port 8002 on the dev host belongs to the native Akida service

`192.168.2.90` runs a real BrainChip Akida card served by the native `neurochip.service`
systemd unit, which owns **port 8002**. The containerized `neurochip-hw-worker` has no Akida
SDK (`workers/neurochip_hw/Dockerfile`), so it can never serve hardware routes there — it only
fights for the port. `docker-compose.akida-native.yml` exists to park it in a `donotstart`
profile and repoint `suite_api`/`launcher-control` at `host.docker.internal:8002`.

- `make dev-update` detects this automatically (`systemctl is-active neurochip.service`, with a
  port probe as fallback) and applies the overlay. Force with `AKIDA_NATIVE=1` / `=0`.
- `make docker-ex-deploy` needs `AKIDA_NATIVE=1` passed **explicitly**, or it will try to bind
  8002 and fail with `address already in use`. `Makefile:121` also uses that flag to keep 8002
  out of its `fuser -k` eviction list.
- **Never evict port 8002 on that host.** `sudo fuser -k 8002/tcp` kills the Akida service the
  whole box exists to provide. `dev-update --evict-ports` refuses to touch it for this reason.

### Cutting a release

The backend version is part of the unified NMTK release number. Backend-facing
changes must keep `suite_api/pyproject.toml` release-ready; do not edit
`NMTK_VERSION` in code or compose files, because release images receive it from
the root `vX.Y.Z` tag. Always use the release tooling below, which updates the
launcher, shared UI, and Suite API package versions together; verify the running
value in **Backend Setup** or `GET /api/suite/health`.

```bash
make release-publish VERSION=1.2.0
```

Pre-flight gates (deployment-bundle sync, notices, `make ci`) → bump/changelog/tag via
`scripts/release.sh` → one confirmation showing exactly what will be pushed → push submodules
then root → watch both CI workflows → verify the images and the GitHub Release.

It refuses to start on a dirty tree, because `scripts/release.sh` runs `git add -A` in every
repo and would otherwise sweep unrelated work into the release commit. `ARGS='--dry-run'`
runs every check and prints the plan without writing anything.
