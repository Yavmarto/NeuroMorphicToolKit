# 0031: Root Flutter App Owns the NeuroStudio Runtime

## Status
Accepted

## Context
NMTK shipped one desktop application, but the native NeuroStudio feature still created a nested
`MaterialApp`, theme provider, localization boundary, and optional standalone connection flow.
That left two application lifecycles in one widget tree and allowed global settings or overlays to
diverge even though NeuroStudio was already compiled directly into the launcher.

## Decision
The root `nmtk/neuro_toolkit` package is the sole Flutter executable and owns the process-wide
`MaterialApp`, theme, localization, accessibility scaling, shortcuts, backend setup, updates, and
error lifecycle. `neurocnl/frontend` remains the internal `neurocnl_studio` feature package and
exposes `initializeNeurocnlFeature()` plus `NeurocnlShellAdapter`.

The adapter renders a routed `NeurocnlStudioSurface` beneath the root app using
`Router.withConfig`. It requires the root-selected backend URL, session token, and server-edit
action. NeuroStudio's standalone entrypoint and platform runners are removed; its GoRouter paths,
workspace restoration, storage format, module id, and backend contracts remain unchanged.

## Consequences
- The mounted NeuroStudio workspace contains one `MaterialApp` and inherits global preferences.
- Backend connection management has one user-facing owner.
- NeuroStudio remains independently testable as a Flutter package through a lightweight test host.
- Changes to the NeuroCNL submodule revision must run both feature and root-app integration tests.
- The NeuroCNL Flutter package can no longer be launched as a standalone application.
