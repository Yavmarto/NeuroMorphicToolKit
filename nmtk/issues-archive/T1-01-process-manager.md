# Replace Mock Install with Real Process Manager

**Priority:** Critical — POC Blocker  
**Type:** Feature  
**Tier:** 1 (Must Do)  
**Estimated Effort:** 3–5 days  

## Description

The neuro_toolkit launcher currently simulates module installation with a timer (`Future.delayed`). It cannot start, stop, or monitor any real Python backend process. This is the **single biggest POC blocker** — the launcher IS the POC.

## Requirements

1. **Python Backend Lifecycle:**
   - Create a `ProcessManager` service that uses `dart:io Process.start()` to:
     - Create a Python venv for each module (if not already created)
     - Install the module's Python dependencies (`pip install -e .`)
     - Start the FastAPI backend on the module's assigned port (`uvicorn app.main:app --port <port>`)
     - Monitor the process health (stdout/stderr streaming, exit code detection)
     - Stop the process gracefully (SIGTERM, then SIGKILL after timeout)
   - Store installation/running state persistently (e.g., JSON file in app data directory)

2. **Port Assignments:**
   | Module | Port |
   |--------|------|
   | neurocnl | 8000 |
   | Neurosim | 8001 |
   | Neurochip | 8002 |
   | Neurobench | 8003 |
   | Neurosense | 8004 |
   | Neurohub | 8005 |

3. **Health Monitoring:**
   - Poll each module's `/health` endpoint to determine running/degraded/stopped status
   - Update `ModuleProvider` state accordingly
   - Show status indicator on DashboardScreen

## Acceptance Criteria

- Clicking "Install" on a catalog module creates a real venv and installs dependencies
- Clicking "Launch" starts the backend process and reports when it's ready
- Clicking "Stop" terminates the process
- Process crashes are detected and reported in the UI
- Module state persists across app restarts

## Files Affected

```
nmtk/neuro_toolkit/lib/services/process_manager.dart        ← new
nmtk/neuro_toolkit/lib/providers/module_provider.dart        ← refactor
nmtk/neuro_toolkit/lib/models/module.dart                    ← add status fields
nmtk/neuro_toolkit/lib/screens/dashboard.dart                ← wire real status
nmtk/neuro_toolkit/lib/screens/catalog.dart                  ← wire real install
```
