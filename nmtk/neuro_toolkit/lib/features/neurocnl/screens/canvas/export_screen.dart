import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_export_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact_saver.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';
import 'package:neuro_toolkit/features/neurocnl/services/notebook_generate_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/backend_support_banner.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String _selectedFormat = 'cnl';

  bool get _isV2Format =>
      _selectedFormat == 'notebook_v2' || _selectedFormat == 'python_v2';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final graphJson = ref.read(canvasProvider).graph.toJson();
      ref.read(exportProvider.notifier).preflight(_selectedFormat, graphJson);
    });
  }

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(exportProvider);
    final canvasState = ref.watch(canvasProvider);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            SizedBox(
              width: 320,
              // Allowed: single-topic surface
              child: NmtkSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Export Design',
                      style: Zeta.of(context).textStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select export format:'),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      key: const Key('export-format-dropdown'),
                      value: _selectedFormat,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: 'cnl',
                          child: Text('Raw CNL (.cnl)'),
                        ),
                        DropdownMenuItem(
                          value: 'python',
                          child: Text('Nengo Python (.py)'),
                        ),
                        DropdownMenuItem(
                          value: 'c',
                          child: Text('C Header (.h)'),
                        ),
                        DropdownMenuItem(
                          value: 'neuroml',
                          child: Text('NeuroML (.xml)'),
                        ),
                        DropdownMenuItem(
                          value: 'svg',
                          child: Text('Diagram (SVG)'),
                        ),
                        DropdownMenuItem(
                          value: 'nir',
                          child: Text('NIR (.nir)'),
                        ),
                        DropdownMenuItem(
                          value: 'notebook_v2',
                          child: Text('Jupyter Notebook (Pipeline-aware)'),
                        ),
                        DropdownMenuItem(
                          value: 'python_v2',
                          child: Text('Python Script (Pipeline-aware)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedFormat = value);
                          ref.read(exportProvider.notifier).reset();
                          if (value != 'notebook_v2' && value != 'python_v2') {
                            ref
                                .read(exportProvider.notifier)
                                .preflight(value, canvasState.graph.toJson());
                          }
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
                    ZetaButton(
                      key: const Key('export-submit-button'),
                      onPressed: _isV2Format
                          ? () => NotebookGenerateService.generate(ref, context)
                          : exportState.isLoading ||
                                exportState.backendSupport?.verdict ==
                                    'unsupported'
                          ? null
                          : () async {
                              await ref
                                  .read(exportProvider.notifier)
                                  .export(
                                    _selectedFormat,
                                    canvasState.graph.toJson(),
                                    allowApproximate: exportState
                                        .requiresApproximateConfirmation,
                                  );
                              final artifact = ref
                                  .read(exportProvider)
                                  .artifact;
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
                              } else if (result.status ==
                                  DownloadStatus.fallback) {
                                NmtkToasts.error(
                                  context,
                                  result.message ??
                                      'Export needs browser assist.',
                                );
                              } else {
                                NmtkToasts.error(
                                  context,
                                  result.message ?? 'Binary export failed.',
                                );
                              }
                            },
                      label: _isV2Format
                          ? 'Generate Notebook'
                          : exportState.isLoading
                          ? 'Exporting…'
                          : exportState.requiresApproximateConfirmation
                          ? 'Export Anyway'
                          : 'Export',
                      leadingIcon: _isV2Format
                          ? ZetaIcons.open_in_new_window
                          : exportState.isLoading
                          ? null
                          : ZetaIcons.ios_share,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              // Allowed: single-topic surface
              child: NmtkSurfaceCard(
                expandChild: true,
                child: exportState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : exportState.error != null
                    ? Center(
                        child: Text(
                          'Error: ${exportState.error}',
                          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      )
                    : exportState.data != null
                    ? _buildExportResult(exportState.data!, exportState.format!)
                    : const Center(
                        child: Text(
                          'Select a format to review fidelity, then export.',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportResult(String data, String format) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Exported ${format.toUpperCase()}:',
              key: const Key('export-result-title'),
              style: Zeta.of(context).textStyles.labelMedium.copyWith(fontWeight: FontWeight.bold),
            ),
            ZetaButton.outline(
              onPressed: () {
                NmtkToasts.success(context, 'Copied to clipboard!');
              },
              leadingIcon:
                  Icons.copy, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              label: 'Copy',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SingleChildScrollView(
              child: Text(
                data,
                // ZETA-MIGRATION-EXEMPT: exported payload is monospace (JetBrains
                // Mono) — Zeta (IBM Plex Sans) has no monospace text style.
                style: const TextStyle(
                  fontFamily: NmtkFontFamilies.monospace,
                  package: NmtkFontFamilies.package,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
