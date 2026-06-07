import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/shell_tokens.dart';
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
    final zeta = Zeta.of(context);
    final colors = zeta.colors;
    final tokens = NmtkShellTokens.of(context);
    final workspaceStateAsync = ref.watch(workspaceNotifierProvider);
    final moduleStateAsync = ref.watch(moduleNotifierProvider);
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
                final foregroundColor =
                    isActive ? colors.mainDefault : colors.mainSubtle;
                final backgroundColor = isActive
                    ? colors.surfaceDefault
                    : colors.surfaceDefault.withValues(alpha: 0.18);
                final borderColor = isActive
                    ? colors.mainPrimary.withValues(alpha: 0.4)
                    : colors.borderSubtle.withValues(alpha: 0.22);

                return Padding(
                  padding: EdgeInsets.only(
                    right: index == activeModules.length - 1
                        ? 0
                        : tokens.compactGap,
                  ),
                  child: Semantics(
                    label: '${module.name} module tab',
                    selected: isActive,
                    button: true,
                    child: Material(
                      color: colors.surfaceDefault.withValues(alpha: 0),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(tokens.radiusMd),
                        onTap: () => onTabSelected(module.id),
                        child: Ink(
                          key: ValueKey<String>('module-tab-${module.id}'),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMd,
                            ),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                module.hasFrontend ? Icons.web : Icons.api,
                                size: 16,
                                color: foregroundColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                module.name,
                                style: Zeta.of(context)
                                    .textStyles
                                    .bodyMedium
                                    .copyWith(
                                      fontWeight: isActive
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: foregroundColor,
                                    ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox.square(
                                dimension: 44,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: foregroundColor,
                                  ),
                                  onPressed: () => onTabClosed(module.id),
                                  tooltip: 'Close ${module.name}',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 44,
                                    height: 44,
                                  ),
                                  splashRadius: 22,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
