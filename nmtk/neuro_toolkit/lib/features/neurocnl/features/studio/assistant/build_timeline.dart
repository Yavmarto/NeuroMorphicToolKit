import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/cnl_patch_card.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_models.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/studio_agent_notifier.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/assistant/tool_call_card.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class BuildTimeline extends ConsumerWidget {
  const BuildTimeline({super.key, required this.entries});

  final List<StudioAgentTimelineEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'Assistant steps will appear here as tools run.',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final unlocked = ref.watch(unlockedStepsProvider);
    final notifier = ref.read(studioAgentNotifierProvider.notifier);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return switch (entry.kind) {
          StudioAgentTimelineKind.userMessage => messageBubble(
            context,
            text: entry.text ?? '',
            isUser: true,
          ),
          StudioAgentTimelineKind.assistantText => messageBubble(
            context,
            text: entry.text ?? '',
            isUser: false,
          ),
          StudioAgentTimelineKind.toolCall => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToolCallCard(entry: entry),
              for (final artifact
                  in entry.toolResult?.artifacts ??
                      const <StudioAgentArtifact>[])
                CnlPatchCard(artifact: artifact),
              if (entry.toolResult != null)
                nextActionChips(
                  context,
                  actions: entry.toolResult!.nextActions,
                  unlockedSteps: unlocked,
                  onStepSelected: notifier.applyStepSuggestion,
                ),
            ],
          ),
          StudioAgentTimelineKind.stepSuggestion => stepSuggestionChip(
            context,
            step: entry.pipelineStep ?? '',
            label: entry.suggestionLabel,
            unlocked: unlocked.contains(entry.pipelineStep),
            onTap: () => notifier.applyStepSuggestion(entry.pipelineStep ?? ''),
          ),
        };
      },
    );
  }
}

Widget messageBubble(
  BuildContext context, {
  required String text,
  required bool isUser,
}) {
  final colors = Zeta.of(context).colors;
  return Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isUser ? colors.mainPrimary : colors.surfaceHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Zeta.of(context).textStyles.bodyMedium.copyWith(
          color: isUser ? colors.surfacePrimary : colors.mainDefault,
        ),
      ),
    ),
  );
}

Widget nextActionChips(
  BuildContext context, {
  required List<StudioAgentNextAction> actions,
  required Set<String> unlockedSteps,
  required bool Function(String stepName) onStepSelected,
}) {
  if (actions.isEmpty) {
    return const SizedBox.shrink();
  }
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          if (pipelineStepForAction(action) != null)
            stepSuggestionChip(
              context,
              step: pipelineStepForAction(action)!,
              label: action.label ?? action.action,
              unlocked: unlockedSteps.contains(pipelineStepForAction(action)),
              onTap: () => onStepSelected(pipelineStepForAction(action)!),
            ),
      ],
    ),
  );
}

String? pipelineStepForAction(StudioAgentNextAction action) {
  if (action.pipelineStep != null) {
    return action.pipelineStep;
  }
  return switch (action.action) {
    'submit_simulation' || 'poll_simulation_job' => 'run',
    _ => null,
  };
}

Widget stepSuggestionChip(
  BuildContext context, {
  required String step,
  required bool unlocked,
  required VoidCallback onTap,
  String? label,
}) {
  SnnWorkflowPhase? phase;
  for (final candidate in SnnWorkflowPhase.values) {
    if (candidate.name == step) {
      phase = candidate;
      break;
    }
  }
  final stepLabel =
      label ?? (phase != null ? (kSnnStepLabels[phase] ?? step) : step);
  final colors = Zeta.of(context).colors;

  return ActionChip(
    label: Text(stepLabel),
    avatar: Icon(
      unlocked ? ZetaIcons.chevron_right : ZetaIcons.lock,
      size: 16,
      color: unlocked ? colors.mainPrimary : colors.mainDisabled,
    ),
    onPressed: unlocked ? onTap : null,
  );
}
