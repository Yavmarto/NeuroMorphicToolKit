import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
import 'package:nmtk_ui_core/motion_tokens.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

class ModuleTabBar extends ConsumerWidget {
  final String activeModuleId;
  final void Function(String) onTabSelected;
  final void Function(String) onTabClosed;
  final Widget? trailing;

  const ModuleTabBar({
    super.key,
    required this.activeModuleId,
    required this.onTabSelected,
    required this.onTabClosed,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);
    final workspaceStateAsync = ref.watch(workspaceProvider);
    final moduleStateAsync = ref.watch(moduleProvider);
    final workspace = workspaceStateAsync.value;
    final modules = moduleStateAsync.value?.modules ?? [];

    if (workspace == null) return const SizedBox.shrink();
    final activeModules = workspace.sessions
        .map((session) {
          for (final module in modules) {
            if (module.id == session.moduleId) {
              return module;
            }
          }
          return null;
        })
        .whereType<Module>()
        .toList(growable: false);

    if (activeModules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      padding: EdgeInsets.fromLTRB(
        tokens.compactGap,
        2,
        trailing == null ? tokens.compactGap : 8,
        2,
      ),
      decoration: BoxDecoration(
        color: tokens.workspaceBarBackground,
        border: Border(
          bottom: BorderSide(color: tokens.chromeBorder),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: activeModules.length,
              itemBuilder: (context, index) {
                final module = activeModules[index];
                final isActive = module.id == activeModuleId;
                return Padding(
                  key: ValueKey<String>(module.id),
                  padding: EdgeInsets.only(
                    right: index == activeModules.length - 1
                        ? 0
                        : tokens.compactGap,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ZetaButton(
                        key: ValueKey<String>('module-tab-${module.id}'),
                        label: module.name,
                        semanticLabel: '${module.name} module tab',
                        leadingIcon: module.hasFrontend ? Icons.web : Icons.api,
                        type: isActive
                            ? ZetaButtonType.primary
                            : ZetaButtonType.outlineSubtle,
                        onPressed: () => onTabSelected(module.id),
                      ),
                      ZetaIconButton.text(
                        icon: ZetaIcons.close,
                        semanticLabel: 'Close ${module.name}',
                        onPressed: () => onTabClosed(module.id),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: NmtkMotionTokens.durationFast)
                    .slideX(begin: 0.3, curve: NmtkMotionTokens.easeEnter);
              },
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
