# Troubleshooting: Module Won't Start

If a module in the NeuroMorphic ToolKit (NMTK) fails to start or shows an "Error" status, follow this guide to identify and resolve common issues.

---

## Common Scenarios

### 1. "Python Not Found" or Setup Screen Appears
The launcher cannot find a valid Python 3.10+ interpreter on your system.

*   **Solution**:
    *   Click the **"Install with Homebrew"** button (macOS) or follow the manual installation link.
    *   Verify Python is in your PATH by running `python3 --version` in a terminal.
    *   Restart the NMTK app after installing Python.

### 2. Module Fails to Install
The installation process (creating a virtual environment or running `pip install`) failed.

*   **Check the Logs**: Look at the terminal output if running from source, or check the module's "Health Status" in the Dashboard.
*   **Common Causes**:
    *   **No Internet**: Required to download Python packages.
    *   **Permission Denied**: Ensure you have write access to the application support directory.
    *   **Missing System Dependencies**: Some modules (like those requiring MuJoCo) may need additional system libraries.
*   **Solution**: Try clicking the "Uninstall" (trash icon) and then "Install" again to retry the process.

### 3. Module Fails to Start (Port Conflict)
The backend service cannot bind to its assigned port because another application is using it.

*   **Symptoms**: Module status flips from "Starting" to "Error" almost immediately.
*   **Solution**:
    *   The launcher attempts to kill processes on the required port automatically.
    *   If it fails, identify the process manually:
        *   **macOS/Linux**: `lsof -i :<port>` (e.g., `lsof -i :8000`)
        *   **Windows**: `netstat -ano | findstr :<port>`
    *   Kill the conflicting process and try starting the module again.

### 4. WebView Shows "Connection Refused"
The backend process is running, but the frontend cannot connect to it.

*   **Solution**:
    *   Wait a few seconds; some backends take longer to initialize.
    *   Check if the backend crashed shortly after starting (Status will change to "Error").
    *   Ensure your firewall is not blocking local connections on ports 8000-8006.

### 5. Akida SDK Verification Is Blocked
The Akida deploy flow can generate a scaffold package, but Neurochip reports that SDK verification is unavailable.

*   **Common Causes**:
    *   **Unsupported host OS**: BrainChip's Akida SDK is supported on Linux and Windows, not macOS.
    *   **Unsupported Python version**: the Akida stack expects Python `3.10` to `3.12`.
    *   **Missing MetaTF packages**: local Akida verification also needs `tensorflow==2.19.*`, `akida==2.19.1`, `cnn2snn==2.19.1`, and `akida-models==1.13.1`.
    *   **Windows prerequisite missing**: the Visual C++ redistributable is not installed.
*   **Solution**:
    *   On supported Linux or Windows hosts, use **Prepare Akida Runtime** from the Akida deploy flow to install the full BrainChip package set into the Neurochip environment.
    *   On macOS, continue using scaffold export and local simulator fallback, but point SDK verification at a Neurochip instance running on Linux or Windows.
    *   Use the [Akida remote host runbook](./akida_remote_host.md) if you need to pair NMTK with a separate Linux or Windows Akida host.

### 6. Akida Remote Host Pairing Does Not Reach Neurochip
The launcher can read the remote control API, but the Akida deploy screen still behaves as if Neurochip is local-only.

*   **Check the control API host**: `NMTK_CONTROL_API_BASE_URL` should point at the remote launcher control service, usually `http://<host>:8090`.
*   **Check the Neurochip host**: if the Akida backend is not reachable on `http://<host>:8002`, also set `NMTK_NEUROCHIP_BASE_URL` explicitly.
*   **Check the remote services**:
    *   `python3 scripts/launcher_control_service.py --host 0.0.0.0 --port 8090`
    *   `poetry run uvicorn neurochip.app.main:app --host 0.0.0.0 --port 8002`
*   **Next step**: use the [Akida remote host runbook](./akida_remote_host.md) to verify the expected port wiring and startup commands.

---

## Still Having Issues?

1.  **Reset Module**: Uninstall the module from the Catalog and reinstall it.
2.  **Check Global Logs**: If running from source, check the terminal output for detailed traceback errors.
3.  **Submit an Issue**: If the problem persists, please collect the error message from the "Health Status" and open an issue on the repository.
