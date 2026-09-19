library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_voyager_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/host_module_navigation.dart';

class StudioVoyagerWorkspace extends ConsumerWidget {
  const StudioVoyagerWorkspace({super.key, required this.isCompact});

  final bool isCompact;

  static const _metricLabels = <String, String>{
    'cpu_latency_ms': 'CPU latency (ms)',
    'aipu_latency_ms': 'AIPU latency (ms)',
    'speedup': 'Speedup',
    'detection_count': 'Detections',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioVoyagerDeployProvider);
    final notifier = ref.read(studioVoyagerDeployProvider.notifier);
    final textStyles = Zeta.of(context).textStyles;
    final colors = Zeta.of(context).colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Axelera Voyager (YOLOv8n)',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Runs the fixed YOLOv8n conventional-accelerator pipeline through '
          'NeuroBench: Docker compile, then CPU vs AIPU latency benchmark. '
          'No CNL network is required.',
          style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ZetaButton.primary(
              key: const Key('voyager-run-benchmark'),
              label: state.isBusy ? 'Running…' : 'Compile & benchmark',
              leadingIcon: state.isBusy ? null : ZetaIcons.play,
              onPressed: state.isBusy ? null : notifier.runCompileAndBenchmark,
            ),
            if (state.hasCompareableResult)
              ZetaButton.text(
                key: const Key('voyager-open-compare'),
                label: 'Open NeuroBench Compare',
                leadingIcon: Icons
                    .compare_arrows_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                onPressed: () => _openCompare(context, state.result?.id),
              ),
          ],
        ),
        if (state.activityMessage != null) ...[
          const SizedBox(height: 12),
          Text(state.activityMessage!, style: textStyles.bodySmall),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 12),
          NmtkStatusBadge(
            label: state.errorMessage!,
            tone: NmtkTone.danger,
            icon: ZetaIcons.error_outline,
          ),
        ],
        if (state.phase == StudioVoyagerDeployPhase.running) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (state.phase == StudioVoyagerDeployPhase.hardwarePending) ...[
          const SizedBox(height: 12),
          const NmtkStatusBadge(
            label:
                'AIPU: pending hardware — Metis not available yet (CEL-238)',
            tone: NmtkTone.warning,
            icon: ZetaIcons.warning_outline,
          ),
        ],
        if (state.resultMetrics.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Benchmark metrics',
            style: textStyles.titleSmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final entry in state.resultMetrics.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_metricLabels[entry.key] ?? entry.key}: '
                '${_formatMetric(entry.key, entry.value)}',
                style: textStyles.bodyMedium,
              ),
            ),
        ],
      ],
    );
  }

  String _formatMetric(String key, double value) {
    if (key.endsWith('_ms')) {
      return value.toStringAsFixed(2);
    }
    if (key == 'detection_count') {
      return value.round().toString();
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _openCompare(BuildContext context, String? resultId) async {
    final deepLink = resultId == null
        ? '/?tab=compare'
        : '/?tab=compare&resultId=$resultId';
    final opened = await openModuleInHost(
      context,
      moduleId: 'Neurobench',
      deepLink: deepLink,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open NeuroBench Compare from here. Switch to NeuroBench in the launcher nav.',
          ),
        ),
      );
    }
  }
}
