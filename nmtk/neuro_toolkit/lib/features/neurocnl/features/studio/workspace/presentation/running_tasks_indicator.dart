import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/running_tasks_dialog.dart';

class RunningTasksIndicator extends ConsumerWidget {
  const RunningTasksIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(runningNotebookTasksProvider);
    final tasks = tasksAsync.value ?? const <RunningNotebookTask>[];
    // A live Jupyter kernel session with nothing executing (the common case
    // right after simply opening a notebook) must not surface as "running" —
    // only tasks with actual code executing count toward the badge.
    final executingTasks = tasks.where((t) => t.isExecuting).toList();
    if (executingTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final colors = Zeta.of(context).colors;
    return Tooltip(
      message:
          '${executingTasks.length} notebook task'
          '${executingTasks.length == 1 ? '' : 's'} running',
      child: InkWell(
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusChip,
        ),
        onTap: () => _showTasksDialog(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.mainInfo.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(
              NmtkShellTokens.of(context).radiusChip,
            ),
            border: Border.all(color: colors.mainInfo),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.mainInfo,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${executingTasks.length}',
                style: TextStyle(
                  color: colors.mainInfo,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTasksDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => RunningTasksDialog(
        onCancel: (task) =>
            ref.read(runningNotebookTasksProvider.notifier).cancel(task),
      ),
    );
  }
}
