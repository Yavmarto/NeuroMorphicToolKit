# NMTK Launcher (neuro_toolkit)

The Flutter desktop application for the NeuroMorphicToolKit suite. This is the only shipped app in the repository.

**The app shell is documented in the [root README](../../README.md#architecture).** That is the single source for how the launcher composes module surfaces; this file covers only what lives in this directory.

## What this app does

It is deliberately thin. The launcher:

- Hosts a single `MaterialApp` and the suite theme
- Owns localization, accessibility scaling, shortcuts, and global overlays for mounted surfaces
- Fetches the module manifest from `launcher-control` and tracks module lifecycle and health
- Handles backend connection and setup, and the update dialog
- Mounts exactly **one** module surface, full-window, and renders no navigation chrome of its own
- Hosts a WebView for modules that are not native surfaces, such as Jupyter

Everything a user sees — nav, chrome, workspace switching, the pipeline — belongs to the mounted surface, which in practice is NeuroStudio. `NativeSurfaceRegistry` is the hand-maintained map from a manifest module id to a Flutter surface builder; it is the real plugin mechanism.

NeuroStudio is compiled as the internal `neurocnl_studio` feature package. It has no standalone
Flutter runner and renders its GoRouter directly beneath this app's `MaterialApp`.

## Key files

- `assets/modules.json` — the bundled module manifest. At runtime the manifest served by `launcher-control` takes precedence.
- `lib/main.dart` — entry point.
- `lib/neuro_toolkit_app.dart` — the single `MaterialApp`.
- `lib/workspace/native_surface_registry.dart` — registration of native module surfaces.
- `lib/screens/tool_view.dart` — mounts the active module surface.

The launcher has no router; it is a single `MaterialApp.home`.

## Local development

```bash
flutter pub get
```
```bash
flutter run -d macos --dart-define=SUITE_API_URL=http://127.0.0.1:9000
```

Run both from this directory. Without the `--dart-define`, the app boots against its `127.0.0.1` default and lands on `/setup`, where the "Already have a server running?" field can point it at another host.

Default backend: `suite_api` on port 9000. The control plane is defined in [ADR 0023](../../docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md).

## License

GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
