import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/widgets/connection_error_actions.dart';

/// Tracks a failed WebView page load for a given module.
class ModuleLoadFailure {
  const ModuleLoadFailure({required this.uri, required this.message});

  final Uri uri;
  final String message;
}

/// Displays a user-friendly error state when a module's WebView fails to load.
///
/// Provides a Retry button that clears the cached controller so the URL is
/// re-fetched.
class ModuleErrorView extends StatelessWidget {
  const ModuleErrorView({
    required this.module,
    required this.failure,
    required this.isRemoteHosted,
    required this.onRetry,
    this.onChangeServer,
    super.key,
  });

  final Module module;
  final ModuleLoadFailure failure;

  /// Whether the app is currently pointing at a remote/hosted service
  /// (e.g. Android device accessing a desktop-hosted suite). Affects the
  /// hint text shown alongside the error.
  final bool isRemoteHosted;

  final VoidCallback onRetry;

  /// Only meaningful when [isRemoteHosted] — this failure is about the
  /// whole remote launcher host, not one module's port, so offer a way
  /// back to the Connect/Setup screen alongside retry.
  final VoidCallback? onChangeServer;

  @override
  Widget build(BuildContext context) {
    final hostHint = isRemoteHosted
        ? 'Confirm that ${failure.uri} is reachable from the Android device '
              'and that the suite API is serving the module frontend on that host.'
        : 'Confirm the launcher host is reachable and that this module\'s '
              'service is running — externally managed services like Jupyter '
              'need to be started separately from the launcher.';

    return NmtkEmptyState(
      title: '${module.name} page unavailable',
      message: [
        failure.message,
        'Requested URL: ${failure.uri}',
        hostHint,
      ].join('\n\n'),
      icon:
          Icons.language_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      tone: NmtkTone.info,
      compact: true,
      action: ConnectionErrorActions(
        onRetry: onRetry,
        retryLabel: 'Retry Load',
        onChangeServer: onChangeServer,
      ),
    );
  }
}
