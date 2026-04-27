import 'package:flutter/widgets.dart';
import 'package:neurohub_shell_adapter/neurohub_shell_adapter.dart';

/// Feature flag — set to false during migration to use the WebView fallback.
/// Always true from Phase 3F onwards.
const bool kNeurohubNativeScreen =
    bool.fromEnvironment('NATIVE_NEUROHUB', defaultValue: true);

/// Top-level native screen for the Neurohub suite orchestration domain.
/// Shell mode: NmtkShellMode.command — per AGENTS.md.
///
/// Wraps [NeurohubShellAdapter]. API base URL configured via SUITE_API_URL
/// (resolved to http://localhost:9000/api/neurohub).
/// Also serves as the unified dashboard entry point after Phase 3F.
class NeurohubShell extends StatelessWidget {
  const NeurohubShell({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    return NeurohubShellAdapter(initialLocation: initialLocation);
  }
}
