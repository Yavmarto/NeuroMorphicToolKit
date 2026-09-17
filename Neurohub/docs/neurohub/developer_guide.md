# Developer Guide: GitHub-Backed Neurohub Workspaces

This guide covers the GitHub workspace integration (CEL-131 series): how a
Studio workspace becomes a GitHub repository, how saves are made atomic, how
conflicts are surfaced, and how the launcher mounts the feature.

## Architecture

Neurohub keeps its public product name but now stores every shared workspace
as a **GitHub repository**. The Neurohub service is a thin, stateless API in
front of GitHub — clients never call the GitHub API directly.

```text
 NeuroStudio (launcher) / Share surface
            |
            | Neurohub API (OAuth device-flow token)
            v
        +----------------------+
        | Neurohub API         |  validation, friendly errors,
        | (stateless FastAPI)  |  mapping to GitHub resources
        +----------+-----------+
                   | GitHub REST API (repo, contents, refs)
                   v
             GitHub (repositories, commits, collaborators)
```

### Storage model

| Neurohub concept | GitHub representation |
|---|---|
| Shared workspace | One repository, private by default |
| Workspace revision | One commit on `main` |
| Workspace payload | `workspace.nmtk.json` at the repository root |
| Checksum | `.neurohub/manifest.json` (SHA-256 of the payload) |
| Sharing | Repository collaborators / organization teams |
| Publish | Repository visibility change (after confirmation) |
| Soft delete | Archive the repository |

Every save writes **both** the workspace payload and its checksum-bearing
manifest in **one atomic commit**, so a partial revision can never be observed.
The ref update is fast-forward-only, so a stale base commit fails the write
instead of racing another writer.

## Key files

- `neurohub/contracts/workspace_contracts.py` — Pydantic contracts for
  `WorkspaceCreate`, `WorkspaceUpdate`, `WorkspaceResponse`,
  `WorkspaceSummary`, `WorkspaceConflict`, and the manifest.
- `neurohub/app/services/github_client.py` — GitHub REST boundary
  (device flow, repos, contents, refs, collaborators, topics).
- `neurohub/app/services/github_workspace_store.py` — the workspace store:
  list, create, get, update (atomic save), collaborators, visibility, archive.
- `neurohub/app/routers/workspaces.py` — the HTTP surface under
  `/api/neurohub/workspaces`, including the stable `409` conflict response.
- `neurohub/app/routers/github_auth.py` — OAuth device flow
  (`/oauth/config`, `/oauth/device/start`, `/oauth/device/poll`).
- Launcher frontend:
  - `nmtk/neuro_toolkit/lib/features/neurocnl/services/neurohub_client.dart`
  - `nmtk/neuro_toolkit/lib/features/neurocnl/providers/neurohub_provider.dart`
  - `nmtk/neuro_toolkit/lib/features/neurocnl/screens/hub/neurohub_workspace_save.dart`
  - `nmtk/neuro_toolkit/lib/features/neurocnl/screens/hub/neurohub_share_surface.dart`
  - `nmtk/neuro_toolkit/lib/screens/tool_view/tool_view_workspace_controller.dart`

## The atomic save and its conflict contract

`update_workspace` in `github_workspace_store.py` is the single write path:

1. Read the current branch tip (`base_commit`).
2. If the client's `base_commit` is not the tip, raise `WorkspaceSaveConflict`.
3. Otherwise create one commit containing the manifest and the workspace
   payload (both canonical JSON), fast-forward the `main` ref, and return the
   new revision.

The API returns a stable, typed conflict instead of a generic error:

```
PUT /api/neurohub/workspaces/{owner}/{slug}
  base_commit != branch tip  →  409
{
  "detail": {
    "code": "workspace_conflict",
    "base_commit": "...",
    "remote_commit": "...",
    "recovery": ["reload", "save_copy", "resolve"]
  }
}
```

The launcher surfaces this as a real conflict UI ("This workspace changed
elsewhere") with **Reload saved version**, **Compare changes**, **Save as new
workspace**, and **Keep editing** — never a silent failure.

## Launcher integration

- `nmtk/neuro_toolkit/assets/modules.json` declares Neurohub with
  `hasFrontend: true` and `showInLauncherNav: true`, so the module appears as
  an openable native surface.
- `lib/workspace/native_surface_registry.dart` registers
  `NmtkModuleId.neurohub` → `NeurohubShareSurface`, following the same
  pattern as NeuroCNL.
- `tool_view_workspace_controller.dart::shouldOpenModule` admits `neurocnl`
  and `Neurohub`; every other manifest entry stays a backend descriptor.
- The Studio's **Save to Neurohub** action builds the portable payload from
  the live canvas/CNL state (`services/workspace_payload_builder.dart`) and
  calls `saveCurrentWorkspaceToNeurohub`, which signs in (device flow), then
  either creates a private workspace repo or updates the bound one.

## Running the tests

Backend (from the `Neurohub/` directory):

```bash
PYTHONPATH=. pytest neurohub/tests/test_github_workspace_store.py \
    neurohub/tests/test_github_auth.py neurohub/tests/test_workspace_contracts.py
ruff check neurohub/
mypy neurohub/
```

The workspace tests use an in-memory `FakeGitHubClient`, so they run without a
GitHub account.

Launcher (from `nmtk/neuro_toolkit/`):

```bash
flutter test test/features/neurocnl/screens/neurohub_ui_test.dart
flutter test test/features/neurocnl/screens/studio_utility_pill_test.dart
flutter test test/module_manifest_frontend_test.dart
flutter test integration_test/cel134_neurohub_commit_e2e_test.dart -d macos
```

The integration test (`cel134_neurohub_commit_e2e_test.dart`) drives the full
connect → list → create → commit → conflict flow against a fake Neurohub API
transport and runs on-device with no live GitHub credentials.

## One-time operator setup

A GitHub OAuth App must be registered once by the GitHub organization owner:

1. Register an OAuth App at `github.com/settings/developers`.
2. Enable **Device Flow** — it needs no client secret and no redirect URI.
3. Set the app's Client ID as `GITHUB_OAUTH_CLIENT_ID` in the Neurohub
   backend environment (see `Neurohub/.env.github.example`).

`GITHUB_OAUTH_SCOPES` defaults to `repo read:user` (required to read and
write both public and private repositories, and to resolve the signed-in
login used as the owner segment of every `neurohub://` URI).

> Note: the in-app Backend Setup flow currently has no field for module-level
> environment variables or secrets. Until one exists, the Client ID is set at
> deployment time by whoever owns the Neurohub backend.
