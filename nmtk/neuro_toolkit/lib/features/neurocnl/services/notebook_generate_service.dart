import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/pipeline_cnl_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/dataset_generation_preparer.dart';
import 'package:neuro_toolkit/features/neurocnl/services/open_external_url.dart';

/// Service that reads both halves of [CanvasState] and calls
/// `POST /api/notebook/generate-v2` to produce a Jupyter notebook.
///
/// This is the only place where architecture (CNL from [specTextProvider])
/// and pipeline config ([PipelineConfig] from [canvasProvider]) are joined.
/// They are kept separate in state to enforce the tab-discriminator rule:
///   Architecture tab → CNL spec
///   Pipeline tab     → training_config.json (PipelineConfig.toJson())
abstract final class NotebookGenerateService {
  static const systemHealthUri = 'nmtk://system-health';

  static bool shouldOfferSystemHealth(Object error) =>
      error is DatasetPreparationException || error is ApiException;

  static String preferredSpecForNotebook({
    required String specText,
    required String canonicalSpecText,
  }) {
    return canonicalSpecText.trim().isNotEmpty ? canonicalSpecText : specText;
  }

  static String importIdForNotebook({
    required NirImportState nirImportState,
    required String retainedFileBackedImportId,
  }) {
    if (nirImportState is NirImportLoaded &&
        nirImportState.importId.isNotEmpty) {
      return nirImportState.importId;
    }
    return retainedFileBackedImportId;
  }

  /// Generate a notebook and open it in JupyterLab (or show an error snackbar).
  static Future<void> generate(WidgetRef ref, BuildContext context) async {
    final spec = preferredSpecForNotebook(
      specText: ref.read(specTextProvider),
      canonicalSpecText: ref.read(canonicalDocProvider).value?.cnlText ?? '',
    );
    final canvas = ref.read(canvasProvider);
    final pipeline = canvas.pipeline;
    final pipelinePhases = canvas.pipelinePhases;
    final workspace = ref.read(workspaceProvider);

    if (spec.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No architecture to generate from.\n'
            'Define and validate a network on the Architecture tab first.',
          ),
        ),
      );
      return;
    }

    final ApiClient api = ref.read(apiClientProvider);
    final nirImportState = ref.read(nirImportProvider);
    final importId = importIdForNotebook(
      nirImportState: nirImportState,
      retainedFileBackedImportId: ref.read(latestFileBackedNirImportIdProvider),
    );
    try {
      final preparation = await DatasetGenerationPreparer(
        apiClient: api,
      ).prepare(pipelinePhases);
      applyDatasetUploadRemaps(ref, preparation.uploads);
      final result = await api.generateNotebookV2(
        spec: spec,
        pipelineConfig: <String, dynamic>{
          ...pipeline.toJson(),
          'framework':
              workspace.selectedPlatforms.firstOrNull ?? 'snntorch_sim',
          if (workspace.selectedDataset != null)
            'dataset': workspace.selectedDataset!,
        },
        pipelinePhases: preparation.phases,
        pipelineCnl: ref.read(pipelineCnlProvider).value,
        workspacePath: _slugify(workspace.workspaceName),
        importId: importId.isNotEmpty ? importId : null,
      );

      final url = resolveJupyterUrl(
        jupyterUrl: result.jupyterUrl,
        workspaceFolder: result.workspaceFolder,
        baseUrl: api.baseUrl,
      );

      unawaited(
        openExternalUrl(
          passiveJupyterFolderUrl(
            targetUrl: url,
            workspaceFolder: result.workspaceFolder,
            cacheBust: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(
        context,
        _describeError(e),
        showSystemHealth: shouldOfferSystemHealth(e),
      );
    }
  }

  static String _slugify(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static String jupyterFolderUrl(String workspaceFolder, String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.isNotEmpty == true
        ? Uri.parse(baseUrl).host
        : 'localhost';
    return workspaceFolder.isNotEmpty
        ? 'http://$host:8008/lab/tree/$workspaceFolder/'
        : 'http://$host:8008/lab';
  }

  /// Prefers the backend-supplied [jupyterUrl] (set via JUPYTER_PUBLIC_URL —
  /// how an operator points remote/mobile clients at a reachable address:
  /// a different port, HTTPS, a reverse-proxy path). Only derives a fallback
  /// from [baseUrl] when the backend left it empty, since that fallback
  /// assumes plain http on port 8008, which isn't guaranteed reachable from
  /// a second device.
  static String resolveJupyterUrl({
    required String jupyterUrl,
    required String workspaceFolder,
    required String baseUrl,
  }) {
    return jupyterUrl.isNotEmpty
        ? jupyterUrl
        : jupyterFolderUrl(workspaceFolder, baseUrl);
  }

  /// Opens JupyterLab at a clean folder view instead of restoring the default
  /// workspace's previously-open notebook tabs. This keeps merely entering the
  /// Notebook view passive: Jupyter does not attach a kernel until the user
  /// explicitly opens a notebook from the file browser.
  static String passiveJupyterFolderUrl({
    required String targetUrl,
    required String workspaceFolder,
    required int cacheBust,
  }) {
    final uri = Uri.parse(targetUrl);
    final treeIndex = uri.path.indexOf('/tree/');
    final labRoot = treeIndex >= 0
        ? uri.path.substring(0, treeIndex)
        : uri.path.replaceFirst(RegExp(r'/+$'), '');
    final normalizedFolder = workspaceFolder
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .join('/');
    final workspaceName = _slugify(
      normalizedFolder.split('/').firstOrNull ?? 'pipeline',
    );
    final folderSuffix = normalizedFolder.isEmpty ? '' : '$normalizedFolder/';
    final path =
        '$labRoot/workspaces/nmtk-${workspaceName.isEmpty ? 'pipeline' : workspaceName}'
        '/tree/$folderSuffix';
    return uri
        .replace(
          path: path,
          queryParameters: <String, String>{
            ...uri.queryParameters,
            'reset': '',
            'ts': '$cacheBust',
          },
          fragment: null,
        )
        .toString();
  }

  static String _describeError(Object e) {
    if (e is ApiException) {
      return 'Notebook generation failed (${e.statusCode}): ${e.body}';
    }
    return 'Notebook generation failed: $e';
  }

  static void _showError(
    BuildContext context,
    String message, {
    bool showSystemHealth = false,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: showSystemHealth
            ? SnackBarAction(
                label: 'System Health',
                onPressed: () {
                  openExternalUrl(systemHealthUri);
                },
              )
            : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
