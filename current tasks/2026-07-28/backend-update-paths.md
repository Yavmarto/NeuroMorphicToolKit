# How the backend gets updated — established 2026-07-29

Written because the wrong answer was proposed first (a shell script plus a systemd timer on
the backend host) and the correction is worth not re-deriving.

## The rule

**End users operate the app only. There is no supported end-user path involving SSH, `make`,
a shell script, `docker`, or systemd.** Terminal targets exist solely to push *unreleased*
source to a dev host. See root `AGENTS.md`, "Updating the backend".

## The end-user path already existed

Nothing here was built from scratch; it was already in the app and merely unadvertised:

- `client_deployment_service.dart:335` — `deploy(DeploymentRequest)`, pushes the compose
  bundle from `nmtk/neuro_toolkit/assets/deployment/` over SSH (`dartssh2`) and runs
  `install.sh` on the host, streaming progress phases and health-verifying Suite API,
  launcher-control and Jupyter.
- `assets/deployment/install.sh` — `compose down` → `pull` → `up -d`. Non-destructive: `down -v`
  only when `CLEAN_INSTALL=true`.
- `deployment_persistence.dart:71,129` — SSH credentials and trusted host keys persisted per
  target in `FlutterSecureStorage`, so a re-deploy needs no re-entry.

So **re-running Backend Setup was always a complete update.** The only missing piece was
that nothing could tell the user they were behind.

## What was added

| Piece | Where |
|---|---|
| Image stamps its release | `suite_api/Dockerfile` `ARG/ENV NMTK_VERSION`, fed by `release-docker.yml`'s `build-args` from `steps.meta.outputs.version` |
| Backend reports it | `suite_api/routers/health.py` — `GET /api/suite/health` now returns `version` |
| App reads it | `ControlApiService.fetchBackendVersion()` + `suiteApiBaseUri` |
| Newest release lookup | `UpdateService.checkForBackendUpdate(runningVersion)` |
| Wiring | `backendUpdateProvider` in `lib/providers/riverpod_providers.dart` |
| UI | update banner + one-tap action in `backend_setup.dart` (`_buildUpdateBanner`, `_updateBackend`) |

## Decisions that cost time — don't redo them

- **`"dev"` is never updatable.** An unstamped/source build reports `"dev"`; there is no
  release to compare it with, so no badge. Every other failure (backend unreachable, field
  absent, GitHub down, malformed body) also resolves to null → say nothing. A false "update
  available" is worse than silence.
- **`cleanInstall` must stay false on an update.** It is the only thing separating
  `compose down` from `down -v`, which deletes `launcher_control_state`, `jupyter_notebooks`,
  and the data volumes. There is a widget test pinning this.
- **The GitHub lookup belongs in `UpdateService`, not `launcher_control`.** A version of this
  was first built server-side (`backendRemoteVersion` in `get_settings()`, an injectable
  resolver, a cached field) and then reverted: `UpdateService` already owned the monorepo URL
  `Completed-Spoon-6/NeuroMorphicToolKit`, the GitHub headers, the timeout, and
  `isNewerVersion`, and the app must reach GitHub anyway for its own launcher check. The
  server-side version meant two GitHub clients and two copies of the repo URL.
- **Not automatic, by decision.** A silent update restarts containers under the user — wrong
  mid-training, and it removes any way to decline a bad release. Notify, then one tap.
- **`launcher_control.update_module` is the wrong seam.** `module_install.py:408`
  (`_install_sync`) builds a per-module venv and pip-installs into a local checkout — the
  native-module model. It has no relationship to the compose stack serving `/api/neurocnl/*`,
  and neurocnl's `modules.json` entry is `startStrategy: none` because suite_api serves it.

## Still open

- `make docker-ex-deploy` fails on pre-existing containers. Needs the actual error text
  before a fix; developer-only, so it blocks nothing above.
- `192.168.2.34` has something bound to port 9000 that accepts TCP and returns empty
  replies. `.51` is the real dev backend (`AGENTS.md`). Worth shutting `.34` down.
