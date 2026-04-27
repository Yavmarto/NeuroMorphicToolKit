import 'package:flutter/widgets.dart';
import 'package:neurocnl_studio/shell_adapter.dart';

/// Feature flag — set to false during migration to use the WebView fallback.
/// Always true from Phase 3A onwards.
const bool kNeurocnlNativeScreen =
    bool.fromEnvironment('NATIVE_NEUROCNL', defaultValue: true);

/// Top-level native screen for the neurocnl CNL Studio domain.
///
/// Wraps [NeurocnlShellAdapter] from the neurocnl_studio package.
/// The API base URL is configured via the SUITE_API_URL dart-define
/// (see neurocnl/frontend/lib/config/app_config.dart).
class NeurocnlShell extends StatelessWidget {
  const NeurocnlShell({super.key, this.initialLocation = '/'});

  final String initialLocation;

  @override
  Widget build(BuildContext context) {
    return NeurocnlShellAdapter(initialLocation: initialLocation);
  }
}
