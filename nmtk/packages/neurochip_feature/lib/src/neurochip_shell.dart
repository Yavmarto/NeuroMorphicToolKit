import 'package:flutter/widgets.dart';
import 'package:neurochip/shell_adapter.dart';

/// Feature flag — set to false during migration to use the WebView fallback.
/// Always true from Phase 3C onwards.
const bool kNeurochipNativeScreen =
    bool.fromEnvironment('NATIVE_NEUROCHIP', defaultValue: true);

/// Top-level native screen for the Neurochip hardware deployment domain.
/// Shell mode: NmtkShellMode.instrument (cyan) — per AGENTS.md.
///
/// Wraps [NeurochipShellAdapter]. API base URL is configured via the
/// SUITE_API_URL dart-define (resolved to http://localhost:9000/api/neurochip).
class NeurochipShell extends StatelessWidget {
  const NeurochipShell({super.key, this.initialDeepLink});

  final String? initialDeepLink;

  @override
  Widget build(BuildContext context) {
    return NeurochipShellAdapter(initialDeepLink: initialDeepLink);
  }
}
