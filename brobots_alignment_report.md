# Brobots Spec Alignment Report

**Date:** March 2026
**Subject:** Alignment of Brobots Neuromorphic Analysis Spec with NMTK Modules

## Overview
This report maps the toolsets proposed in the `Brobots Neuromorphic analysis spec` to the existing and newly created modules within the NeuroMorphicToolKit (NMTK). The Brobots analysis identifies critical gaps in the neuromorphic computing ecosystem—specifically a lack of standardization, robust benchmarking, onboarding tools, and a unified developer experience. The NMTK suite is well-positioned to fill these gaps. 

## Mapping Analysis

### 1. Benchmarking Tools
- **Benchmark Runner:** Aligns perfectly with `Neurobench`. A task was created in `Neurobench` to ensure it can load models in multiple formats (PyNN, Lava, Nengo, Brian2, NIR), as specified by Brobots.
- **Results Comparator:** Already largely covered by `Neurobench`'s Cross-Target Comparison and Regression Testing specs.
- **Hardware Profiler:** Best fits within the `Neurochip` deployment workflow (with data feeding into `Neurobench`). A task was added to `Neurochip` to build the physical on-chip metric capture functionality.

### 2. Standardization Tools
- **Model Converter:** `neurocnl` translates specs via CNL and Nengo. Expanding this to support NIR as a pivot format to cross-translate PyNN, Lava, and Brian2 is essential. A task was tracked in `neurocnl/issues`.
- **NIR Inspector:** The `NeuroSim` visual canvas is ideal for this. A task was created to allow natively importing/exporting and rendering NIR graph formats.
- **Hardware Target Mapper:** Already fully implemented by `Neurochip`'s "Automatic compatibility report".

### 3. Developer Tooling
- **Visual Network Editor:** Covered natively by `NeuroSim` (drag-and-drop SNN canvas).
- **Spike Train Visualizer:** Handled by `NeuroSim` (Simulation Preview panel) and `Neurosense` (Live signal viewer).
- **Parameter Sweep Tool:** Handled directly by `NeuroSim` (Sweep Grid) and `Neurobench` (Fault Sweeps).

### 4. Accessibility Tools
- **Project Scaffolder:** Brobots proposes a wizard and a CLI tool (`neuro new ...`). We have initiated a new module `neurocli` to house the terminal application. The visual wizard component will be integrated into the `Neurohub` project dashboard.
- **Software Simulator:** Covered efficiently by the Nengo backend within `neurocnl` and visualizes in `NeuroSim`.
- **Interactive Docs Browser:** An aggregator for framework documentation. We have created a new module `neurodocs` (with a corresponding issue) to act as the unified documentation browser and code playground.

## New Modules Created
Based on the gaps identified above, two new folders and corresponding architecture plans have been created:
- **`neurocli`**: Provides a command-line interface for the project scaffolder and general suite operations.
- **`neurodocs`**: Houses the unified, cross-framework interactive documentation browser.

Tasks have been safely distributed into the `issues/` directories of `Neurobench`, `Neurochip`, `Neurosim`, `neurocnl`, `Neurohub`, `neurocli`, and `neurodocs` for implementation tracking.
