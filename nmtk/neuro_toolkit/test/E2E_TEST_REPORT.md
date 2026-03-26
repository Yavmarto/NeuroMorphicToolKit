# E2E Launcher Test Report (2026-03-26)

## Overview
The E2E Launcher test was executed on a Linux environment (Ubuntu 24.04). The test verified the full process of installing a module, creating a virtual environment, installing dependencies, and launching the backend server via Uvicorn.

## Results
- **Install neurocnl**: SUCCESS
- **Verify venv creation**: SUCCESS
- **Verify pip install -e .**: SUCCESS (Also verified local dependency `Neuro-Dream-Hand` installation)
- **Verify uvicorn subprocess starts**: SUCCESS
- **Verify health polling detects it**: SUCCESS
- **Verify multi-module support**: SUCCESS (Tested `neurocnl` and `Neurosim` simultaneously)
- **Verify tab management (UI)**: SUCCESS (Verified via `ui_integration_test.dart`)
- **Verify fallback to system browser**: SUCCESS (Verified via UI presence in `ui_integration_test.dart`)

## Platform-Specific Observations

### Linux
- **WebView Support**: The current implementation of `ToolViewScreen` in `neuro_toolkit` explicitly excludes Linux from WebView support:
  ```dart
  bool _isWebViewSupported() {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }
  ```
  On Linux, the UI correctly falls back to a message and an "Open in System Browser" button.
- **Fontconfig Errors**: During Uvicorn startup, several "Fontconfig error: No writable cache directories" messages were observed in stderr. These are likely related to the sandbox environment and did not prevent the backend from starting or serving requests.
- **Venv Portability**: Found and fixed an issue where pre-existing virtual environments might have hardcoded absolute paths in their shebangs that point to non-existent directories (likely from a different build environment). The `ProcessManager` correctly handles venv creation when no venv exists.

### Performance
- **Installation Time**: Real `pip install` operations take significant time (approx. 20-40 seconds per module). E2E tests should use a timeout of at least 3-5 minutes.
- **Health Polling**: Uvicorn typically takes 2-5 seconds to become ready after the process starts. The 2-second initial delay in `ProcessManager` and 5-second polling interval are appropriate.

## Recommendations
1. Consider adding `Platform.isLinux` to `_isWebViewSupported()` once `webview_flutter_linux` or a similar package is integrated and verified.
2. Ensure the installer/setup script clears any existing `venv` directories if the installation path changes to avoid shebang issues.
