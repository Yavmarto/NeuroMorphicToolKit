import 'package:flutter/widgets.dart';
import 'package:Neurosim_shell_adapter/Neurosim_shell_adapter.dart';

/// Feature flag — set to false during migration to use the WebView fallback.
/// Always true from Phase 3B onwards.
const bool kNeurosimNativeScreen =
    bool.fromEnvironment('NATIVE_NEUROSIM', defaultValue: true);

/// Top-level native screen for the Neurosim canvas domain.
///
/// Wraps [NeuroSimShellAdapter]. API base URL is configured via the
/// SUITE_API_URL dart-define (resolved to http://localhost:9000/api/neurosim).
class NeurosimShell extends StatelessWidget {
  const NeurosimShell({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    return NeuroSimShellAdapter(initialLocation: initialLocation);
  }
}
