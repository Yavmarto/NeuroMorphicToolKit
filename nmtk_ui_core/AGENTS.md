# nmtk_ui_core

Read first:
- `../CODING_STYLE_GUIDE.md`
- `pubspec.yaml`
- `analysis_options.yaml`
- `docs/ADR-Gemini/0001-initial-architecture.md`
- `docs/ADR-claude/0001-barrel-export-pattern.md`
- `docs/ADR-claude/0003-zero-state-management-dependency.md`
- `docs/ADR-claude/0004-domain-specific-widget-library.md`

Constraints:
- `lib/nmtk_ui_core.dart` is the public API barrel; add or remove public models, theme exports, and widgets there intentionally.
- This package must stay state-management-agnostic. Keep runtime dependencies limited to Flutter core plus the package's declared UI dependencies; use callback-based APIs instead of Provider or Riverpod bindings.
- Shared widgets must remain self-contained and typed. If a widget needs app services, routing, HTTP clients, or module-specific state, it belongs in the consumer app instead.
- When a shared model changes, update every consumer package that imports it before treating the change as complete.
- Verify touched surfaces with `flutter test`.

Do NOT:
- Import `provider`, `flutter_riverpod`, or module-specific app code here.
- Expose a new public widget without adding it to the barrel export.
- Hide network calls, environment lookups, or launcher state inside a shared widget.
