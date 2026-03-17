# NeuroMorphic ToolKit (NMTK) Status

## 1. Executive Summary
The NeuroMorphic ToolKit is transitioning from a set of isolated scripts/repositories into a unified, integrated suite. The current architecture places `neurocnl` as the core backend dependency, with various Flutter-based tools (NeuroHub, NeuroSim, NeuroBench, NeuroSense, NeuroChip) augmenting the development lifecycle from design to physical hardware deployment. 

## 2. Current Progress by Module

*   **neurocnl**: Core library stable (v0.3.0). Supports learning rules, multi-population networks, spike encoding, and export formats. Acts as the foundational library for other tools.
*   **NeuroSim**: Backend API endpoints and simulation runner logic are **100% complete**. Next focus is building the Flutter frontend UI workflows.
*   **NeuroBench**: Backend API foundations, data layer, and business logic are **complete**. Next milestone is implementing the CLI interface, followed by frontend integration.
*   **NeuroChip**: Phase 1 Scaffolding complete. Next steps are Phase 2 (Hardware Profiles & Firmware Templates) and Phase 3 (Backend Business Logic).
*   **NeuroSense**: Scaffolding and initial device management complete. Pending steps include impedance checks and the live signal viewer logic.
*   **NeuroHub**: Backend scaffolding complete. Pending steps include `assets`, `workflows`, and `health` logic, plus the `suite_client.py` to enable cross-app communication. Frontend UI data models and providers need implementation.
*   **Neuro-Dream-Hand**: Endpoints are being integrated as routers within the `neurocnl` backend (`/api/prosthetic/*`) to avoid running separate microservices.
*   **Maintenance & Architecture (`nmtk`)**: Comprehensive plans are documented for security scanning, type safety (`mypy`), linting (`ruff`), and distribution (Phase 1-5 in `Merge_maintain.md`).

## 3. What's Needed for Proof of Concept (POC)

To achieve a viable MVP/POC of the integrated suite, the following must be completed:
1.  **Backend Integration (Phase 2)**: Complete the integration of `Neuro-Dream-Hand` endpoints into the common backend.
2.  **Suite Orchestration**: Implement `suite_client.py` in NeuroHub to establish the cross-app activity feed and health monitoring.
3.  **Frontend Baselines (Phase 3)**: Establish basic, working UIs for the tools, prioritizing:
    *   **NeuroSim**: Ability to visually place populations and hit `/api/neurosim/preview`.
    *   **NeuroHub**: Displaying the central dashboard and suite health.
    *   **NeuroSense**: Basic live signal viewer connecting to a mock/real device.
4.  **Hardware Proof**: Populate at least one working Hardware Profile and Firmware Template in NeuroChip (e.g., Teensy) so that a generated CNL spec can be deployed to physical hardware. 

## 4. Focus Areas for Subsequent Sessions
*   **Frontend UI Development**: The backends for NeuroSim and NeuroBench are largely done; heavy lifting is now required on the Dart/Flutter frontends (Riverpod providers, Canvas drawing, UI implementation).
*   **NeuroHub Core Logistics**: Build the inter-app HTTP communication layer so NeuroHub can accurately reflect operations in NeuroSim, NeuroChip, etc.
*   **Continuous Integration & Automation**: Implement the `maintenance-improvement.md` plan, setting up GitHub Actions for tests, `ruff` checks, and eventually the Desktop installers (Phase 5 of maintenance merge).
