import 'package:flutter/widgets.dart';
import 'package:neurosense_shell_adapter/neurosense_shell_adapter.dart';

/// Feature flag — set to false during migration to use the WebView fallback.
/// Always true from Phase 3E onwards.
const bool kNeurosenseNativeScreen =
    bool.fromEnvironment('NATIVE_NEUROSENSE', defaultValue: true);

/// Top-level native screen for the Neurosense biosignal acquisition domain.
/// Shell mode: NmtkShellMode.instrument (cyan) — per AGENTS.md.
///
/// Wraps [NeurosenseShellAdapter]. API base URL is configured via the
/// SUITE_API_URL dart-define (ws://localhost:9000/api/neurosense/stream for WebSocket).
class NeurosenseShell extends StatelessWidget {
  const NeurosenseShell({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    return NeurosenseShellAdapter(initialLocation: initialLocation);
  }
}
