import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/braille_config_import.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact_saver.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';
import 'package:neuro_toolkit/features/neurocnl/services/platform_helper.dart' as platform;

typedef DownloadFileCallback =
    Future<DownloadResult> Function(ExportArtifact artifact);

typedef ExportWorkspaceSummary = ({
  String spec,
  StepStatus generateStatus,
  String activeFileName,
});

final exportWorkspaceSummaryProvider = Provider<ExportWorkspaceSummary>((ref) {
  final spec = ref.watch(specTextProvider);
  final generateStatus = ref.watch(
    pipelineProvider.select((pipeline) => pipeline.generateStatus),
  );
  final activeFileName = ref.watch(
    workspaceProvider.select(
      (workspace) => workspace.activeFile?.name ?? 'Untitled',
    ),
  );
  return (
    spec: spec,
    generateStatus: generateStatus,
    activeFileName: activeFileName,
  );
});

final workspaceRecentActivitiesProvider = Provider<List<WorkspaceActivity>>((
  ref,
) {
  return ref.watch(
    workspaceProvider.select((workspace) => workspace.recentActivities),
  );
});

class ExportMenu extends ConsumerWidget {
  const ExportMenu({
    super.key,
    this.downloadFileOverride,
    this.filePickerGatewayOverride,
    this.buttonLabel,
    this.buttonKey,
  });

  final DownloadFileCallback? downloadFileOverride;

  /// Test seam for the native file-picker used by "Import NIR..." and
  /// "Import Config...". Defaults to the real [FilePickerDialogGateway].
  final NativeFileDialogGateway? filePickerGatewayOverride;
  final String? buttonLabel;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return PopupMenuButton<String>(
      key: buttonKey,
      icon: buttonLabel == null
          ? Icon(ZetaIcons.download, color: Zeta.of(context).colors.mainPrimary)
          : null,
      tooltip: l10n.export,
      color: Zeta.of(context).colors.surfaceDefault,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Zeta.of(context).colors.borderDefault),
      ),
      onSelected: (value) => _ExportWorkflow(
        downloadFileOverride,
        filePickerGatewayOverride,
      ).runAction(context, ref, value),
      child: buttonLabel == null
          ? null
          : IgnorePointer(
              child: NmtkOutlinedButton(
                label: buttonLabel!,
                icon: ZetaIcons.download,
                onPressed: () {},
              ),
            ),
      itemBuilder: (context) => [
        _WorkspaceMenuItem(
          value: _ExportAction.importNir,
          icon: Icons
              .upload_file_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          title: 'Import NIR...',
          subtitle: 'Load .nir into Model canvas',
        ),
        _WorkspaceMenuItem(
          value: _ExportAction.cnl,
          icon: ZetaIcons.note,
          title: 'Download .cnl',
          subtitle: 'Save the active spec',
        ),
        _WorkspaceMenuItem(
          value: _ExportAction.html,
          icon: Icons.article, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          title: 'Export HTML Report',
          subtitle: 'Generate a review report',
        ),
        _WorkspaceMenuItem(
          value: _ExportAction.python,
          icon: Icons.code, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          title: 'Export Python Script',
          subtitle: 'Save generated Nengo code',
        ),
        _WorkspaceMenuItem(
          value: _ExportAction.link,
          icon: ZetaIcons.link,
          title: 'Copy Shareable Link',
          subtitle: 'Browser-only review link',
        ),
      ],
    );
  }
}

class NeurocnlExportWorkspacePanel extends ConsumerWidget {
  const NeurocnlExportWorkspacePanel({
    super.key,
    this.downloadFileOverride,
    this.filePickerGatewayOverride,
    this.scrollable = true,
  });

  final DownloadFileCallback? downloadFileOverride;

  /// Test seam for the native file-picker used by "Import NIR..." and
  /// "Import Config...". Defaults to the real [FilePickerDialogGateway].
  final NativeFileDialogGateway? filePickerGatewayOverride;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflow = _ExportWorkflow(
      downloadFileOverride,
      filePickerGatewayOverride,
    );
    final summary = ref.watch(exportWorkspaceSummaryProvider);

