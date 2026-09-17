# Implementation Plan for NeuroChip

Based on the `neurochip_spec.md`, the implementation is broken down into the following distinct phases. The project structure and initial backend setup have been completed in Phase 1.

## Phase 1: Project Scaffolding and Boilerplate (Completed)
- **Directory Structure:** Created the full nested folder structure for both the Flutter frontend (`frontend/lib/screens`, `frontend/lib/widgets`, etc.) and the FastAPI backend (`neurochip/app/routers`, `neurochip/app/schemas`, `neurochip/app/services`, etc.).
- **Backend Schema Implementation:** Implemented the exact Pydantic data models defined in the specification:
  - `HardwareProfile`
  - `ConstraintReport`
  - `QuantizationResult`
  - `FaultSweepResult`
  - `DeploymentRecord`
- **Backend Router Implementation:** Scaffolded all required FastAPI routes (`/api/neurochip/targets`, `/api/neurochip/analyze`, etc.) with mock responses and included them in the main FastAPI app.
- **Frontend Scaffolding:** Created the empty dart files for all specified screens and widgets. Set up `pubspec.yaml` and `app.dart`.
- **Infrastructure:** Set up `pyproject.toml`, `Dockerfile`, and `docker-compose.yml` to run the backend in a containerized environment. Added a basic `.gitignore` for Python and Dart artifacts.

## Phase 2: Hardware Profiles & Firmware Templates
- **Hardware Targets:** Populate the empty JSON files in `neurochip/targets/` (e.g., `teensy41.json`, `loihi2.json`) with the actual hardware constraints, memory limits, and capabilities according to the schema.
- **Jinja Templates:** Write the Jinja2 templates for the C/C++ firmware generation (`main.ino.j2`, `lif_engine.h.j2`, etc.) and Loihi deployment scripts (`deploy.py.j2`).

## Phase 3: Backend Business Logic Implementation (In Progress)
- **Constraint Analyzer:** Implemented `constraint_analyzer.py` to compare an input network against a `HardwareProfile` and generate a detailed `ConstraintReport`. Refactored to pass strict static typing guidelines (`mypy`).
- **Quantization & Power:** Integrated the `neurodreamhand` mock capabilities into `quantizer.py` and `power_estimator.py` to run realistic bit-width sweeps and energy estimations. Applied strong type hints.
- **Fault Injection:** Implemented `fault_runner.py` to sweep fault rates and calculate the robustness curve (`FaultSweepResult`). Refactored to pass strict typing rules.
- **Code Generation & Flashing:** Implemented `teensy_generator.py` to render the Jinja templates. Implemented `flash_service.py` to invoke PlatformIO as a subprocess to compile and upload firmware via the serial port. Refactored all logic for `mypy --strict` compliance.
- **Data Persistence:** Implemented basic mock storage in `deployment_store.py`/`deployments.py` routers for logging deployment records. Addressed generic type omissions to adhere to AI coding standards.

## Phase 4: Frontend Implementation (Flutter) (In Progress)
- **Coding Style Guidelines Fix:** Refactored `pubspec.yaml` to fix the non-existent relative path to `nmtk_ui_core` and disabled `publish_to` to remove static analysis warnings.
- **UI Architecture:** Implemented `api_client.dart` with strong typing to interface with the FastAPI backend. Created `HardwareProfile` data model. Wired up Riverpod providers (`apiClientProvider`, `targetsFutureProvider`, `selectedTargetProvider`).
- **Target Selection:** Built the `TargetSelector` ConsumerWidget dropdown/gallery to load and select target hardware profiles from the API.
- **App Initialization:** Populated `app.dart` to bootstrap the Flutter app with Riverpod `ProviderScope`.
- **Interactive Explorers:** Build the `QuantizationExplorer` with live charting and the `ConstraintReportCard` for immediate feedback.
- **Deployment Flow:** Implement the `FirmwareGeneratorPanel` and `FlashProgressIndicator` to provide a seamless one-click deployment experience.

## Phase 5: Testing and Integration
- **Unit Tests:** Write comprehensive Pytest suites for all backend services (e.g., ensuring the constraint analyzer correctly flags memory overflows).
- **Integration Tests:** Test the end-to-end flow from receiving a CNL spec to generating compilable C code.
- **Frontend Tests:** Write Flutter widget tests for the interactive UI components.
