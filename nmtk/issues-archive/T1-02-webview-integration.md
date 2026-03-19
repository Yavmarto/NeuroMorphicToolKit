# Add WebView or Embedded UI for Launched Modules

**Priority:** Critical — POC Blocker  
**Type:** Feature  
**Tier:** 1 (Must Do)  
**Estimated Effort:** 2–3 days  

## Description

When a user clicks "Launch" on an installed module, the launcher currently opens a mock `ToolViewScreen` with fake terminal output. It must instead display the module's actual UI — either via a WebView pointing to the module's frontend, or by embedding the module's Flutter frontend directly.

## Requirements

1. **WebView Integration:**
   - Add `webview_flutter` (or `webview_windows` / `desktop_webview_window` for macOS/Windows desktop) dependency
   - When a module backend is confirmed running (via `/health` poll), open a WebView panel pointing to `http://localhost:<port>`
   - For modules with Flutter frontends that are built to web, serve the static build and display it
   - For modules without a frontend (e.g., Neuro-Dream-Hand), show the FastAPI Swagger docs at `http://localhost:<port>/docs`

2. **Fallback:**
   - If WebView is unavailable on the platform, open the URL in the system browser via `url_launcher`

3. **Tab Management:**
   - Support multiple modules open simultaneously as tabs within the launcher
   - Each tab shows the module name and a close button
   - Closing a tab does not stop the backend process

## Acceptance Criteria

- Launching neurocnl opens its frontend UI within the launcher window
- Launching Neurosim opens its Swagger docs (or minimal frontend) in a WebView
- Multiple modules can be open as tabs simultaneously
- The back button returns to the dashboard

## Dependencies

- Requires `T1-01-process-manager` to be implemented first (module must be running)

## Files Affected

```
nmtk/neuro_toolkit/pubspec.yaml                             ← add webview dependency
nmtk/neuro_toolkit/lib/screens/tool_view.dart                ← replace mock with WebView
nmtk/neuro_toolkit/lib/widgets/module_tab_bar.dart           ← new
nmtk/neuro_toolkit/lib/routing/router.dart                   ← add WebView routes
```
