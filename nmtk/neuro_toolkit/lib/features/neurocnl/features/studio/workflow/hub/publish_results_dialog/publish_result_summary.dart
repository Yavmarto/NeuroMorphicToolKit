import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/hub/publish_results_dialog/support.dart';

class PublishResultSummary extends ConsumerWidget {
  const PublishResultSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(workspaceProvider);
    final pipeline = ref.watch(pipelineProvider);
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;

    final seenLabels = <String>{};
    final rows = <MapEntry<String, String>>[];
    void addRow(String label, String value) {
      final key = label.trim().toLowerCase();
      if (!seenLabels.add(key)) return;
      rows.add(MapEntry(label, value));
    }

    addRow('Workspace', workspace.workspaceName);
    if (workspace.selectedDeployTarget.isNotEmpty) {
      addRow('Target', targetLabel(workspace.selectedDeployTarget));
    }

    final simulation = pipeline.simulateResult;
    if (simulation != null) {
      addRow(
        'Duration',
        '${simulation.duration.toStringAsFixed(2)}s over '
            '${simulation.timesteps} steps',
      );
      final summary = simulation.summary;
      addRow(
        'Sensory activity',
        '${summary.sensorySpikeCount} spikes • '
            '${summary.sensoryMeanRate.toStringAsFixed(1)} Hz avg',
      );
      addRow(
        'Motor activity',
        '${summary.motorSpikeCount} spikes • '
            '${summary.motorMeanRate.toStringAsFixed(1)} Hz avg',
      );
      if (summary.inputToOutputLatency case final latency?) {
        addRow('Input → output latency', '${latency.toStringAsFixed(1)} s');
      }
    }

    for (final entry in workspace.benchmarkResultSummary.entries) {
      addRow(publishResultTitleCase(entry.key), entry.value.toString());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Result summary',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (final row in rows) ...[
          Text(
            row.key,
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          ),
          const SizedBox(height: 2),
          Text(row.value, style: textStyles.bodyMedium),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
