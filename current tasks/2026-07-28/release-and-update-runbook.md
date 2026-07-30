# Runbook: cutting a release, and how end users get it

Two audiences, two procedures. Verified against `scripts/release.sh`,
`.github/workflows/release-docker.yml`, `.github/workflows/release-desktop.yml`,
`scripts/sync_flutter_deployment_assets.py`, and the app's update paths on 2026-07-29.

---

# A. Release (maintainer, one time per version)

## A-auto. Just run this

```bash
make release-publish VERSION=1.2.0
```

`scripts/release_publish.sh` performs every step in A0–A4 below, in order, and stops on the
first failure. It asks for confirmation exactly once — immediately before the push, which is
the only irreversible part — and prints what it is about to publish. `ARGS='--dry-run'` runs
all the checks and prints the plan without writing anything; `ARGS='--yes'` skips the prompt;
`ARGS='--skip-tests'` skips `make ci`.

It also refuses to start on a dirty tree in the root or any submodule, because
`scripts/release.sh` runs `git add -A` and would otherwise commit unrelated work in progress
as part of the release.

Everything below documents what it does, so the steps can be audited or run by hand.

## A0. Pre-flight — do these before tagging

**1. Sync the Flutter deployment bundle.** The app ships its own copies of the compose files
with SHA-256 pins in `assets/deployment/deployment-manifest.json`. If a root compose file
changed since the last sync, the app deploys *stale* compose.

```bash
python3 scripts/sync_flutter_deployment_assets.py --check
```

Exit 1 → run it without `--check` and commit the result.

> **This is not enforced anywhere in CI.** The only caller of `--check` is
> `scripts/run_launcher_guardrails.sh:159`. Neither `scripts/release.sh` nor any workflow
> runs it, so a stale bundle will tag and ship silently. Treat it as a manual gate.

**2. Confirm you are on the release branch.** The repo's default branch is `dev`, not `main`.

**3. Green tests.**

```bash
make ci
```

## A1. Cut the version

```bash
make release VERSION=1.2.0
```

`scripts/release.sh` does all of this **locally, without pushing**:

- bumps versions in `neurocnl`, `Neuro-Dream-Hand`, `Neurobench`, `Neurosense`, `Neurosim`,
  `Neurochip`, `Neurohub` (their `pyproject.toml` / `frontend/pubspec.yaml`) — `Neurosim` was
  missing from this list until 2026-07-29, so releases before then never tagged it
- bumps `nmtk/neuro_toolkit/pubspec.yaml` and `nmtk_ui_core/pubspec.yaml`
- bumps `suite_api/pyproject.toml`, keeping the source-visible backend package
  number aligned with the release stamped into backend images
- regenerates each `CHANGELOG.md`
- commits `chore(release): 1.2.0` and tags `v1.2.0` **in every submodule and in the root repo**

Semver only — `1.2.0` or `1.2.0-beta.1`. Do not prefix with `v`; the script adds it.

## A2. Push

`release.sh` used to sign off by printing `git push origin main --tags`. That was wrong twice
over — the branch is `dev`, and it ignored every submodule tag the script had just created.
Corrected 2026-07-29 to point at `make release-publish`.

```bash
git submodule foreach 'git push origin HEAD --follow-tags || true'
```

```bash
git push origin dev --follow-tags
```

Push submodules first, so the root commit never points at objects the remote lacks.

## A3. What CI does on the `v*` tag

| Workflow | Produces | Runner |
|---|---|---|
| `release-docker.yml` | 9 images → `ghcr.io/completed-spoon-6/neuromorphictoolkit/<svc>`, tagged `latest`, `1.2.0`, `1.2`, `sha-…`, each stamped with `NMTK_VERSION=1.2.0` | GitHub-hosted |
| `release-desktop.yml` | Windows `.exe`, macOS `.dmg`, Linux `.AppImage`, then a **GitHub Release** with generated notes | self-hosted |

`prerelease` is set automatically when the tag contains `beta` or `rc`, and the app's stable
update channel skips prereleases — so a `-beta.1` tag will not prompt stable users.

