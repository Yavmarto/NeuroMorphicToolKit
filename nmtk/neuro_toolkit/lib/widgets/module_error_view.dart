import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:flutter/widget_previews.dart';
import 'package:neuro_toolkit/models/module.dart';

/// Tracks a failed WebView page load for a given module.
class ModuleLoadFailure {
  const ModuleLoadFailure({required this.uri, required this.message});

  final Uri uri;
  final String message;
}

/// Displays a user-friendly error state when a module's WebView fails to load.
///
/// Provides a Retry button (clears the cached controller so the URL is
/// re-fetched) and an Open-in-Browser fallback.
class ModuleErrorView extends StatelessWidget {
  const ModuleErrorView({
    required this.module,
    required this.failure,
    required this.isRemoteHosted,
    required this.onRetry,
    required this.onOpenInBrowser,
    super.key,
  });

  final Module module;
  final ModuleLoadFailure failure;

  /// Whether the app is currently pointing at a remote/hosted service
  /// (e.g. Android device accessing a desktop-hosted suite). Affects the
  /// hint text shown alongside the error.
  final bool isRemoteHosted;

  final VoidCallback onRetry;
  final VoidCallback onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    final hostHint = isRemoteHosted
        ? 'Confirm that ${failure.uri} is reachable from the Android device '
            'and that the suite API is serving the module frontend on that host.'
        : 'Confirm that the launcher host is configured correctly for mobile '
            'and that the suite API is reachable from this device.';

    return NmtkEmptyState(
      title: '${module.name} Page Could Not Load',
      message: [
        failure.message,
        'Requested URL: ${failure.uri}',
        hostHint,
      ].join('\n\n'),
      icon: Icons.language_outlined,
      tone: NmtkTone.warning,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NmtkPrimaryButton(
            onPressed: onRetry,
            icon: Icons.refresh,
            label: 'Retry Load',
            tone: NmtkTone.warning,
          ),
          const SizedBox(height: 12),
          NmtkOutlinedButton(
            onPressed: onOpenInBrowser,
            icon: Icons.open_in_browser,
            label: 'Open in Browser',
            tone: NmtkTone.warning,
          ),
        ],
      ),
    );
  }
}
