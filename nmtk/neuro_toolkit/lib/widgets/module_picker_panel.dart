import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_navigation_notifier.dart';
import 'package:neuro_toolkit/widgets/connection_error_actions.dart';
import 'package:neuro_toolkit/widgets/server_setup_popup.dart';

part 'module_picker_panel/module_card.dart';
part 'module_picker_panel/module_activity_state.dart';
part 'module_picker_panel/module_progress_state.dart';
part 'module_picker_panel/status_message_bar.dart';

/// A scrollable grid of module cards.
///
/// Used as the [ToolViewScreen] empty state (full-screen) and as a bottom
/// sheet when the user taps "+" in the workspace tab bar. The panel is
/// stateless — all lifecycle actions delegate to [moduleStateProvider].
class ModulePickerPanel extends ConsumerWidget {
  const ModulePickerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moduleStateAsync = ref.watch(moduleProvider);
    final moduleState = moduleStateAsync.value;
    final controller = ref.read(moduleProvider.notifier);
    final hasSelectedServer =
        ref.watch(selectedControlApiServiceProvider) != null;
    final theme = Theme.of(context);

    if (moduleStateAsync.isLoading || moduleState == null) {
      return const Center(child: ZetaProgressCircle(size: ZetaCircleSizes.s));
    }

    if (moduleStateAsync.hasError) {
      return NmtkEmptyState(
        title: 'Catalog Unavailable',
        message: moduleStateAsync.error.toString(),
        icon: ZetaIcons.cloud_off,
        tone: NmtkTone.danger,
        action: ConnectionErrorActions(
          onRetry: () => ref.invalidate(moduleProvider),
          onChangeServer: () => showAdaptiveServerSetupPopup(context),
        ),
      );
    }

    final modules = moduleState.modules;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Modules',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Browse, install, and launch toolkit modules.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (modules.isEmpty)
          NmtkEmptyState(
            title: hasSelectedServer
                ? 'No Modules Available'
                : 'Connect to a server',
            message: hasSelectedServer
                ? 'The launcher did not load any modules.'
                : 'Choose an existing server or set up a new one to load '
                    'your modules.',
            icon: hasSelectedServer
                ? Icons
                    .inventory_2_outlined // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                : ZetaIcons.cloud_off,
            action: hasSelectedServer
                ? null
                : ZetaButton(
                    onPressed: () => showAdaptiveServerSetupPopup(context),
                    label: 'Connect to server',
                  ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final crossAxisCount = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 840
                      ? 2
                      : 1;
              final cardWidth =
                  (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                      crossAxisCount;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: modules.indexed.map(((int, Module) entry) {
                  final index = entry.$1;
                  final module = entry.$2;
                  final isMuJoCoUnavailable =
                      module.requiresMuJoCo && !moduleState.mujocoAvailable;
                  return SizedBox(
                    width: cardWidth,
                    child: _ModuleCard(
                      module: module,
                      isMuJoCoUnavailable: isMuJoCoUnavailable,
                      onInstall: () => controller.installModule(module.id),
                      onLaunch: () => controller.launchModule(module.id),
                      onOpen: () => ref
                          .read(launcherNavigationProvider.notifier)
                          .openModule(module.id),
                      onStop: () => controller.stopModule(module.id),
                      onUpdate: _hasUpdateAvailable(module)
                          ? () => unawaited(controller.updateModule(module.id))
                          : null,
                      onRepair: () => controller.repairModule(module.id),
                    )
                        .animate(delay: Duration(milliseconds: 40 * index))
                        .fadeIn(duration: NmtkMotionTokens.durationBase)
                        .slideY(
                          begin: 0.06,
                          curve: NmtkMotionTokens.easeEnter,
                        ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  static bool _hasUpdateAvailable(Module module) {
    return !module.versionPinned &&
        UpdateService.isNewerVersion(module.version, module.remoteVersion);
  }
}

// ---------------------------------------------------------------------------
// Module card
// ---------------------------------------------------------------------------
