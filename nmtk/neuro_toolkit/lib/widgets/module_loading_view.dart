import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';

/// Displays a branded loading card while a module's backend is starting up.
///
/// In debug builds, shows the health-check URL and current status message
/// to help diagnose slow-start issues.
class ModuleLoadingView extends StatelessWidget {
  const ModuleLoadingView({
    required this.module,
    required this.healthCheckUri,
    super.key,
  });

  final Module module;

  /// The URI that the launcher polls to detect when the backend is ready.
  /// Only shown in debug builds.
  final Uri? healthCheckUri;

  @override
  Widget build(BuildContext context) {
    final zeta = Zeta.of(context);
    final colors = zeta.colors;

    // Installing/updating is a distinct, potentially long phase (the backend
    // pip-installs its environment on first bring-up). Surface it explicitly —
    // with a determinate bar when progress is reported — so a multi-minute
    // install reads as "working", not "hung".
    final bool isInstalling = module.status == ModuleStatus.installing;
    final bool isUpdating = module.status == ModuleStatus.updating;
    // Externally managed services (e.g. Jupyter) are never installed/started by
    // the launcher — it only health-probes them while they come up. Their env
    // is built at deploy time, so a long first-run wait is expected rather than
    // a hang. Since this view only renders while the module is NOT ready, an
    // externally managed module here is always "being prepared / waited on".
    final bool isPreparingExternal =
        module.isExternallyManaged && !isInstalling && !isUpdating;
    final bool hasProgress =
        (isInstalling || isUpdating) && module.installProgress > 0.0;

    final String title;
    if (isInstalling) {
      title = 'Installing ${module.name} backend';
    } else if (isUpdating) {
      title = 'Updating ${module.name} backend';
    } else if (isPreparingExternal) {
      title = 'Preparing ${module.name} backend';
    } else {
      title = 'Waiting for ${module.name}';
    }

    final String subtitle;
    if (isInstalling || isUpdating) {
      final verb = isInstalling ? 'Installing' : 'Updating';
      subtitle = hasProgress
          ? '$verb the backend environment — ${(module.installProgress * 100).round()}%.\n\nThis can take several minutes the first time while packages download.'
          : '$verb the backend environment.\n\nThis can take several minutes the first time while packages download.';
    } else if (isPreparingExternal) {
      subtitle =
          'Setting up the ${module.name} backend. The first run can take several minutes while its environment is installed.';
    } else if (kDebugMode) {
      subtitle = [
        if (module.statusMessage != null) module.statusMessage!,
        if (module.status == ModuleStatus.starting && healthCheckUri != null)
          'Backend: $healthCheckUri'
        else
          'Starting ${module.name} backend for this tab',
        'Some modules take a little longer to warm up.',
      ].join('\n\n');
    } else {
      subtitle = 'Starting up, this may take a moment.';
    }

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
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: NmtkStatusBadge(
                      label: 'Debug',
                      tone: NmtkTone.warning,
                      icon: Icons
                          .bug_report_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                    ),
                  ),
                ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Zeta.of(
                  context,
                ).textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Zeta.of(
                  context,
                ).textStyles.bodyMedium.copyWith(color: colors.mainSubtle),
              ),
              const SizedBox(height: 14),
              hasProgress
                  ? ZetaProgressBar.standard(
                      progress: module.installProgress,
                      isThin: true,
                    )
                  : const ZetaProgressBar.indeterminate(isThin: true),
            ],
          ),
        ),
      ),
    );
  }
}
