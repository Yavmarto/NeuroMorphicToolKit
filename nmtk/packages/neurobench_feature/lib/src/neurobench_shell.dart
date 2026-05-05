import 'package:flutter/widgets.dart';
import 'package:neurobench_frontend/shell_adapter.dart';

/// Feature flag — set to false during migration to use the WebView fallback.
/// Always true from Phase 3D onwards.
const bool kNeurobenchNativeScreen =
    bool.fromEnvironment('NATIVE_NEUROBENCH', defaultValue: true);

/// Top-level native screen for the Neurobench benchmarking domain.
/// Shell mode: NmtkShellMode.command — per AGENTS.md.
///
/// Wraps [NeurobenchShellAdapter]. API base URL is configured via the
/// SUITE_API_URL dart-define (resolved to http://localhost:9000/api/neurobench).
class NeurobenchShell extends StatelessWidget {
  const NeurobenchShell({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    return NeurobenchShellAdapter(initialLocation: initialLocation);
  }
}