    final content = [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _WorkspaceStatTile(label: 'File', value: summary.activeFileName),
          _WorkspaceStatTile(
            label: 'Lines',
            value:
                '${'\n'.allMatches(summary.spec).length + (summary.spec.isEmpty ? 0 : 1)}',
          ),
          _WorkspaceStatTile(
            label: 'Generate',
            value: summary.generateStatus.name,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _WorkspaceButtonCard(
        title: 'Core',
        actions: [
          _WorkspaceActionButton(
            icon: Icons
                .upload_file_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'Import NIR...',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.importNir),
          ),
          _WorkspaceActionButton(
            icon: Icons
                .tune_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'Import Config...',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.importConfig),
          ),
          _WorkspaceActionButton(
            icon: ZetaIcons.note,
            label: 'Download .cnl',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.cnl),
          ),
          _WorkspaceActionButton(
            icon: Icons
                .article_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'HTML Report',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.html),
          ),
          _WorkspaceActionButton(
            icon: Icons
                .code_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'Python Script',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.python),
          ),
          _WorkspaceActionButton(
            icon: ZetaIcons.link,
            label: 'Share Link',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.link),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _WorkspaceButtonCard(
        title: 'Targets',
        actions: [
          _WorkspaceActionButton(
            icon: Icons
                .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'NeuroML',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.neuroml),
          ),
          _WorkspaceActionButton(
            icon: ZetaIcons.memory,
            label: 'C Header',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.cHeader),
          ),
          _WorkspaceActionButton(
            icon: Icons
                .settings_input_component_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'NengoLoihi',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.loihi),
          ),
          _WorkspaceActionButton(
            icon: Icons
                .local_fire_department_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'Lava',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.lava),
          ),
          _WorkspaceActionButton(
            icon: ZetaIcons.grid_view,
            label: 'SpiNNaker',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.spinnaker),
          ),
          _WorkspaceActionButton(
            icon:
                Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            label: 'NIR',
            onPressed: () =>
                workflow.runAction(context, ref, _ExportAction.nir),
          ),
        ],
      ),
    ];

    if (!scrollable) {
      final children = <Widget>[];
      for (var i = 0; i < content.length; i++) {
        children.add(content[i]);
        if (i < content.length - 1) {
          children.add(const SizedBox(height: 12));
        }
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: content,
    );
  }
}

class _ExportWorkflow {
  const _ExportWorkflow(
    this.downloadFileOverride, [
    this.filePickerGatewayOverride,
  ]);

  final DownloadFileCallback? downloadFileOverride;
  final NativeFileDialogGateway? filePickerGatewayOverride;

  NativeFileDialogGateway get _filePickerGateway =>
      filePickerGatewayOverride ?? const FilePickerDialogGateway();

  Future<void> runAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    if (action == _ExportAction.importNir) {
      await _importNir(context, ref);
      return;
    }

    if (action == _ExportAction.importConfig) {
      await _importConfig(context, ref);
      return;
    }

    final spec = ref.read(specTextProvider);
    if (spec.trim().isEmpty) {
      _showSnackBar(
        context,
        'Nothing to export. Write or load a spec first.',
        isError: true,
      );
      return;
    }

