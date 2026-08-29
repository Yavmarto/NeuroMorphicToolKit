import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';

class WorkspaceComparisonPanel extends StatelessWidget {
  const WorkspaceComparisonPanel({
    super.key,
    required this.files,
    required this.activeFileId,
    required this.onActivateFile,
  });

  final List<WorkspaceFile> files;
  final String activeFileId;
  final ValueChanged<String> onActivateFile;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Center(
        child: Text(
          'Open or create a model to compare cached results.',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: Zeta.of(context).colors.mainSubtle,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final file = files[index];
        final cache = file.pipelineCache;
        final isActive = file.id == activeFileId;
        final hasPreview = cache != null;
        final hasNirArtifact = file.nirArtifactCache != null;
        final nodeCount = cache?.generateResult.network.nodes.length;
        final edgeCount = cache?.generateResult.network.edges.length;
        final nirLength = cache?.generateResult.nirCode.length;

        return Container(
          key: ValueKey<String>('workspace-comparison-row-${file.id}'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive
                ? Zeta.of(context).colors.surfaceHover
                : Zeta.of(context).colors.surfacePrimary,
            border: Border.all(
              color: isActive
                  ? Zeta.of(context).colors.mainPrimary
                  : Zeta.of(context).colors.borderDefault,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: Zeta.of(context).textStyles.titleMedium
                              .copyWith(
                                color: Zeta.of(context).colors.mainDefault,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasPreview
                              ? 'Cached preview ready'
                              : 'No cached preview yet',
                          style: Zeta.of(context).textStyles.bodySmall.copyWith(
                            color: Zeta.of(context).colors.mainSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    _StatusPill(
                      label: 'Active',
                      color: Zeta.of(context).colors.mainPrimary,
                    )
                  else
                    ZetaButton.outline(
                      onPressed: () => onActivateFile(file.id),
                      label: 'Open',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricPill(
                    label: 'Generate',
                    value: cache == null ? 'Not run' : 'Cached',
                  ),
                  _MetricPill(
                    label: 'NIR artifact',
                    value: hasNirArtifact ? 'Cached' : 'Not cached',
                  ),
                  _MetricPill(label: 'Nodes', value: _countLabel(nodeCount)),
                  _MetricPill(
                    label: 'NIR exported',
                    value: _timestampLabel(file.nirArtifactCache?.savedAt),
                  ),
                  _MetricPill(label: 'Edges', value: _countLabel(edgeCount)),
                  _MetricPill(
                    label: 'NIR size',
                    value: _nirLengthLabel(nirLength),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _countLabel(int? count) {
    if (count == null) {
      return '—';
    }
    return count.toString();
  }

  String _timestampLabel(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return '—';
    }
    return timestamp.split('T').first;
  }

  String _nirLengthLabel(int? length) {
    if (length == null) {
      return '—';
    }
    return '$length chars';
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border.all(color: Zeta.of(context).colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Zeta.of(context).textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainDefault,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Zeta.of(context).textStyles.bodySmall.copyWith(color: color),
      ),
    );
  }
}