## A4. Verify before you tell anyone

1. **GHCR has the new tags** — the in-app update pulls `:latest`, so this must be green first.
2. **The GitHub Release exists** — this is what the app reads to detect updates.
3. Spot-check the stamp on a pulled image:
   ```bash
   docker run --rm ghcr.io/completed-spoon-6/neuromorphictoolkit/suite-api:1.2.0 printenv NMTK_VERSION
   ```

### ⚠ The one race to know about

`UpdateService._fetchRepositoryRelease` reads `/releases` and **falls back to `/tags`**. Your
tag exists on GitHub the moment you push, so the in-app update badge can appear *while
`release-docker.yml` is still building*.

It does not break anything, but it is confusing: the app deploys `:latest`
(`_releaseImageTag` is a hardcoded const), so an early tap pulls the **previous** release,
reports success, and leaves the badge showing. Either wait for the docker workflow to go
green before announcing, or expect that window. `release-desktop.yml` runs on self-hosted
runners across three platforms, so in practice images finish well before the Release appears —
the risk window is only against the raw tag.

---

# A-dev. The daily loop (not a release)

```bash
make dev-update
```

For testing unreleased source against the dev backend, many times a day. Runs the
changed-module tests first — a failure aborts *before* the sync, so a broken change never
reaches the host — then syncs and does the minimum to make it live.

The minimum is not uniform, which is the point: only `suite_api` has a repo bind mount, so
`suite_api/**` and `neurocnl/backend/**` need no container work at all, while a `workers/**`
edit needs a rebuild (workers get `--reload` but no bind mount) and `neurocnl/neurocnl/**`
needs one too (pip-installed non-editable). See the table in root `AGENTS.md`, or ask:

```bash
make dev-update ARGS='--explain workers/neurocnl_physics/main.py'
```

No state file — `rsync --itemize-changes` reports exactly what differed from the host.
`ARGS='--dry-run'` decides and prints without changing anything;
`ARGS='--no-rebuild'` syncs and warns instead of rebuilding.

---

# B. End-user update (in the app, no terminal)

There are two independent things a user updates. Neither needs a shell.

## B1. The backend — one tap, keeps your data

1. Open the app.
2. Go to **Backend Setup**.
3. The connected backend's current version is shown at the top. Source builds
   are labelled **Development build**.
4. If a newer release exists, a card appears below it:
   *"Backend update available — 1.2.0"*, noting that workspaces and notebooks are kept and
   that the backend restarts.
5. **Finish any running training first** — the containers restart.
6. Press **Update backend**. It validates the connection, then redeploys in place:
   `compose down` → `pull` → `up -d`, with health checks. Progress shows live.
7. Done. No credentials to re-enter — SSH keys and passwords are already in the OS keychain.

**Nothing is deleted.** The update always runs with clean-install off; that flag is the only
thing that turns `compose down` into `down -v`, which would remove workspaces, notebooks, and
the data volumes.

**When no card appears**, that is deliberate — every uncertain case stays silent rather than
prompting wrongly:

| Situation | Why no card |
|---|---|
| Already current | Nothing to do |
| Backend built from source (reports `dev`) | No release to compare against |
| Backend unreachable | Cannot tell what is running |
| Backend predates version reporting | Same |
| No internet / GitHub rate-limited | Cannot tell what is newest |

## B2. The app itself — download and install

On launch, if a newer app release exists, a **"Launcher Update Available"** dialog appears with
the release notes and two buttons: **Later**, or **Download Now** (opens the GitHub Release in
the browser).

Then install it the normal way for the platform: macOS `.dmg`, Windows `.exe`, Linux
`.AppImage`.

> **This step is manual by design today.** `UpdateService.performDifferentialUpdate` is a stub
> (a simulated progress bar with `debugPrint`), so there is no silent in-app self-update for the
> launcher. It is not a terminal step, but it is a download-and-install step. If you want it to
> be one tap like the backend, that is a real feature to build — the platform installers and
> the release feed already exist.

## B3. Order

Update the **app first**, then the backend. A newer app understands an older backend; the app
is what drives the backend update.
