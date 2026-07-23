import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Shared action row for "can't reach a server" error states.
///
/// Every reachability failure in this app should offer both: retry the same
/// target, or point the app at a different one. A bare "Retry" is a dead end
/// when the target itself is wrong — this widget keeps that pairing
/// consistent instead of each screen inventing its own button row.
class ConnectionErrorActions extends StatelessWidget {
  const ConnectionErrorActions({
    super.key,
    required this.onRetry,
    this.onChangeServer,
    this.retryLabel = 'Retry',
    this.changeServerLabel = 'Change server',
  });

  final VoidCallback onRetry;

  /// Omit when the failure isn't about a redirectable target (e.g. a
  /// sub-resource fetch within an already-connected session).
  final VoidCallback? onChangeServer;
  final String retryLabel;
  final String changeServerLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Wrap(
      spacing: tokens.compactGap,
      runSpacing: tokens.compactGap,
      children: [
        ZetaButton.primary(
          onPressed: onRetry,
          leadingIcon: ZetaIcons.refresh,
          label: retryLabel,
        ),
        if (onChangeServer != null)
          ZetaButton.outline(
            onPressed: onChangeServer,
            leadingIcon: ZetaIcons.server,
            label: changeServerLabel,
          ),
      ],
    );
  }
}
