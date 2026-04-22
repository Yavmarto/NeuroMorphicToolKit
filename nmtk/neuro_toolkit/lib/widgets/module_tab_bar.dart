import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

class ModuleTabBar extends ConsumerWidget {
  final String activeModuleId;
  final void Function(String) onTabSelected;
  final void Function(String) onTabClosed;

  const ModuleTabBar({
    super.key,
    required this.activeModuleId,
    required this.onTabSelected,
    required this.onTabClosed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(moduleStateProvider);
    final activeModules = provider.activeModules;

    if (activeModules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: activeModules.length,
        itemBuilder: (context, index) {
          final module = activeModules[index];
          final isActive = module.id == activeModuleId;

          return InkWell(
            onTap: () => onTabSelected(module.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.surface
                    : Colors.transparent,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                  bottom: isActive
                      ? BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    module.hasFrontend ? Icons.web : Icons.api,
                    size: 16,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    module.name,
                    style: TextStyle(
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: () => onTabClosed(module.id),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 16,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
