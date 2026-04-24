# Launcher Install/Start Consistency Plan

Date: 2026-04-23

## Summary

The current launcher mixes two different concepts:

- durable module presence: not installed vs installed
- transient runtime activity: installing, starting, running, stopping, updating, error

That split leaks into the UI and creates two confusing behaviors:

1. A module can disappear from the dashboard while it is installing because the dashboard and catalog are filtered from different state subsets.
2. Pressing `Start` can silently trigger a reinstall or repair path, so `Start` is not reliably just `Start`.

The launcher should move to one module library surface with stable cards, explicit action semantics, and a visible repair state. The reinstall behavior is currently caused by auto-repair logic in the launcher control service, especially environment fingerprint drift and failed import preflight.

## What Is Happening Today

### 1. Dashboard and catalog disagree about where a module belongs

In [nmtk/neuro_toolkit/lib/providers/module_provider.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/providers/module_provider.dart), the provider defines:

- `installedModules` as `installed`, `starting`, `running`, `stopping`, `degraded`, `error`
- `availableModules` as `notInstalled`, `installing`

This means `installing` is treated as catalog-only, not dashboard-visible. The result is exactly the symptom described by users: start or install a module, then the card vanishes from the dashboard and only appears in the catalog.

The UI surfaces reinforce the split:

- [nmtk/neuro_toolkit/lib/screens/dashboard.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/screens/dashboard.dart) renders only `installedModules`
- [nmtk/neuro_toolkit/lib/screens/catalog.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/screens/catalog.dart) renders the full module list but treats install/start/update actions differently from the dashboard

### 2. `Start` can trigger reinstall/repair

The launcher control service does not treat `start` as a pure runtime action.

In [nmtk/launcher_control/server.py](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/launcher_control/server.py):

- `start_module()` calls `_start_sync()`
- `_start_sync()` calls `_preflight_module(module, allow_repair=True)`
- `_preflight_module()` can reinstall automatically when:
  - module python is missing
  - environment fingerprint changed
  - import probe fails

That means the user clicks `Start`, but the system may do `Repair/Reinstall + Start` instead.

### 3. Reinstall is especially likely when environment fingerprint changes

The strongest current root cause is the environment fingerprint logic in `server.py`.

`_compute_environment_fingerprint()` hashes:

- Python version
- absolute `pythonPath`
- absolute `installDir`
- absolute `runDir`
- install/start strategy
- uvicorn target
- hashes of environment files such as `pyproject.toml`, `poetry.lock`, `requirements.txt`

The problem is that absolute environment paths are not stable enough to serve as the primary reinstall trigger.

For Poetry-based modules in this repo, this is particularly risky because the interpreter path may move between:

- in-project `.venv`
- fallback Poetry env path
- a recreated environment after cleanup

Any such path drift changes the fingerprint, and `_preflight_module()` then treats that as `reinstall required before launch`.

### 4. Startup also reinstalls when imports fail

Even if the environment exists, `_preflight_module()` will reinstall once when required imports fail. That makes the launch path feel non-deterministic from the UI perspective:

- UI says `Installed`
- user presses `Start`
- backend decides import probe failed
- backend reinstalls
- user experiences `Start` as another install

### 5. "Reinstall submodules" is really reinstalling sibling local dependencies

The launcher is not primarily reinstalling git submodules here. It is reinstalling local sibling Python packages during module install.

In `_install_sync()`:

- every install or repair runs local dependency installs for entries in `localDeps`
- then it runs the module install itself

So when a repair is triggered, local sibling packages can be reinstalled as part of the same operation. From the user perspective, that looks like "it reinstall the submodules again".

## Why This Is Confusing For Users

The current model asks users to infer too much:

- whether a module is installed permanently or only for this session
- whether `Start` is a runtime action or a hidden repair/install action
- why a module moved from one screen to another
- whether an error means `repair`, `reinstall`, `start failed`, or `optional capability degraded`

The product language also does not clearly separate:

- `Install`: prepare environment
- `Start`: run backend/service
- `Open`: open workspace
- `Repair`: rebuild broken environment
- `Update`: upgrade installed environment

## Proposed Product Direction

## Option Chosen

Merge the dashboard and catalog into a single `Modules` surface.

Keep workspace tabs and module detail views separate, but stop splitting the module inventory itself into two navigational destinations.

This is the cleanest fix because the current confusion is caused by state partitioning more than by missing badges or copy tweaks.

## Single-Surface Module Library

The main screen should show all modules in one list with stable placement.

Recommended structure:

1. `Needs Attention`
2. `Installed`
3. `Available`

Each module card should remain visible in its section while an operation is in progress. Do not move or remove the card just because the status changed from `installed` to `installing` or `starting`.

For example:

- installed + starting: stays in `Installed`, shows `Starting`
- installed + repairing: stays in `Needs Attention` or `Installed`, depending on design choice, but remains visible in-place
- not installed + installing: stays in `Available`, shows `Installing`

This is the key rule: transitions should update the card, not relocate the card.

## Recommended State Model

Replace the single mixed status with two user-facing axes:

### Presence state

- `Not installed`
- `Installed`
- `Repair required`

### Activity state

- `Idle`
- `Installing`
- `Repairing`
- `Starting`
- `Running`
- `Stopping`
- `Updating`

### Health state

- `Healthy`
- `Degraded optional capability`
- `Error`

The implementation can still keep an internal enum, but the UI should present these as separate concepts. Right now one enum is doing too much work.

## Action Semantics

Action labels should be strict:

