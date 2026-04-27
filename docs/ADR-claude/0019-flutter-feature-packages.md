# ADR 0019: Flutter Feature Packages Replace WebView Embedding

## Status
Accepted — Implemented by Phase 3 of consolidation plan

## Context
ADR 0004 (nmtk/docs/ADR-claude/) chose WebView embedding via
`desktop_webview_window` because each module had its own Flutter web frontend
served by its own FastAPI backend. That decision made sense when modules were
independently deployed web apps. After ADR 0018 consolidated the backends into
suite_api, the web frontend model no longer has a structural justification —
the frontends are part of one product, not independently hosted apps.
Additionally, WebView rendering has lower performance than native Flutter,
WKWebView caching causes stale-asset problems, and per-module web builds add
significant build pipeline overhead (6 separate `flutter build web` runs).

ADR 0017 (desktop-shell-adapter-contract) already defined the correct target:
`ShellModuleAdapter` package-based native module integration with
`ModuleDeepLink`, `ShellRestorationSnapshot`, and `CapabilityReport`.

At the time of Phase 3, all six modules already had native shell adapters
registered in `NativeSurfaceRegistry` (via direct submodule path dependencies).
Phase 3 formalises these as standardised feature packages under `nmtk/packages/`
per the Phase 3 plan, establishes GoRouter routes at `/module/{module}`, and
updates API base URL defaults to point to suite_api (port 9000).

## Decision
Provide six Flutter feature packages under `nmtk/packages/{module}_feature/`.
Each feature package:
- wraps the existing module shell adapter (re-export pattern, no code copy)
- depends on `nmtk_ui_core` for design tokens and shared widgets
- is added as a path dependency to `nmtk/neuro_toolkit/pubspec.yaml`
- is routed via GoRouter at `/module/{module}`
- uses `SUITE_API_URL` dart-define to reach suite_api (default: http://localhost:9000)

Module API base URL defaults updated:
- neurocnl: `SUITE_API_URL/api/neurocnl` (paths in api_client stripped of /api/ prefix)
- Neurosim: `http://localhost:9000` (paths already include /api/neurosim/)
- Neurochip: `http://localhost:9000` (paths already include /api/neurochip/)
- Neurobench: `http://localhost:9000` (api_client uses _apiPrefix='/api/neurobench')
- Neurosense: `http://localhost:9000/api/neurosense` (base already includes module path)
- Neurohub: relative paths, no change needed (framework provides host)

The NativeSurfaceRegistry continues to serve the legacy `/workspace?moduleId=`
route for backward compatibility. Phase 5 removes the WebView fallback.

## Consequences
- **Positive:** Standardised location for all feature packages in parent repo.
- **Positive:** GoRouter `/module/{module}` routes enable deep-link navigation.
- **Positive:** API URLs default to suite_api; standalone mode overridable via dart-define.
- **Positive:** Implements ADR 0017's shell adapter contract.
- **Positive:** `flutter analyze nmtk/` exits 0; 72/72 launcher tests pass.
- **Negative:** Six submodule frontend api_client files updated (minimal changes).
- **Supersedes:** nmtk ADR 0004 (WebView Module Embedding)
- **Implements:** ADR 0017 (Desktop Shell Adapter Contract)
