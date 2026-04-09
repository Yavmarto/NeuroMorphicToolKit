# ADR 0004: WebView Module Embedding

## Status
Accepted

## Context
Each NMTK module has its own Flutter web frontend served by its respective FastAPI backend. The desktop launcher needs to display these web UIs within the native application without rebuilding them as native widgets.

## Decision
Use `desktop_webview_window` to embed module web frontends in a native webview. The `ToolViewScreen` receives a `moduleId`, resolves the module's localhost URL from the manifest (e.g., `http://localhost:8001`), and loads it in an embedded webview. A fallback message is shown when the frontend build is not available.

## Consequences
- **Positive:** Webview embedding reuses existing web frontends without any porting effort; modules can be developed and tested independently as web apps.
- **Negative:** Webview rendering performance is lower than native Flutter; WKWebView caches (macOS) can serve stale assets after frontend rebuilds, requiring manual cache clearing.
