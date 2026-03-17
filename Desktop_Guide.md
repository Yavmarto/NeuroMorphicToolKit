# NMTK Desktop Running Guide

This guide details how to run the multi-app NeuroMorphic ToolKit suite locally on a desktop environment. 

## Architecture Overview
The suite consists of several independent Flutter desktop applications that communicate with standalone Python FastAPI backends. `neurocnl` acts as the foundational core library, and `NeuroHub` acts as the cross-suite orchestrator.

## 1. Prerequisites
*   **Python 3.10+**: Ensure `pip` and `venv` are available.
*   **Flutter SDK**: Installed and on your PATH. Compatible with macOS desktop application development.
*   **Dependencies**: 
    ```bash
    flutter doctor # Ensure desktop development is enabled for macOS
    ```

## 2. Bootstrapping the Backends

Each tool currently has its own FastAPI backend architecture. It is recommended to use independent virtual environments or a unified Conda/Poetry setup across the suite.

### A. Installing Core Libraries
Ensure `neurocnl` and `Neuro-Dream-Hand` are installed so other modules can access them:
```bash
cd neurocnl
pip install -e .

cd ../Neuro-Dream-Hand
pip install -e .
```

### B. Starting Individual Backends
Depending on which tool you are working on, start its respective backend server. 

**NeuroSim Backend:**
```bash
cd Neurosim/neurosim
uvicorn app.main:app --reload --port 8001
```

**NeuroBench Backend:**
```bash
cd Neurobench/neurobench
uvicorn app.main:app --reload --port 8002
```

**NeuroSense Backend:**
```bash
cd Neurosense/neurosense
uvicorn app.main:app --reload --port 8003
```

**NeuroChip Backend:**
```bash
cd Neurochip/neurochip
uvicorn app.main:app --reload --port 8004
```

**NeuroHub Backend (Orchestrator):**
```bash
cd Neurohub/neurohub
uvicorn app.main:app --reload --port 8000
```

*Note: In the future 'pipeline collapse' phases (as per `Merge_maintain.md`), some of these setup procedures and services may merge into a unified suite runner or installer.*

## 3. Running the Flutter Desktop Frontends

Open a new terminal for the frontend you wish to run. Ensure you have run `flutter pub get` in the respective `frontend/` directories.

**To run a specific app (e.g., NeuroHub) on macOS Desktop:**
```bash
cd Neurohub/frontend
flutter pub get
flutter run -d macos
```

*If API URLs need to be explicitly defined for the Flutter app client, pass them via dart-define:*
```bash
flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## 4. Useful Maintenance Commands

*   **Linting & Typing:** The suite adheres strictly to `ruff` and `mypy`.
    ```bash
    ruff check .
    mypy .
    ```
*   **Testing:** Run Python tests via pytest.
    ```bash
    pytest
    ```