- `Install`: create or refresh the environment only
- `Start`: start the module only
- `Open`: open the module UI/workspace
- `Repair`: rebuild environment without pretending it is a normal start
- `Update`: move installed environment to a newer version
- `Uninstall`: remove environment

Most important rule:

`Start` should not silently reinstall.

If preflight finds the environment is broken, the backend should return `repair required` and the UI should show:

- primary action: `Repair`
- secondary action: `Start anyway` only if that is genuinely safe

If a one-click recovery flow is desired, label it explicitly as `Repair and Start`, not `Start`.

## UX Changes To Make Behavior Clear

### 1. Replace dashboard and catalog with one Modules page

The page should include:

- search
- filters such as `Installed`, `Running`, `Needs Attention`, `Available`
- stable cards with primary action and secondary menu
- one-line explanation of what `Install` means

Suggested copy:

`Install prepares this module on this machine. Start runs it for this session.`

### 2. Add explicit persistence copy after install

When install completes, show a durable confirmation:

`Installed on this machine. You can start it later without reinstalling unless the environment changes or needs repair.`

This is important because users currently do not know whether install is persistent.

### 3. Show reasoned status, not just generic status

Examples:

- `Installed`
- `Installed, repair required`
- `Running`
- `Degraded optional capability`
- `Start blocked: repair required`
- `Installing dependency environment`

### 4. Show operation provenance

When an automatic backend action occurs, surface why:

- `Repair required because the module environment changed`
- `Repair required because Python executable was missing`
- `Repair required because required imports failed`

Without this, reinstall feels random.

### 5. Keep cards visible during transitions

A module should never disappear from the main list because it moved from one enum bucket to another.

### 6. Keep workspace/open state separate from installation state

Whether a module is open in a tab is not the same thing as whether it is installed or running. Those should not drive which inventory screen the module appears on.

## Backend Changes Needed

## 1. Stop auto-repair inside `start`

Current behavior:

- `_start_sync()` calls `_preflight_module(... allow_repair=True)`

Recommended behavior:

- `start` should call preflight with `allow_repair=False`
- if preflight fails, return structured repair metadata
- UI should offer `Repair` explicitly

This is the highest-value product fix because it aligns backend semantics with the visible button label.

## 2. Soften the environment fingerprint trigger

Current fingerprint includes absolute paths:

- `pythonPath`
- `installDir`
- `runDir`

Recommended fingerprint inputs:

- Python major/minor version
- dependency manifest hashes
- lockfile hashes
- install strategy
- start strategy
- uvicorn target
- maybe package-manager type (`pip` vs `poetry`)

Do not use absolute interpreter path as a reinstall trigger.

At most, keep absolute paths as diagnostics, not as fingerprint identity.

## 3. Separate `installed evidence` from `repair evidence`

On startup, the launcher should persist and compute:

- installation exists
- environment present
- environment valid
- runtime healthy

A module with a present but invalid environment should not be shown as `Not installed`. It should be shown as `Installed, repair required`.

That distinction matters because users interpret `Not installed` as "my previous install was lost".

## 4. Track repair reasons structurally

Instead of only setting a generic `healthStatus`, persist a repair reason enum such as:

- `missing_python`
- `fingerprint_changed`
- `required_import_failed`
- `install_incomplete`

Then map that to specific UI copy.

## 5. Avoid reinstalling local sibling dependencies unless needed

If the launcher has to repair one module, it should not blindly reinstall all local sibling dependencies every time unless those dependencies are part of the actual repair scope.

Recommended options:

- cache installed local dependency versions/fingerprints
- reinstall local deps only when their source hash changed
- or treat local deps as their own repairable environment units

This is secondary to the UI fix, but it will reduce "everything reinstalls again" perception.

## Implementation Plan

### Phase 1: Make behavior honest

- Merge `Dashboard` and `Catalog` into one `Modules` route
- Keep module cards stable during transitions
- Add explicit `Repair required` state
- Change `Start` so it does not auto-repair
- Surface repair reasons in UI text

### Phase 2: Make persistence understandable

- Add post-install copy that explains install persists across app restarts
- Add per-card metadata like `Installed on this machine`
- Show `Last installed` and `Last started` timestamps if useful

### Phase 3: Reduce unnecessary repairs

- Redefine environment fingerprint to avoid absolute path churn
- Separate environment existence from environment validity
- Reduce repeated local dependency reinstalls

## Concrete Code Areas To Change

Frontend:

- [nmtk/neuro_toolkit/lib/providers/module_provider.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/providers/module_provider.dart)
- [nmtk/neuro_toolkit/lib/screens/dashboard.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/screens/dashboard.dart)
- [nmtk/neuro_toolkit/lib/screens/catalog.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/screens/catalog.dart)
- [nmtk/neuro_toolkit/lib/models/module.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/models/module.dart)
- [nmtk/neuro_toolkit/lib/routing/router.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/lib/routing/router.dart)

Backend:

- [nmtk/launcher_control/server.py](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/launcher_control/server.py)
- [nmtk/neuro_toolkit/module_states.json](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk/neuro_toolkit/module_states.json)

## Recommended Decision

Make one `Modules` page the source of truth, keep cards stable, and split `installed` from `running` and `repair required`.

On the backend, stop repairing during `Start` and stop using absolute environment paths as fingerprint identity.

That combination will fix both user-visible problems:

- modules will no longer disappear between dashboard and catalog
- users will understand whether they are installing, repairing, or starting

It will also address the likely reinstall root cause instead of only papering over it with UI copy.
