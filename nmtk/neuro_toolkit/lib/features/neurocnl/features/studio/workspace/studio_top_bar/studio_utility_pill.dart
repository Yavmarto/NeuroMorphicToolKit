import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/autosave_status_indicator.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/running_tasks_indicator.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/workspace_tab_file_view_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/zeta_styled_tab.dart';

class StudioUtilityPill extends StatelessWidget {
  const StudioUtilityPill({
    super.key,
    required this.files,
    required this.activeFileId,
    required this.workspaceName,
    required this.onSelected,
    required this.onClosed,
    required this.onSaveActiveFile,
    this.workspaceHeaderAction,
  });

  final List<WorkspaceTabFileViewData> files;
  final String activeFileId;
  final String workspaceName;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onClosed;
  final VoidCallback onSaveActiveFile;
  final Widget? workspaceHeaderAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shellTokens = NmtkShellTokens.of(context);

    return Container(
      key: const Key('studio-utility-pill'),
      height: 52,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(shellTokens.radiusChip),
        border: Border.all(color: shellTokens.subtleBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(shellTokens.radiusChip),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Save workspace',
                child: ZetaIconButton.text(
                  icon: ZetaIcons.save,
                  semanticLabel: 'Save workspace',
                  onPressed: onSaveActiveFile,
                ),
              ),
              const SizedBox(width: 8),
              const AutosaveStatusIndicator(),
              const SizedBox(width: 8),
              const RunningTasksIndicator(),
              const SizedBox(width: 8),
              _buildWorkspaceTab(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceTab(BuildContext context) {
    if (files.length <= 1) {
      final activeFile = files.isEmpty
          ? null
          : files.firstWhere(
              (f) => f.id == activeFileId,
              orElse: () => files.first,
            );
      final dirty = activeFile?.dirty ?? false;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZetaStyledTab(
            label: dirty ? '$workspaceName *' : workspaceName,
            isActive: true,
            onTap: activeFile == null ? null : () => onSelected(activeFile.id),
          ),
          if (workspaceHeaderAction != null) ...[
            const SizedBox(width: 8),
            workspaceHeaderAction!,
          ],
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ZetaStyledTab(
          label: workspaceName,
          isActive: false,
          isHeader: true,
          onTap: null,
        ),
        if (workspaceHeaderAction != null) ...[
          const SizedBox(width: 8),
          workspaceHeaderAction!,
        ],
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              shrinkWrap: true,
              itemCount: files.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final file = files[index];
                final isActive = file.id == activeFileId;
                final label = file.dirty ? '${file.name} *' : file.name;
                return ZetaStyledTab(
                  label: label,
                  isActive: isActive,
                  onTap: () => onSelected(file.id),
                  trailing: Tooltip(
                    message: 'Close',
                    child: ZetaIconButton.text(
                      icon: ZetaIcons.close,
                      size: ZetaWidgetSize.small,
                      semanticLabel: 'Close',
                      onPressed: () => onClosed(file.id),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
