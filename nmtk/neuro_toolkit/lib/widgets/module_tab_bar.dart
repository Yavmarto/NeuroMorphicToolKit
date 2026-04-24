import 'package:flutter/material.dart';
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = NmtkShellTokens.of(context);
    final workspace = ref.watch(workspaceStateProvider);
    final modules = ref.watch(moduleStateProvider).modules;
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
        6,
        trailing == null ? tokens.compactGap : 8,
        6,
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
                final foregroundColor = isActive
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant;
                final backgroundColor = isActive
                    ? colorScheme.surface
                    : colorScheme.surface.withValues(alpha: 0.18);
                final borderColor = isActive
                    ? colorScheme.primary.withValues(alpha: 0.4)
                    : colorScheme.outlineVariant.withValues(alpha: 0.22);

                return Padding(
                  padding: EdgeInsets.only(
                    right: index == activeModules.length - 1
                        ? 0
                        : tokens.compactGap,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(tokens.radiusMd),
                      onTap: () => onTabSelected(module.id),
                      child: Ink(
                        key: ValueKey<String>('module-tab-${module.id}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(tokens.radiusMd),
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
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: foregroundColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: foregroundColor,
                              ),
                              onPressed: () => onTabClosed(module.id),
                              tooltip: 'Close ${module.name}',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 18,
                                height: 18,
                              ),
                              splashRadius: 16,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
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
