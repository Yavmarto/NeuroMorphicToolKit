# NMTK: Neurotraining Integration Handoff Document

This document provides a comprehensive technical overview of the **Neurotraining** architecture within the **NeuroMorphicToolKit (NMTK)** monorepo. It details what is already implemented, maps out the codebase integration, and provides a playbook for running, verifying, and extending the training pipelines.

---

## 🚀 1. The Good News: Completion Status

You do not need to implement the core neurotraining pipeline from scratch! The entire architecture—from the domain registry up to the Flutter desktop UI widgets—is **already fully implemented, integrated, and covered by automated tests**. 

The system leverages a capability-driven adapter pattern that permits seamless background execution, status polling, and modular expansion.

---

## 🗺️ 2. Architectural Codebase Map

The pipeline is organized across standard structural layers (Domain logic, Backend REST API, and Frontend Dart UI):

### 🧬 A. Core Domain Library (`neurocnl/neurocnl/`)
* **[training_registry.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/training_registry.py):** The generic orchestrator contract. Declares the data transfer objects (`TrainingRequest`, `TrainingResult`, `AdapterCapability`) and the `BaseTrainingAdapter` interface. It provides capability-checking and validation for any new learning framework.
* **[training/sleep_pes_adapter.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/training/sleep_pes_adapter.py):** The first concrete adapter. Bridges `neurodreamhand`'s sensory-motor sleep optimizer, featuring a deterministic, safe mock fallback when local development libraries are absent.
* **[training/snntorch_adapter.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/training/snntorch_adapter.py):** A deep-learning surrogate gradient adapter using `snnTorch`. Fuzzes training gradients on top of a synthetic `n-mnist` dataset fixture.
* **[training/factory.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/training/factory.py):** Singleton builder wire-up that registers both training adapters.

### 🌐 B. Backend REST Layer (`neurocnl/backend/`)
* **[routers/training.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/routers/training.py):** Exposes JSON endpoints:
  * `GET /api/training/capabilities` - List available models and check system dependency availability.
  * `POST /api/training/run` - Start a training run in the background (returns a queued `job_id`).
  * `GET /api/training/jobs/{job_id}` - Poll for training metrics, loss curves, and resulting weights.
* **[services/training_service.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/services/training_service.py):** Mediates between the REST API and the domain registry, submitting execution functions to the thread-pool based `job_store`.

### 🖥️ C. Frontend Dart Layer (`neurocnl/frontend/`)
* **[providers/training_provider.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/providers/training_provider.dart):** Riverpod providers managing submission state, error handling, capability detection, and interval polling (`Timer.periodic` triggers) to fetch live loss curves.
* **[widgets/training_inspector_panel.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/training_inspector_panel.dart):** A responsive UI card that renders dropdowns for target backends, handles epoch configuration sliders, runs active timers, and prints loss charts.
* **[screens/studio_screen.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart):** Fully integrated training hookup! The toolbar features an `Icons.model_training_outlined` (graduation cap) icon that launches the `TrainingInspectorPanel` in the editor workspace.

---

## 🧪 3. Playbook: Verification & Running

### A. Run Automated Backend Tests
Run the FastAPI route and worker tests to verify that capability extraction and job polling operate smoothly:
```bash
# From workspace root
cd neurocnl
PYTHONPATH=. pytest backend/tests/test_training_router.py -v
```

### B. Run Automated Frontend Widget & Provider Tests
Test the Riverpod state notifier and the widget configuration UI:
```bash
cd neurocnl/frontend
flutter test test/widgets/training_inspector_test.dart  # If specific widget test exists
flutter test                                           # Standard test suite run
```

### C. Manual Verification Steps
To see the training pipeline run live on your machine:
1. **Launch the Backend Service:** Start the local uvicorn development server.
2. **Launch the Flutter Application:** Start the desktop client (`flutter run -d macos` or equivalent).
3. **Write a CNL Network:** Open a new editor tab in NeuroStudio and type in a basic SNN spec.
4. **Open the Training Panel:** Click the **Graduation Cap Icon** on the right-hand action bar of the Studio Screen.
5. **Select a Backend:** Choose `sleep_pes` (or `snntorch`). If dependencies are missing, the UI will display a locked state explaining the exact command (e.g. `pip install neurodreamhand`) needed to unlock the physical runtime.
6. **Submit & Poll:** Set your target epochs, click **Start Training**, and watch the elapsed timer and loss summary update live.

---

## 📈 4. The "Next Steps" Extension Roadmap

Since the structural plumbing is complete, you can focus on building advanced enhancements to promote this into a production-grade system:

### 1. Integrate Realistic Dataset Ingestion
Currently, the `snntorch` adapter is hardcoded to a lightweight synthetic `n-mnist` fixture (`neurocnl/neurocnl/training/dataset_fixtures.py`). 
* **Extension:** Integrate physical file-system path loaders in the payload, allowing users to choose raw DVS (Dynamic Vision Sensor) event files or local folders in the UI.

### 2. Add New Framework Adapters
Implement additional learning engines (like Norse, SpikingJelly, NengoDL, or BrainScaleS-2 mixed-signal backends).
* **Extension:** Subclass `BaseTrainingAdapter` and register your new adapter in `neurocnl/neurocnl/training/factory.py`:
```python
# neurocnl/neurocnl/training/norse_adapter.py
class NorseAdapter(BaseTrainingAdapter):
    capability = AdapterCapability(
        backend_name="norse",
        supported_training_modes=("gradient",),
        default_training_mode="gradient",
    )
    # Implement is_available() and run()
```

### 3. Model Zoo Weight Handoff
Once training is successful, the resulting weights are returned as a matrix of numbers (`learned_weights` inside the `TrainingResult` payload).
* **Extension:** Implement an export button that maps these learned weights back into the `.nir` graph, enabling the user to immediately download the optimized network or deploy it to PYNQ/Teensy with fully trained parameters!
