import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/hub_preview.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hub_preview_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/hub/publish_results_dialog/publish_result_summary.dart';

class PublishResultsDialog extends ConsumerStatefulWidget {
  const PublishResultsDialog({super.key});

  @override
  ConsumerState<PublishResultsDialog> createState() =>
      _PublishResultsDialogState();
}

class _PublishResultsDialogState extends ConsumerState<PublishResultsDialog> {
  bool _public = true;
  bool _isPublishing = false;

  // NeuroHub's real publish endpoint isn't wired up yet, so this mocks the
  // publish flow locally: it drops the workspace straight into the current
  // user's profile (`hubArtefactPreviewsProvider`) instead of calling the
  // (currently broken) network client.
  Future<void> _publish() async {
    final workspace = ref.read(workspaceProvider);
    final pipeline = ref.read(pipelineProvider);
    final target = workspace.selectedDeployTarget;
    setState(() => _isPublishing = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final fields = <HubDetailField>[
      if (target.isNotEmpty)
        HubDetailField(label: 'Target', value: targetLabel(target)),
    ];
    final simulation = pipeline.simulateResult;
    if (simulation != null) {
      fields.add(
        HubDetailField(
          label: 'Duration',
          value:
              '${simulation.duration.toStringAsFixed(2)}s over '
              '${simulation.timesteps} steps',
        ),
      );
    }

    ref
        .read(hubArtefactPreviewsProvider.notifier)
        .addWorkspace(
          title: workspace.workspaceName,
          description: 'Published from CNL Studio (${targetLabel(target)}).',
          visibility: _public ? HubVisibility.public : HubVisibility.private,
          tags: <String>['studio-result', _public ? 'public' : 'private'],
          detail: HubArtefactDetail(
            overview:
                'Workspace published from CNL Studio\'s Review step, with its '
                'latest run result.',
            fields: fields,
          ),
        );

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Published to your profile.'),
        showCloseIcon: true,
      ),
    );
    setState(() => _isPublishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: NmtkDesignTokens.dialogShape),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Publish to NeuroHub',
                      style: textStyles.titleLarge.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  NmtkOutlinedButton(
                    label: 'Close',
                    icon: ZetaIcons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: 16),
              const Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        child: PublishResultSummary(),
                      ),
                    ),
                    SizedBox(width: 24),
                    Expanded(flex: 5, child: WorkspaceCanvasPreview()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ZetaCheckbox(
                    value: _public,
                    label: 'Public',
                    onChanged: _isPublishing
                        ? null
                        : (value) => setState(() => _public = value),
                  ),
                  const SizedBox(width: 16),
                  NmtkPrimaryButton(
                    label: _isPublishing ? 'Publishing…' : 'Publish',
                    icon: ZetaIcons.cloud_upload,
                    onPressed: _isPublishing ? null : _publish,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
