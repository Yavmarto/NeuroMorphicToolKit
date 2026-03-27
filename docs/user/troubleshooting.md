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

---

## Still Having Issues?

1.  **Reset Module**: Uninstall the module from the Catalog and reinstall it.
2.  **Check Global Logs**: If running from source, check the terminal output for detailed traceback errors.
3.  **Submit an Issue**: If the problem persists, please collect the error message from the "Health Status" and open an issue on the repository.
