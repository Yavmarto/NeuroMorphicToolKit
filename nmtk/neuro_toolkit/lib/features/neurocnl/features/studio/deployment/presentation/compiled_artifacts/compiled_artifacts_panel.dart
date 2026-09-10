import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' hide AppTheme;

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/services/deploy_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact_saver.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/network_graph_view.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/compiled_artifacts/compiled_artifacts_header.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/compiled_artifacts/generated_code_pane.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/presentation/compiled_artifacts/step_error_pane.dart';

/// Deployment panel for generated CNL and NIR artifacts.

class CompiledArtifactsPanel extends ConsumerWidget {
  const CompiledArtifactsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.watch(pipelineProvider);
    final result = pipeline.generateResult;
    final spec = ref.watch(specTextProvider);

    if (pipeline.generateStatus == StepStatus.error &&
        pipeline.errorMessage != null) {
      final error = extractPipelineStepError(
        pipeline.errorMessage,
        stepLabel: 'Compile',
      );
      return StepErrorPane(
        title: error.title,
        message: error.message,
        hint: error.hint,
      );
    }

    NetworkNode? ensembleNode;
    if (result != null) {
      for (final n in result.network.nodes) {
        if (n.type == 'ensemble') {
          ensembleNode = n;
          break;
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = constraints.maxWidth >= 980 ? 16.0 : 12.0;
        final graphPane = Container(
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: const NetworkGraphView(),
        );
        final codePane = GeneratedCodePane(
          cnlDocument: result?.cnlDocument,
          nirCode: result?.nirCode,
          onDownloadNir: result == null || spec.trim().isEmpty
              ? null
              : () async {
                  final cachedNirArtifact = ref
                      .read(workspaceProvider)
                      .activeFile
                      ?.nirArtifactCache;
                  final artifact =
                      cachedNirArtifact != null &&
                          cachedNirArtifact.isValidForContent(spec)
                      ? ExportArtifact.binary(
                          filename: cachedNirArtifact.filename,
                          mimeType: cachedNirArtifact.mimeType,
                          payload: cachedNirArtifact.payloadBytes,
                        )
                      : await ref
                            .read(apiClientProvider)
                            .exportNirArtifact(spec);
                  if (cachedNirArtifact == null ||
                      !cachedNirArtifact.isValidForContent(spec)) {
                    ref
                        .read(workspaceProvider.notifier)
                        .saveNirArtifactForActiveFile(artifact);
                  }
                  final downloadResult = await saveExportArtifact(
                    ref.read(nativeFileAdapterProvider),
                    artifact,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  if (downloadResult.status == DownloadStatus.downloaded) {
                    final detail = downloadResult.path == null
                        ? 'Saved ${artifact.filename}'
                        : 'Saved to ${downloadResult.path}';
                    ref
                        .read(workspaceProvider.notifier)
                        .recordActivity(
                          kind: 'export',
                          title: 'Deploy compiled artifacts NIR export',
                          detail: detail,
                          status: 'success',
                          panelId: 'deploy',
                        );
                    NmtkSnackBars.success(context, detail);
                  } else if (downloadResult.status == DownloadStatus.fallback) {
                    ref
                        .read(workspaceProvider.notifier)
                        .recordActivity(
                          kind: 'export',
                          title:
                              'Deploy compiled artifacts NIR export needs browser assist',
                          detail:
                              downloadResult.message ??
                              'Use a browser-capable workspace to complete the download.',
                          status: 'warning',
                          panelId: 'deploy',
                        );
                    NmtkSnackBars.error(
                        context,
                        downloadResult.message ??
                            'Use a browser-capable workspace to complete the download.',
                      );
                  } else {
                    ref
                        .read(workspaceProvider.notifier)
                        .recordActivity(
                          kind: 'export',
                          title: 'Deploy compiled artifacts NIR export failed',
                          detail:
                              downloadResult.message ?? 'Binary export failed.',
                          status: 'error',
                          panelId: 'deploy',
                        );
                    NmtkSnackBars.error(
                        context,
                        downloadResult.message ?? 'Binary export failed.',
                      );
                  }
                },
        );

        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CompiledArtifactsHeader(
                result: result,
                ensembleNode: ensembleNode,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: constraints.maxWidth >= 1080
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 11, child: graphPane),
                          const SizedBox(width: 12),
                          Expanded(flex: 9, child: codePane),
                        ],
                      )
                    : codePane,
              ),
            ],
          ),
        );
      },
    );
  }
}
