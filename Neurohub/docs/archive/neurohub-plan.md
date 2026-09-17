# NeuroHub Development Plan & Status

This document tracks the status of the NeuroHub codebase against the specifications (`neurohub_spec.md`) and the coding style guide (`CODING_STYLE_GUIDE.md`).

## 1. Compliance with Coding Style Guide

### Python Backend (`neurohub/`)
- **Type Hints:** The codebase is using Pydantic models with explicit type hints (`app/schemas/projects.py`), and FastAPI routes are typed (`app/routers/projects.py`).
- **File Structure:** Adhering to small, focused files (e.g., `app/routers`, `app/schemas`, `app/services`, `db`).
- **Standardized Docstrings:** Code currently lacks extensive docstrings. **Next Step:** We need to add Google-style docstrings to all functions, classes, and methods, especially for `services` and `routers`.
- **Database Rules:** SQLAlchemy models and Pydantic schemas correctly use aliases for fields like `metadata` when required.
- **Agent Rules enforced:** Added `.cursorrules` to instruct agents to follow global coding standards.

### Flutter Frontend (`frontend/`)
- **Widget Architecture:** The project structure is appropriately separated into `screens` and `widgets`.
- **Typing:** `dynamic` types must be avoided, and strong typing strictly enforced. Current basic files look compliant with standard Flutter style.
- **State Management:** Currently missing providers structure implementation. **Next Step:** Implement Riverpod providers as outlined in `neurohub_spec.md`.
- **Agent Rules enforced:** Added `.cursorrules` to instruct agents to follow global coding standards.

## 2. Current Status (vs `neurohub_spec.md`)

### Implemented
- **Backend API Structure:** FastAPI application initialized (`neurohub/app/main.py`).
- **Database:** SQLite initialized with SQLAlchemy.
- **Routers:** Endpoints exist for dashboard, projects, milestones, assets, workflows, activity, health, config, members, and notes.
- **Projects Endpoint:** Full CRUD functionality implemented for Projects (`neurohub/app/routers/projects.py` and schemas).
- **Tests:** A testing suite exists and 27 endpoints/projects tests currently pass.
- **Frontend Scaffolding:** Basic directory layout (`lib/screens`, `lib/widgets`, `lib/providers`, `lib/models`, `lib/services`) and an initial `DashboardScreen`.

### Missing / Next Steps

1. **Backend Implementations:**
   - Implement the remaining service logic for `assets.py`, `workflows.py`, `milestones.py`, etc., connecting routers to database models.
   - Implement the `activity_collector.py` polling system across different apps.
   - Implement the workflow execution logic in `workflow_engine.py`.
   - Implement suite health check logic in `health_checker.py`.
   - Add Google Style Docstrings to all current modules.

2. **Frontend Implementations:**
   - Define Data Models in Dart (`lib/models/`).
   - Implement API client to communicate with FastAPI (`lib/services/api_client.dart`).
   - Set up Riverpod Providers (`lib/providers/`).
   - Build out the UI screens (Dashboard, Project Detail, New Project, Workflow Editor, etc.) utilizing `nmtk_ui_core`.

3. **Cross-App Integrations:**
   - Mock or implement the suite apps HTTP clients in `suite_client.py`.

## 3. Next Immediate Actions

- Add missing Google-style docstrings to the existing Python codebase to comply perfectly with `CODING_STYLE_GUIDE.md`.
- Flesh out the backend services for `assets`, `workflows`, and `health`.
- Begin implementing the Data Models and API client in the Flutter frontend.
