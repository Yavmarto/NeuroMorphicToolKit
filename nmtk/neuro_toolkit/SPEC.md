# NeuroToolkit App Specification

> **Product intent (read this first):** The frontend is **one integrated surface — NeuroStudio**.
> There is **no module marketplace, no module picker, and no per-module tab bar** in the
> launcher. Users connect to a server, and everything they see lives inside the single mounted
> NeuroStudio surface. This has regressed multiple times (see CEL-100): do not reintroduce
> module-selection UI from any "marketplace" or "catalog" idea.

## Overview
NeuroToolkit (`nmtk/neuro_toolkit`) is the single shipped Flutter app for the
NeuroMorphicToolKit suite. It is a deliberately thin launcher: it connects to a backend server,
tracks module health from the `launcher-control` manifest, and mounts exactly **one** module
surface full-window. In practice that surface is **NeuroStudio**, which owns all navigation,
chrome, workspace switching, and the pipeline UX. The launcher renders no navigation of its own.

## Goals
- **Single surface:** One app, one workspace. After connecting to a server, the user works
  entirely inside NeuroStudio — no picking, browsing, or installing of modules.
- **Ease of Use:** Auto-detect the backend and mount the workspace with minimal setup steps.
- **Integration:** All suite capabilities (simulation, CNL compilation, deployment, datasets)
  are features inside NeuroStudio, not separate tools the user must discover or install.

## Architecture
1. **Frontend (Flutter launcher):**
   - **Tool View:** Hosts exactly one mounted module surface, full-window, with no outer nav
     chrome (see ADR-0009 `docs/ADR-claude/0009-single-workspace-launcher-navigation.md`).
   - **Server connect / Backend Setup:** The only pre-workspace flow — connect to a server,
     verify backend health, then enter NeuroStudio.
   - **Embedded WebViews:** Only for surfaces that are genuinely web-backed (e.g., Jupyter);
     these are rendered inside the single workspace, not as a module catalog.
2. **Backend / Local Integration:**
   - **launcher-control:** Serves the module manifest (`assets/modules.json` bundled, remote
     manifest takes precedence) and module lifecycle/health. The manifest describes deployed
     suite services — it is not a user-facing "install" catalog.
   - **Process Execution:** The launcher starts/monitors local services and streams status;
     it does not present install/update buttons to the user.

## Suite Modules (backend services, not user-facing picks)
1. **Neuro-Dream-Hand:** Neuromorphic simulation framework for prosthetic hand control.
2. **neurocnl:** Controlled Natural Language specifications compiler (hosts NeuroStudio).
3. **nmtk:** Neuromorphic Toolkit hub for various utilities.

## Historical / Deprecated (do NOT implement)
The following describe an obsolete early vision and are kept only as history. They contradict
the current product intent and the root README:
- ~~"Module Marketplace": a catalog view to browse, install, and update tools.~~ Deprecated.
- ~~"Dashboard: overview of installed tools."~~ Deprecated.
- ~~Module picker panel / module tab bar (`ModulePickerPanel`, `ModuleTabBar`).~~ Removed in
  CEL-101/CEL-103 (commits `ba3704fe`, landed 2026-09-08). Do not reintroduce.
