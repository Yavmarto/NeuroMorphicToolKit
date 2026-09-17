# ADR 0004: WebView Module Embedding

## Status
Superseded by ADR 0019 (Flutter Feature Packages)

## Supersession note
WebView embedding via desktop_webview_window is replaced by native Flutter
feature packages after Phase 3 of the consolidation plan. See
docs/ADR-claude/0019-flutter-feature-packages.md and
docs/implementation-plan-consolidation.md.

## Context
Each NMTK module has its own Flutter web frontend served by its respective FastAPI backend. The desktop launcher needs to display these web UIs within the native application without rebuilding them as native widgets.

## Decision
Use `desktop_webview_window` to embed module web frontends in a native webview. The `ToolViewScreen` receives a `moduleId`, resolves the module's localhost URL from the manifest (e.g., `http://localhost:8001`), and loads it in an embedded webview. A fallback message is shown when the frontend build is not available.

## Consequences
- **Positive:** Webview embedding reuses existing web frontends without any porting effort; modules can be developed and tested independently as web apps.
- **Negative:** Webview rendering performance is lower than native Flutter; WKWebView caches (macOS) can serve stale assets after frontend rebuilds, requiring manual cache clearing.

## Status Update (2026-07-16 audit)

**Path reference fix:** The supersession note above cites `docs/ADR-claude/0019-flutter-feature-packages.md` and `docs/implementation-plan-consolidation.md` as if both live under this module's own `nmtk/docs/`. Verified via `ls`: neither exists there. The correct locations are the top-level `/NeuroMorphicToolKit/docs/ADR-claude/0019-flutter-feature-packages.md` and `/NeuroMorphicToolKit/docs/archive/implementation-plan-consolidation.md`.

**Migration completeness:** The native-Flutter migration this ADR's supersession note implies is complete is actually partial. `nmtk/neuro_toolkit/pubspec.yaml` still declares `desktop_webview_window: ^0.2.3` (confirmed by reading the file), and `nmtk/neuro_toolkit/lib/workspace/native_surface_registry.dart` registers native surfaces for only 4 of the 6 modules ADR 0019 describes — `neurocnl`, `Neurohub`, `Neurochip`, and `Neurobench` (confirmed by reading that file's `_builders` map). `Neurosense` and `Neurosim` have no entry there and still fall back to WebView embedding under this ADR's original decision.
