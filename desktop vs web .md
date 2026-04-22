# Desktop vs Web Architecture

## Current Setup

The current NeuroMorphicToolKit architecture is a hybrid model:

- The main launcher runs as a Flutter desktop app.
- Each module usually exposes a local FastAPI backend.
- Module frontends are Flutter web apps served locally by their module backend.
- The desktop launcher embeds those module web apps through a desktop WebView.
- Some modules, such as `Neuro-Dream-Hand`, are CLI-only and do not expose a frontend.

This matches the accepted launcher direction in `nmtk/docs/ADR-claude/0004-webview-module-embedding.md`: the desktop launcher manages the suite, while modules keep their own independently developed web UIs.

## Short Recommendation

For this repository, the current hybrid model is the best default right now.

It gives the launcher native desktop access to local processes, Python environments, hardware workflows, logs, and installed modules, while letting each submodule keep a portable web UI. Moving everything to desktop would require a large rewrite of module UIs. Moving everything to web would make local process management, hardware access, offline use, and dependency isolation harder unless a separate local agent is introduced.

The better near-term path is to improve the hybrid model rather than replace it.

## Option 1: Current Hybrid Model

Main app: desktop.  
Submodules: local web apps embedded in the desktop app.

### Pros

- Keeps one native desktop control plane for install, launch, health checks, local paths, logs, and process lifecycle.
- Reuses existing module web frontends instead of rewriting them as native Flutter desktop screens.
- Allows modules to be developed, tested, and shipped independently.
- Keeps module boundaries clear: each module owns its backend, frontend, port, and runtime requirements.
- Works well for local scientific tooling where Python environments, hardware dependencies, and CLI tools matter.
- Preserves future flexibility because module web UIs can later be opened in a browser or hosted remotely.
- Reduces coupling between the launcher and product-specific module UI code.

### Cons

- WebView rendering is not as native as pure Flutter desktop.
- Desktop WebViews can have platform-specific behavior, especially around caching, focus, keyboard shortcuts, downloads, and file pickers.
- The launcher must manage local ports, backend readiness, failed starts, and stale frontend assets.
- Styling can drift if each module evolves its web UI independently.
- Debugging spans multiple layers: launcher, WebView, module frontend, module backend, and local runtime.

### Best Fit

This is the best fit when the app is a local suite manager for multiple independent tools, especially when those tools need Python backends, optional hardware, local files, and separate dependency environments.

## Option 2: Everything as Desktop Apps

Main app: desktop.  
Submodules: native desktop screens or separate desktop apps.

### Pros

- Most native-feeling user experience.
- Better access to operating system features such as local files, windows, menus, notifications, serial ports, and device APIs.
- Potentially better rendering performance for complex native Flutter views.
- Fewer WebView-specific issues.
- Easier to provide consistent global keyboard shortcuts and window behavior.

### Cons

- Requires porting every module frontend from web to desktop-native Flutter or another desktop framework.
- Makes independent module development harder because module UI code becomes more coupled to the launcher.
- Increases platform testing burden across macOS, Windows, and Linux.
- Makes browser-based or remote access harder.
- Can create a monolith if module UIs are folded into the launcher.
- Still needs local backend/process management for Python services, so it does not remove backend complexity.

### Best Fit

This is best if the product becomes one tightly integrated professional desktop application where native polish, hardware interaction, and offline workflows matter more than modularity or browser portability.

## Option 3: Everything as Web Apps

Main app: web.  
Submodules: web apps.

### Pros

- Simplest distribution for users if hosted centrally: open a URL and sign in.
- Easier cross-platform access from any modern browser.
- Easier remote collaboration and cloud deployment.
- Frontend development stack is unified around web delivery.
- Avoids desktop packaging, app signing, and native installer maintenance.

### Cons

- Browser apps cannot directly manage local Python environments, shell processes, hardware ports, firmware tools, or arbitrary local files without a local helper service.
- Offline use is weaker unless substantial local caching and service-worker support are added.
- Hardware workflows require WebUSB/WebSerial where available, or a separate native/local agent.
- User data, compute jobs, and module execution need a hosted backend or local bridge.
- Security, authentication, multi-user isolation, and deployment operations become larger concerns.
- Heavy simulations or hardware-dependent workflows may not map cleanly to browser-only execution.

### Best Fit

This is best if NeuroMorphicToolKit becomes primarily a cloud-hosted collaboration platform, a remote dashboard, or a classroom/browser-first product where local hardware and local Python dependency management are not central.

## Decision Matrix

| Criterion | Hybrid Desktop Shell + Web Modules | All Desktop | All Web |
| --- | --- | --- | --- |
| Current implementation fit | High | Low | Medium |
| Module independence | High | Medium to low | High |
| Local Python/runtime control | High | High | Low without local agent |
| Hardware workflow support | High | High | Low to medium |
| Browser/remote reuse | Medium to high | Low | High |
| Native desktop polish | Medium | High | Low |
| Packaging complexity | Medium | High | Low if hosted, medium if local |
| Testing complexity | Medium | High | Medium |
| Rewrite cost | Low | High | Medium |
| Best long-term flexibility | High | Medium | Medium to high |

## Practical Recommendation

Keep the hybrid architecture as the default product direction:

- Keep the launcher as the native desktop control plane.
- Keep module UIs as web frontends embedded in the launcher.
- Keep module backend ports, run paths, health checks, and frontend availability in `nmtk/neuro_toolkit/assets/modules.json`.
- Improve the launcher-module contract rather than rewriting the UI stack.

The most useful improvements are:

- Add stronger module readiness checks before loading a WebView.
- Add cache-busting or cache-clearing behavior for rebuilt module frontends.
- Standardize module loading, error, offline, and degraded-capability screens.
- Keep shared visual components in `nmtk_ui_core` so module UIs feel consistent.
- Keep backend endpoint smoke tests and launcher guardrails as the source of truth for runtime behavior.
- Document which modules are local-only, web-capable, hardware-dependent, or CLI-only.

## When to Reconsider

Consider moving toward all desktop if:

- Most module UIs need deep native OS integration.
- WebView behavior becomes the main source of bugs.
- The project is intentionally becoming one tightly integrated desktop product.
- Browser or remote usage is no longer important.

Consider moving toward all web if:

- The suite becomes cloud-hosted.
- Users no longer need local Python environment management from the UI.
- Hardware deployment moves to remote services or a dedicated local agent.
- Collaboration, browser access, and managed deployment become more important than offline local execution.

## Bottom Line

The current desktop-shell plus web-module architecture is not just a compromise. For this codebase, it is a pragmatic fit because NeuroMorphicToolKit is both a local runtime manager and a collection of independently owned tools.

The main risk is not the hybrid model itself. The main risk is weak contracts between the desktop launcher, local backends, and embedded frontends. The project should invest in better launcher guardrails, health checks, shared UI conventions, and WebView reliability before considering a full rewrite to all desktop or all web.
