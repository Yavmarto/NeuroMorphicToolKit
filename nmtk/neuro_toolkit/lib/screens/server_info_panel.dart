import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/system_resources.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/system_resources_notifier.dart';

/// Live CPU, memory, GPU, and host details for the connected backend.
class ServerInfoPanel extends ConsumerWidget {
  const ServerInfoPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);
    final resources = ref.watch(systemResourcesProvider);
    final backendVersion = ref.watch(backendVersionProvider).value;

    return NmtkSectionCard(
      key: const Key('server-info-panel'),
      title: 'Server info',
      subtitle: backendVersion == null ? null : 'Backend v$backendVersion',
      child: _buildBody(context, tokens, resources),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NmtkShellTokens tokens,
    SystemResourcesState resources,
  ) {
    if (resources.isLoading && resources.snapshot == null) {
      return const Row(
        children: [
          ZetaProgressCircle(size: ZetaCircleSizes.s),
          SizedBox(width: 12),
          Expanded(child: Text('Loading server stats…')),
        ],
      );
    }

    final snapshot = resources.snapshot;
    if (snapshot == null) {
      return Text(
        'Server stats are not available right now.',
        style: Zeta.of(context).textStyles.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _usageRow(
          context,
          label: 'CPU',
          percent: snapshot.cpuPercent,
          detail:
              '${snapshot.cpuPercent.toStringAsFixed(0)}% · '
              '${snapshot.cpuCores} cores',
        ),
        SizedBox(height: tokens.compactGap),
        _usageRow(
          context,
          label: 'Memory',
          percent: snapshot.memoryPercent,
          detail:
              '${formatResourceBytes(snapshot.memoryUsed)} / '
              '${formatResourceBytes(snapshot.memoryTotal)}',
        ),
        if (snapshot.hasGpu) ...[
          SizedBox(height: tokens.compactGap),
          for (final gpu in snapshot.gpus!) ...[
            _usageRow(
              context,
              label: gpu.name,
              percent: gpu.memoryTotal == 0
                  ? gpu.utilization.toDouble()
                  : (gpu.memoryUsed / gpu.memoryTotal) * 100,
              detail:
                  '${gpu.utilization}% util · '
                  '${formatResourceBytes(gpu.memoryUsed)} / '
                  '${formatResourceBytes(gpu.memoryTotal)}',
            ),
            if (gpu != snapshot.gpus!.last) SizedBox(height: tokens.compactGap),
          ],
        ],
        SizedBox(height: tokens.sectionGap),
        NmtkKeyValueRow(label: 'Hostname', value: snapshot.hostname),
        NmtkKeyValueRow(label: 'OS', value: snapshot.platform),
        NmtkKeyValueRow(
          label: 'Uptime',
          value: formatResourceUptime(snapshot.uptimeSeconds),
        ),
      ],
    );
  }

  Widget _usageRow(
    BuildContext context, {
    required String label,
    required double percent,
    required String detail,
  }) {
    final clamped = percent.clamp(0, 100) / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Zeta.of(
                  context,
                ).textStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              detail,
              style: Zeta.of(context).textStyles.bodySmall.copyWith(
                color: Zeta.of(context).colors.mainSubtle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ZetaProgressBar.standard(progress: clamped, isThin: true),
      ],
    );
  }
}
