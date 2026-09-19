import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';

class ServerWorkspacePickerDialog extends ConsumerWidget {
  const ServerWorkspacePickerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspacesAsync = ref.watch(serverWorkspacesProvider);
    return SafeArea(
      child: AlertDialog(
        insetPadding: NmtkDialogSurface.insetPadding(context),
        title: const Text('Load from server'),
        content: ConstrainedBox(
          constraints: NmtkDialogSurface.constraints(
            context,
            maxWidth: 640,
            maxHeight: 420,
          ),
          child: SizedBox(
            width: 640,
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
                      trailing: Icon(
                        ZetaIcons.chevron_right,
                        color: Zeta.of(context).colors.mainSubtle,
                      ),
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
        ),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
          ),
        ],
      ),
    );
  }
}