    final pipeline = ref.read(pipelineProvider);
    switch (action) {
      case _ExportAction.cnl:
        final artifact = ExportArtifact.text(
          filename: 'spec.cnl',
          mimeType: 'text/plain',
          content: spec,
        );
        final result = await _downloadArtifact(ref, artifact);
        if (!context.mounted) {
          return;
        }
        _handleDownloadResult(
          context,
          ref,
          result,
          kind: 'export',
          title: 'CNL export',
          successMessage: 'Saved spec.cnl',
          fallbackTitle: 'Desktop export requires browser assist',
        );
        return;
      case _ExportAction.html:
        final report = _buildHtmlReport(spec, pipeline);
        final artifact = ExportArtifact.text(
          filename: 'neurocnl_report.html',
          mimeType: 'text/html',
          content: report,
        );
        final result = await _downloadArtifact(ref, artifact);
        if (!context.mounted) {
          return;
        }
        _handleDownloadResult(
          context,
          ref,
          result,
          kind: 'export',
          title: 'HTML report export',
          successMessage: 'Saved neurocnl_report.html',
          fallbackTitle: 'Desktop export requires browser assist',
        );
        return;
      case _ExportAction.python:
        final code = pipeline.generateResult?.cnlDocument;
        if (code == null) {
          _showSnackBar(
            context,
            'Run the model first to produce compiled artifacts.',
            isError: true,
          );
          ref
              .read(workspaceProvider.notifier)
              .recordActivity(
                kind: 'export',
                title: 'Round-trip CNL export blocked',
                detail:
                    'Compiled artifacts must be available before exporting the round-trip CNL document.',
                status: 'warning',
                panelId: 'export',
              );
          return;
        }
        final artifact = ExportArtifact.text(
          filename: 'roundtrip.cnl',
          mimeType: 'text/plain',
          content: code,
        );
        final result = await _downloadArtifact(ref, artifact);
        if (!context.mounted) {
          return;
        }
        _handleDownloadResult(
          context,
          ref,
          result,
          kind: 'export',
          title: 'Round-trip CNL export',
          successMessage: 'Saved roundtrip.cnl',
          fallbackTitle: 'Desktop export requires browser assist',
        );
        return;
      case _ExportAction.link:
        final origin = platform.getOrigin();
        if (origin == null) {
          _showSnackBar(
            context,
            'Shareable links need a browser-capable surface. Use file export from this workspace instead.',
            isError: true,
          );
          ref
              .read(workspaceProvider.notifier)
              .recordActivity(
                kind: 'share',
                title: 'Share link unavailable',
                detail:
                    'This desktop session does not expose a browser origin for URL handoff.',
                status: 'warning',
                panelId: 'export',
              );
          return;
        }
        final encoded = base64Encode(utf8.encode(spec));
        final url = '$origin/#spec=$encoded';
        await platform.copyToClipboard(url);
        if (!context.mounted) {
          return;
        }
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: 'share',
              title: 'Share link copied',
              detail: 'Browser review link copied to the clipboard.',
              status: 'success',
              panelId: 'artifacts',
            );
        _showSnackBar(context, 'Shareable link copied to clipboard.');
        return;
      case _ExportAction.neuroml:
      case _ExportAction.cHeader:
      case _ExportAction.loihi:
      case _ExportAction.lava:
      case _ExportAction.spinnaker:
      case _ExportAction.nir:
        await _exportNeuromorphic(context, ref, spec, action);
        return;
      default:
        return;
    }
  }

  Future<void> _importNir(BuildContext context, WidgetRef ref) async {
    final files = await _filePickerGateway.pickFiles(
      allowMultiple: false,
      allowedExtensions: const ['nir'],
    );
    if (files == null || files.isEmpty) return;
    final f = files.first;
    await ref.read(nirImportProvider.notifier).inspectFile(f.name, f.bytes);
    unawaited(
      ref.read(canonicalDocProvider.notifier).updateFromNirFile(f.bytes),
    );
    if (!context.mounted) return;
    _showSnackBar(context, 'NIR loaded: ${f.name}');
  }

  Future<void> _importConfig(BuildContext context, WidgetRef ref) async {
    final files = await _filePickerGateway.pickFiles(
      allowMultiple: false,
      allowedExtensions: const ['json'],
    );
    if (files == null || files.isEmpty) return;
    final f = files.first;

    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(utf8.decode(f.bytes));
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object at the top level.');
      }
      decoded = parsed;
      final config = PipelineConfig.fromJson(decoded);
      ref.read(canvasProvider.notifier).updatePipeline(config);
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Invalid JSON: $e', isError: true);
      return;
    }

    // Map the reference braille hyperparameter keys (nb_hidden, alpha_r,
    // beta_r, alpha_out, beta_out, lr, slope, reg_l1, reg_l2) onto the
    // architecture-canvas and Training-DAG node parameters they correspond
    // to. This is additive to the legacy PipelineConfig import above, which
    // has no fields for these keys.
    final canvasState = ref.read(canvasProvider);
    final report = applyBrailleHyperparams(
      decoded,
      canvasState.graph,
      canvasState.pipelinePhases,
      (nodeId, params) => ref
          .read(canvasProvider.notifier)
          .updateNodeParameters(nodeId, params),
      (phase, nodeId, params) => ref
          .read(canvasProvider.notifier)
          .updatePipelineDagNodeParams(phase, nodeId, params),
    );

    if (!context.mounted) return;

    final hasHyperparamActivity =
        report.applied.isNotEmpty || report.skipped.isNotEmpty;
    final summary = hasHyperparamActivity
        ? 'Pipeline config imported from ${f.name} '
              '(${report.applied.length} hyperparameter'
              '${report.applied.length == 1 ? '' : 's'} applied'
              '${report.skipped.isEmpty ? '' : ', ${report.skipped.length} skipped'})'
        : 'Pipeline config imported from ${f.name}';

    if (hasHyperparamActivity) {
      ref
          .read(workspaceProvider.notifier)
          .recordActivity(
            kind: 'import',
            title: 'Hyperparameter import from ${f.name}',
            detail: [
              if (report.applied.isNotEmpty)
                'Applied: ${report.applied.join('; ')}',
              if (report.skipped.isNotEmpty)
                'Skipped: ${report.skipped.join('; ')}',
            ].join('\n'),
            status: report.skipped.isEmpty ? 'success' : 'warning',
            panelId: 'artifacts',
          );
    }

    _showSnackBar(context, summary);
  }

  String _buildHtmlReport(String spec, PipelineState pipeline) {
    final specEscaped = _escapeHtml(spec);

    final validationHtml = StringBuffer();
    final v = pipeline.validateResult;
    if (v != null) {
      final statusColor = v.overall ? '#1c7c54' : '#a61b1b';
      final statusText = v.overall ? 'PASSED' : 'FAILED';
      validationHtml.write(
        '<h2>Validation <span style="color:$statusColor">$statusText</span></h2>\n',
      );
      validationHtml.write(
        '<h3>Layer 1: Biophysical Invariants</h3>\n'
        '<table><tr><th>Invariant</th><th>Description</th><th>Result</th></tr>\n',
      );
      for (final inv in v.layer1.passed) {
        validationHtml.write(
          '<tr><td>${_escapeHtml(inv.name)}</td>'
          '<td>${_escapeHtml(inv.description)}</td>'
          '<td style="color:#1c7c54">\u2713</td></tr>\n',
        );
      }
      for (final inv in v.layer1.failed) {
        validationHtml.write(
          '<tr><td>${_escapeHtml(inv.name)}</td>'
          '<td>${_escapeHtml(inv.description)}</td>'
          '<td style="color:#a61b1b">\u2717</td></tr>\n',
        );
      }
      validationHtml.write('</table>\n');
    }

    final networkHtml = StringBuffer();
    final net = pipeline.generateResult?.network;
    if (net != null) {
      networkHtml.write('<h2>Network Topology</h2>\n');
      networkHtml.write(
        '<table><tr><th>ID</th><th>Type</th><th>Label</th></tr>\n',
      );
      for (final node in net.nodes) {
        networkHtml.write(
          '<tr><td>${_escapeHtml(node.id)}</td>'
          '<td>${_escapeHtml(node.type)}</td>'
          '<td>${_escapeHtml(node.label)}</td></tr>\n',
        );
      }
      networkHtml.write('</table>\n');
    }

    final previewHtml = StringBuffer();
    final generated = pipeline.generateResult;
    if (generated != null) {
      previewHtml.write('<h2>Compiled Preview</h2>\n<table>\n');
      final stats = <String, dynamic>{
        'Nodes': generated.network.nodes.length,
        'Edges': generated.network.edges.length,
        'NIR length': generated.nirCode.length,
      };
      for (final entry in stats.entries) {
        previewHtml.write(
          '<tr><td><strong>${entry.key}</strong></td><td>${entry.value}</td></tr>\n',
        );
      }
      previewHtml.write('</table>\n');
      previewHtml.write('<h2>NIR Preview</h2>\n');
      previewHtml.write('<pre>${_escapeHtml(generated.nirCode)}</pre>\n');
    }

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>neurocnl Studio Report</title>
<style>
body { font-family: 'SF Pro Display', 'Segoe UI', sans-serif; max-width: 960px; margin: 32px auto; padding: 0 20px 40px; background: #f3efe7; color: #14213d; }
h1 { color: #0b3c49; border-bottom: 3px solid #e07a5f; padding-bottom: 12px; }
h2 { color: #0b3c49; margin-top: 28px; }
pre { background: #fffdf8; padding: 16px; border-radius: 12px; border: 1px solid #d8d2c4; overflow-x: auto; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; background: #fffdf8; }
th, td { text-align: left; padding: 8px 12px; border: 1px solid #d8d2c4; }
th { background: #d7e3d4; }
</style>
</head>
<body>
<h1>neurocnl Desktop Export Report</h1>
<h2>CNL Specification</h2>
<pre>$specEscaped</pre>
$validationHtml
$networkHtml
$previewHtml
</body>
</html>''';
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  Future<void> _exportNeuromorphic(
    BuildContext context,
    WidgetRef ref,
    String spec,
    String format,
  ) async {
    final client = ref.read(apiClientProvider);
    try {
      final cachedNirArtifact = ref
          .read(workspaceProvider)
          .activeFile
          ?.nirArtifactCache;
      final artifact = format == _ExportAction.nir
          ? _nirArtifactFromCache(cachedNirArtifact, spec) ??
                await client.exportNirArtifact(spec)
          : ExportArtifact.text(
              filename:
                  'network.${<String, String>{_ExportAction.neuroml: 'nml', _ExportAction.cHeader: 'h', _ExportAction.loihi: 'py', _ExportAction.lava: 'py', _ExportAction.spinnaker: 'py'}[format]!}',
              mimeType: 'text/plain',
              content: await client.export(spec, format: format),
            );
      if (format == _ExportAction.nir &&
          _nirArtifactFromCache(cachedNirArtifact, spec) == null) {
        ref
            .read(workspaceProvider.notifier)
            .saveNirArtifactForActiveFile(artifact);
      }
      final result = await _downloadArtifact(ref, artifact);
      if (!context.mounted) {
        return;
      }
      _handleDownloadResult(
        context,
        ref,
        result,
        kind: 'target_export',
        title: '${format.toUpperCase()} export',
        successMessage: 'Saved ${artifact.filename}',
        fallbackTitle: 'Desktop export requires browser assist',
      );
    } catch (error) {
      ref
          .read(workspaceProvider.notifier)
          .recordActivity(
            kind: 'target_export',
            title: '${format.toUpperCase()} export failed',
            detail: error.toString(),
            status: 'error',
            panelId: 'artifacts',
          );
      _showSnackBar(context, 'Export failed: $error', isError: true);
    }
  }

  ExportArtifact? _nirArtifactFromCache(
    WorkspaceNirArtifactCache? cache,
    String spec,
  ) {
    if (cache == null || !cache.isValidForContent(spec)) {
      return null;
    }
    return ExportArtifact.binary(
      filename: cache.filename,
      mimeType: cache.mimeType,
      payload: cache.payloadBytes,
    );
  }

  Future<DownloadResult> _downloadArtifact(
    WidgetRef ref,
    ExportArtifact artifact,
  ) async {
    final override = downloadFileOverride;
    if (override != null) {
      return override(artifact);
    }
    return saveExportArtifact(ref.read(nativeFileAdapterProvider), artifact);
  }

  void _handleDownloadResult(
    BuildContext context,
    WidgetRef ref,
    DownloadResult result, {
    required String kind,
    required String title,
    required String successMessage,
    required String fallbackTitle,
  }) {
    switch (result.status) {
      case DownloadStatus.downloaded:
        final detail = result.path == null
            ? successMessage
            : 'Saved to ${result.path}';
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: kind,
              title: title,
              detail: detail,
              status: 'success',
              panelId: 'artifacts',
            );
        _showSnackBar(context, detail);
        return;
      case DownloadStatus.fallback:
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: kind,
              title: '$title needs browser assist',
              detail:
                  result.message ??
                  'Use a browser-capable suite workspace to complete the download.',
              status: 'warning',
              panelId: 'artifacts',
            );
        _showFallbackDialog(
          context,
          title: fallbackTitle,
          detail:
              result.message ??
              'This desktop session kept the export inside the workspace. Use a browser-capable suite workspace if you need native browser download handling.',
        );
        return;
      case DownloadStatus.failed:
        ref
            .read(workspaceProvider.notifier)
            .recordActivity(
              kind: kind,
              title: '$title failed',
              detail:
                  result.message ??
                  'Export failed before the download started.',
              status: 'error',
              panelId: 'artifacts',
            );
        _showSnackBar(
          context,
          result.message ?? 'Export failed before the download could start.',
          isError: true,
        );
        return;
    }
  }

  void _showFallbackDialog(
    BuildContext context, {
    required String title,
    required String detail,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'OK',
          ),
        ],
      ),
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      isError
          ? NmtkSnackBars.error(context, message)
          : NmtkSnackBars.success(context, message),
    );
  }
}

class _WorkspaceMenuItem extends PopupMenuItem<String> {
  _WorkspaceMenuItem({
    required super.value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) : super(
         child: _MenuRow(icon: icon, title: title, subtitle: subtitle),
       );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Zeta.of(context).colors.mainPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainDefault,
                  fontSize: 13,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainSubtle,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkspaceButtonCard extends StatelessWidget {
  const _WorkspaceButtonCard({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // zeta-card-reduction Task 10: NeurocnlSectionCard → NmtkSection.
    return NmtkSection(
      title: title,
      child: Wrap(spacing: 12, runSpacing: 12, children: actions),
    );
  }
}

class _WorkspaceActionButton extends StatelessWidget {
  const _WorkspaceActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: NmtkOutlinedButton(onPressed: onPressed, icon: icon, label: label),
    );
  }
}

class _WorkspaceStatTile extends StatelessWidget {
  const _WorkspaceStatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfaceDefault,
        border: Border.all(color: Zeta.of(context).colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainDefault,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class NeurocnlArtifactsPanel extends ConsumerWidget {
  const NeurocnlArtifactsPanel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(workspaceRecentActivitiesProvider);
    if (activities.isEmpty) {
      return compact
          ? const NmtkSection(
              title: 'Recent Activity',
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'No recent export or handoff activity yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No export or handoff artifacts yet. Use the deploy surface to populate this history.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
    }

    final list = ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: activities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final activity = activities[index];
        // zeta-card-reduction Task 10: NeurocnlSectionCard → NmtkSection.
        // The legacy `tone: _toneForStatus(...)` framing is dropped —
        // status is already conveyed by the leading icon's color (via
        // `_colorForStatus`), so removing the section's tone-based frame
        // does not lose information. The unused `_toneForStatus` helper
        // was deleted alongside this migration.
        return NmtkSection(
          title: activity.title,
          leading: Icon(
            _iconForKind(activity.kind),
            color: _colorForStatus(context, activity.status),
          ),
          trailing: Text(
            _relativeTimestamp(activity.timestamp),
            style: Zeta.of(context).textStyles.bodyMedium.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
              fontSize: 11,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    activity.kind.replaceAll('_', ' ').toUpperCase(),
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      color: Zeta.of(context).colors.mainSubtle,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (activity.panelId != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Panel: ${activity.panelId}',
                      style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                        color: Zeta.of(context).colors.mainSubtle,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                activity.detail,
                style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                  color: Zeta.of(context).colors.mainDefault,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!compact) {
      return list;
    }

    return NmtkSection(
      title: 'Recent Activity',
      child: SizedBox(height: 320, child: list),
    );
  }

  IconData _iconForKind(String kind) {
    return switch (kind) {
      'handoff' =>
        Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      'share' => ZetaIcons.link,
      _ =>
        Icons.inventory_2_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    };
  }

  Color _colorForStatus(BuildContext context, String status) {
    return switch (status) {
      'success' => Zeta.of(context).colors.surfacePositive,
      'warning' => Zeta.of(context).colors.surfaceWarning,
      'error' => Zeta.of(context).colors.surfaceNegative,
      _ => Zeta.of(context).colors.surfaceInfo,
    };
  }

  String _relativeTimestamp(String timestamp) {
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      return timestamp;
    }
    final age = DateTime.now().difference(parsed);
    if (age.inMinutes < 1) {
      return 'just now';
    }
    if (age.inHours < 1) {
      return '${age.inMinutes}m ago';
    }
    if (age.inDays < 1) {
      return '${age.inHours}h ago';
    }
    return '${age.inDays}d ago';
  }
}

abstract final class _ExportAction {
  static const String importNir = 'import_nir';
  static const String importConfig = 'import_config';
  static const String cnl = 'cnl';
  static const String html = 'html';
  static const String python = 'python';
  static const String neuroml = 'neuroml';
  static const String cHeader = 'c_header';
  static const String loihi = 'loihi';
  static const String lava = 'lava';
  static const String spinnaker = 'spinnaker';
  static const String nir = 'nir';
  static const String link = 'link';
}
