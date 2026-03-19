# NeuroToolkit App Specification

## Overview
NeuroToolkit is a centralized, modular hub built in Flutter that allows users to easily manage, install, and run various neuromorphic engineering sub-modules. Instead of forcing users to download and configure a monolithic repository, the app provides a lightweight core where users can browse available tools (e.g., `Neuro-Dream-Hand`, `neurocnl`, `nmtk`) and selectively "install" what they need.

## Goals
- **Modularity:** Users download only the tools they require.
- **Ease of Use:** Provide a simple graphical interface to manage complex Python dependencies and CLI tools.
- **Discoverability:** Serve as a catalog for related neuromorphic projects.

## Architecture
1. **Frontend (Flutter):**
   - **Dashboard:** Overview of installed tools and system status.
   - **Module Marketplace:** A catalog view showing available tools with descriptions, statuses (Not Installed, Installed, Update Available), and an "Install" button.
   - **Tool Runners:** Dedicated GUI wrappers for each installed tool to execute commands (e.g., running a simulation in `Neuro-Dream-Hand` or compiling a spec in `neurocnl`).
2. **Backend/Local Integration:**
   - **Module Manager:** Handles cloning Git repositories or downloading packages.
   - **Environment Manager:** Provisions isolated Python environments (via `venv` or `conda`) for each tool to prevent dependency conflicts.
   - **Process Execution:** Uses Dart's `Process.run` to execute underlying Python scripts and stream stdout/stderr back to the Flutter UI.

## Modules Included
1. **Neuro-Dream-Hand:** Neuromorphic simulation framework for prosthetic hand control.
2. **neurocnl:** Controlled Natural Language specifications compiler for neuromorphic computing.
3. **nmtk:** Neuromorphic Toolkit hub for various utilities.

## Phase 1 Implementation (Current Scope)
- Build the Flutter UI shell (Navigation, Dashboard, Module Catalog).
- Implement state management for module statuses (Uninstalled, Installing, Installed).
- Provide a mock installation process (simulating a download and setup phase with progress indicators).
- Set up a generic "Tool View" for launched modules.
