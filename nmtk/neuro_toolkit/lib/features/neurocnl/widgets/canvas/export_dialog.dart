import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_export_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact_saver.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/backend_support_banner.dart';

class ExportDialog extends ConsumerStatefulWidget {
  const ExportDialog({super.key, required this.graphJson});

  final Map<String, dynamic> graphJson;

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  String _selectedFormat = 'cnl';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(exportProvider.notifier)
          .preflight(_selectedFormat, widget.graphJson);
    });
  }

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(exportProvider);
    return AlertDialog(
      insetPadding: NmtkDialogSurface.insetPadding(context),
      title: const Text('Export Design'),
      actions: [
        ZetaButton.outline(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Close',
        ),
        ZetaButton(
          onPressed:
              exportState.isLoading ||
                  exportState.backendSupport?.verdict == 'unsupported'
              ? null
              : () async {
                  await ref
                      .read(exportProvider.notifier)
                      .export(
                        _selectedFormat,
                        widget.graphJson,
                        allowApproximate:
                            exportState.requiresApproximateConfirmation,
                      );
                  final artifact = ref.read(exportProvider).artifact;
                  if (!context.mounted || artifact == null) {
                    return;
                  }
                  final result = await saveExportArtifact(
                    ref.read(nativeFileAdapterProvider),
                    artifact,
                  );
                  if (!context.mounted) {
                    return;
                  }
                  if (result.status == DownloadStatus.downloaded) {
                    final detail = result.path == null
                        ? 'Saved ${artifact.filename}'
                        : 'Saved to ${result.path}';
                    NmtkToasts.success(context, detail);
                  } else if (result.status == DownloadStatus.fallback) {
                    NmtkToasts.error(
                      context,
                      result.message ?? 'Export needs browser assist.',
                    );
                  } else {
                    NmtkToasts.error(
                      context,
                      result.message ?? 'Binary export failed.',
                    );
                  }
                },
          label: exportState.requiresApproximateConfirmation
              ? 'Export Anyway'
              : 'Export',
        ),
      ],
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select export format:'),
            const SizedBox(height: 10),
            DropdownButton<String>(
              value: _selectedFormat,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'cnl', child: Text('Raw CNL (.cnl)')),
                DropdownMenuItem(
                  value: 'python',
                  child: Text('Nengo Python (.py)'),
                ),
                DropdownMenuItem(value: 'c', child: Text('C Header (.h)')),
                DropdownMenuItem(
                  value: 'neuroml',
                  child: Text('NeuroML (.xml)'),
                ),
                DropdownMenuItem(value: 'svg', child: Text('Diagram (SVG)')),
                DropdownMenuItem(value: 'nir', child: Text('NIR (.nir)')),
                DropdownMenuItem(
                  value: 'mlir',
                  child: Text('SNN-MLIR (.mlir)'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedFormat = value);
                  ref.read(exportProvider.notifier).reset();
                  ref
                      .read(exportProvider.notifier)
                      .preflight(value, widget.graphJson);
                }
              },
            ),
            const SizedBox(height: 16),
            if (exportState.backendSupport != null)
              NmtkBackendSupportBanner(
                verdict: exportState.backendSupport!.verdict,
                backend: exportState.backendSupport!.backend,
                warnings: exportState.backendSupport!.warnings,
                title: 'Export Target Fidelity',
                compact: true,
              ),
            const SizedBox(height: 24),
            if (exportState.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (exportState.error != null)
              Text(
                'Error: ${exportState.error}',
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainNegative,
                ),
              )
            else if (exportState.data != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exported ${_selectedFormat.toUpperCase()}:',
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Zeta.of(context).colors.surfaceHover,
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Text(
                        exportState.data!,
                        style: Zeta.of(context).textStyles.bodySmall.copyWith(
                          fontFamily: NmtkFontFamilies.monospace,
                          package: NmtkFontFamilies.package,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
