import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';

class RunningTasksDialog extends ConsumerWidget {
  const RunningTasksDialog({super.key, required this.onCancel});

  final Future<void> Function(RunningNotebookTask task) onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks =
        ref.watch(runningNotebookTasksProvider).value ??
        const <RunningNotebookTask>[];
    final colors = Zeta.of(context).colors;

    return AlertDialog(
      title: const Text('Notebook Tasks'),
      content: SizedBox(
        width: 360,
        child: tasks.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nothing running right now.'),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final task in tasks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            task.isExecuting ? ZetaIcons.play : ZetaIcons.note,
                            size: 16,
                            color: task.isExecuting
                                ? NmtkShellTokens.of(context).runningColor
                                : colors.mainSubtle,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              task.isExecuting
                                  ? task.label
                                  : '${task.label} (open, not running)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Tooltip(
                            message: 'Stop',
                            child: ZetaIconButton.negative(
                              icon: ZetaIcons.stop,
                              size: ZetaWidgetSize.small,
                              semanticLabel: 'Stop',
                              onPressed: () => onCancel(task),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        ZetaButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Close',
        ),
      ],
    );
  }
}
