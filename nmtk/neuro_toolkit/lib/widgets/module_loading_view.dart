import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';

/// Displays a branded loading card while a module's backend is starting up.
///
/// In debug builds, shows the health-check URL and current status message
/// to help diagnose slow-start issues.
class ModuleLoadingView extends StatelessWidget {
  const ModuleLoadingView({
    required this.module,
    required this.healthCheckUri,
    required this.onOpenInBrowser,
    super.key,
  });

  final Module module;

  /// The URI that the launcher polls to detect when the backend is ready.
  /// Only shown in debug builds.
  final Uri? healthCheckUri;

  final VoidCallback onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    final zeta = Zeta.of(context);
    final colors = zeta.colors;
    final tokens = NmtkShellTokens.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: NmtkSurfaceCard(
          tone: NmtkTone.info,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kDebugMode)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: NmtkStatusBadge(
                      label: 'Debug',
                      tone: NmtkTone.warning,
                      icon: Icons.bug_report_outlined,
                    ),
                  ),
                ),
              Text(
                'Waiting for ${module.name}',
                textAlign: TextAlign.center,
                style: ZetaTextStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                kDebugMode
                    ? [
                        if (module.statusMessage != null) module.statusMessage!,
                        if (module.status == ModuleStatus.starting &&
                            healthCheckUri != null)
                          'Backend: $healthCheckUri'
                        else
                          'Starting ${module.name} backend for this tab',
                        'Some modules take a little longer to warm up.',
                      ].join('\n\n')
                    : 'Starting up, this may take a moment.',
                textAlign: TextAlign.center,
                style: ZetaTextStyles.bodyMedium.copyWith(
                  color: colors.mainSubtle,
                ),
              ),
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
              const SizedBox(height: 14),
              NmtkOutlinedButton(
                onPressed: onOpenInBrowser,
                icon: Icons.open_in_browser,
                label: 'Open in Browser instead',
                tone: NmtkTone.info,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
