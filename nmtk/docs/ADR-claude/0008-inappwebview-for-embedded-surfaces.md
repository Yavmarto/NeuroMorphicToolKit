# ADR 0008: `flutter_inappwebview` for Embedded Module Surfaces

## Status
Accepted

## Context
ADR 0004 introduced WebView embedding (via `desktop_webview_window`, later
`webview_flutter`) for module web frontends, and is itself superseded by ADR
0019 (native Flutter feature packages) for *first-party* modules. But not
every embedded surface can become a native Flutter package: Jupyter is a
third-party JupyterLab web app served by the `jupyter_server` worker, so an
embedded WebView remains the only option for it.

`ToolViewScreen` rendered that surface with `webview_flutter ^4.10.0`, whose
macOS/WKWebView backend (`webview_flutter_wkwebview`) has two disqualifying
limitations on the launcher's primary desktop platform:

1. **No native file open-panel.** WKWebView only shows a file dialog when the
   host app implements `WKUIDelegate.webView(_:runOpenPanelWith:…)`.
   `webview_flutter_wkwebview` does not, so any in-page `<input type="file">`
   — including JupyterLab's **Upload Files** toolbar button — silently does
   nothing. The button could never work.
2. **Hover repaint flicker.** The macOS backend repaints the whole webview
   surface on pointer/cursor changes, so hovering the embedded toolbar
   flickers continuously.

A prior attempt (`jupyter_webview_injector.dart`) tried to patch both from
inside the page with injected CSS (`transition: none`) and a transparent
overlay `<input type="file">`. The overlay approach was architecturally
incapable of working: the overlaid input is still inside WKWebView and hits
the same missing delegate. The CSS only suppressed one narrow flicker trigger.

## Decision
Replace `webview_flutter` with `flutter_inappwebview ^6.1.5` for the embedded
(non-native) module surface in `ToolViewScreen`. `flutter_inappwebview` wires
up the WKUIDelegate open panel on Apple platforms (and the Android file
chooser), so the in-page upload button works natively, and composites cleanly
on macOS, removing the flicker. Both fixes happen at the platform layer, so
the CSS/JS injection workaround is deleted.

Mapping of the previous `webview_flutter` integration to `flutter_inappwebview`:

| `webview_flutter`                     | `flutter_inappwebview`                          |
|---------------------------------------|-------------------------------------------------|
| `WebViewController` + `WebViewWidget` | `InAppWebView` (controller via `onWebViewCreated`) |
| `loadRequest(uri)`                    | `loadUrl(urlRequest: URLRequest(url: WebUri))`  |
| `onPageStarted`                       | `onLoadStart`                                   |
| `onNavigationRequest` → `NavigationDecision` | `shouldOverrideUrlLoading` → `NavigationActionPolicy` |
| `onWebResourceError`                  | `onReceivedError`                               |
| `onHttpError`                         | `onReceivedHttpError`                           |

The webview is keyed by module id inside the existing `IndexedStack`, so the
native webview is created once and preserved across tab switches and the
3-second provider polling rebuilds — no reload on rebuild, matching prior
behavior.

`onReceivedHttpError` now guards on `request.isForMainFrame`, which the old
`onHttpError` path did not. JupyterLab routinely fires sub-resource 404s
(optional extension probes); without the guard these were recorded as
main-page load failures, which could surface the module error view.

The change is scoped to the launcher's embedded-surface code path only; it
touches no module manifest, port, health-check, or tool-routing contract, so
launcher manifest/Dart-model synchronization is unaffected.

## Consequences

### Positive
- JupyterLab's **Upload Files** button opens a real native file dialog on
  macOS/iOS; uploads work without any in-page workaround.
- Embedded-toolbar hover flicker on macOS is resolved.
- `jupyter_webview_injector.dart` and its CSS/overlay workaround are deleted;
  no module-specific JS injection to maintain.
- The sub-resource HTTP-error guard prevents false "module failed to load"
  states for SPA frontends.

### Negative / Debt
- `flutter_inappwebview`'s macOS backend (`flutter_inappwebview_macos`) is its
  least battle-tested platform. `shouldOverrideUrlLoading`-based cross-module
  navigation interception may not fire on macOS; if it does not, navigation
  degrades to normal in-webview loading rather than a launcher tab switch.
  Verify cross-module deep-links on macOS before relying on them.
- `webview_flutter` is removed from `pubspec.yaml`. Any future embedded
  surface must use `flutter_inappwebview` to avoid reintroducing two webview
  stacks.
- `desktop_webview_window` remains declared (legacy from ADR 0004) and unused
  by `ToolViewScreen`; a follow-up should remove it if nothing else depends
  on it.
