import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';

class ServerWorkspacePickerDialog extends ConsumerWidget {
  const ServerWorkspacePickerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspacesAsync = ref.watch(serverWorkspacesProvider);
    final maxWidth = MediaQuery.sizeOf(context).width - 48;
    return AlertDialog(
      title: const Text('Load from server'),
      content: SizedBox(
        width: maxWidth.clamp(0.0, 640.0),
        height: 420,
        child: workspacesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(error.toString())),
          data: (workspaces) {
            if (workspaces.isEmpty) {
              return const Center(
                child: Text(
                  'No workspaces have been saved on this server yet.',
                ),
              );
            }
            return ListView.separated(
              itemCount: workspaces.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final workspace = workspaces[index];
                return ListTile(
                  title: Text(workspace.name),
                  subtitle: Text('Updated ${workspace.updatedAt}'),
                  trailing: const Icon(ZetaIcons.chevron_right),
                  onTap: () => Navigator.of(context).pop(
                    ServerWorkspaceChoice(
                      slug: workspace.slug,
                      name: workspace.name,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
