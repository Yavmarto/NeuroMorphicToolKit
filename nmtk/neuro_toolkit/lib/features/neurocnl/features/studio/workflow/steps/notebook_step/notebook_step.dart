import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/config/platform_capabilities.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/notebook_meta_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/step_unlock_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/dataset_generation_preparer.dart';
import 'package:neuro_toolkit/features/neurocnl/services/notebook_generate_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/open_external_url.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart';

class NotebookStep extends ConsumerStatefulWidget {
  const NotebookStep({super.key});

  @override
  ConsumerState<NotebookStep> createState() => _NotebookStepState();
}

class _NotebookStepState extends ConsumerState<NotebookStep> {
  WebViewController? _controller;
  String? _error;
  Object? _rawError;
  StackTrace? _stackTrace;
  bool _isGenerating = false;

  static String _slugify(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  @override
  void initState() {
    super.initState();
    // webview_flutter has no platform implementation on web, Linux or
    // Windows, so there is nothing to generate or load a notebook into.
    if (!supportsEmbeddedWebView) return;
    // If a notebook was already generated for the current platform this
    // session, reload it as-is instead of regenerating — regenerating here
    // would discard any in-progress edits made in the embedded JupyterLab
    // view every time this step is merely re-entered.
    final workspace = ref.read(workspaceProvider);
    final platforms = workspace.selectedPlatforms.isNotEmpty
        ? workspace.selectedPlatforms
        : const <String>['snntorch_sim'];
    final existing = ref.read(notebookMetaProvider)[platforms.first];
    if (existing != null) {
      _loadUrl(
        NotebookGenerateService.resolveJupyterUrl(
          jupyterUrl: existing.jupyterUrl,
          workspaceFolder: existing.workspaceFolder,
          baseUrl: ref.read(apiClientProvider).baseUrl,
        ),
        existing.workspaceFolder,
      );
    } else {
      _generateAndLoad();
    }
  }

  void _loadUrl(String targetUrl, String workspaceFolder) {
    final url = NotebookGenerateService.passiveJupyterFolderUrl(
      targetUrl: targetUrl,
      workspaceFolder: workspaceFolder,
      cacheBust: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      _isGenerating = false;
      _error = null;
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..clearCache()
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (e) {
              // Only surface main-frame failures. JupyterLab routinely fires
              // sub-resource errors (kernel probes, extension 404s, fonts)
              // that must not be treated as a page load failure.
              if (e.isForMainFrame == false) return;
              if (mounted) setState(() => _error = e.description);
            },
            onNavigationRequest: (request) {
              // JupyterLab's own "Download" action isn't a real file
              // download here — the embedded WebView has no download
              // handling, so a hard navigation to raw file content (or a
              // blob: URL) would just replace the whole JupyterLab UI in
              // place with e.g. raw notebook JSON, with no way back.
              // Anything that isn't staying inside the JupyterLab app
              // (`/lab...`) is treated as "leaving the app" and handed to
              // the system browser instead, which can actually save it.
              final uri = Uri.tryParse(request.url);
              final staysInApp =
                  uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https') &&
                  uri.path.startsWith('/lab');
              if (!staysInApp) {
                openExternalUrl(request.url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
    });
  }

  Future<void> _generateAndLoad() async {
    setState(() {
      _isGenerating = true;
      _error = null;
      _rawError = null;
      _stackTrace = null;
      _controller = null;
    });

    String? targetUrl;
    String? targetWorkspaceFolder;
    String? errorMessage;
    try {
      final spec = ref.read(specTextProvider);
      if (spec.trim().isEmpty) {
        errorMessage =
            'There is no architecture to turn into a notebook yet. '
            'Define and validate a network in the Architecture step first.';
      } else {
        final api = ref.read(apiClientProvider);
        final workspace = ref.read(workspaceProvider);
        final canvas = ref.read(canvasProvider);
        final importId = NotebookGenerateService.importIdForNotebook(
          nirImportState: ref.read(nirImportProvider),
          retainedFileBackedImportId: ref.read(
            latestFileBackedNirImportIdProvider,
          ),
        );
        final platforms = workspace.selectedPlatforms.isNotEmpty
            ? workspace.selectedPlatforms
            : const <String>['snntorch_sim'];
        final preparation = await DatasetGenerationPreparer(
          apiClient: api,
        ).prepare(canvas.pipelinePhases);
        applyDatasetUploadRemaps(ref, preparation.uploads);
        NotebookGenerationResult? lastResult;
        for (final platform in platforms) {
          final configJson = <String, dynamic>{
            ...canvas.pipeline.toJson(),
            'framework': platform,
            if (workspace.selectedDataset != null)
              'dataset': workspace.selectedDataset!,
          };
          lastResult = await api.generateNotebookV2(
            spec: spec,
            pipelineConfig: configJson,
            pipelinePhases: preparation.phases,
            workspacePath: _slugify(workspace.workspaceName),
            importId: importId.isNotEmpty ? importId : null,
          );
          if (lastResult.notebookFilenames.isNotEmpty) {
            ref
                .read(notebookMetaProvider.notifier)
                .recordGeneration(
                  platform,
                  NotebookGenerationMeta(
                    workspaceFolder: lastResult.workspaceFolder,
                    filename: lastResult.notebookFilenames.first,
                    generatedAt: lastResult.generatedAt,
                    jupyterUrl: lastResult.jupyterUrl,
                  ),
                );
          }
        }
        targetUrl = NotebookGenerateService.resolveJupyterUrl(
          jupyterUrl: lastResult!.jupyterUrl,
          workspaceFolder: lastResult.workspaceFolder,
          baseUrl: api.baseUrl,
        );
        targetWorkspaceFolder = lastResult.workspaceFolder;
      }
    } catch (e, s) {
      errorMessage = _describeError(e);
      _rawError = e;
      _stackTrace = s;
    }

    if (!mounted) return;

    // On any failure, surface an actionable message + Retry instead of silently
    // loading Jupyter Lab's root folder.
    if (errorMessage != null ||
        targetUrl == null ||
        targetWorkspaceFolder == null) {
      setState(() {
        _isGenerating = false;
        _error =
            errorMessage ?? 'Could not prepare the notebook. Please retry.';
        _controller = null;
      });
      return;
    }

    _loadUrl(targetUrl, targetWorkspaceFolder);
  }

  /// Turns an exception into an actionable, user-facing message — never a raw
  /// exception string (see AGENTS.md: error messages must say what to do).
  static String _describeError(Object e) {
    if (e is DatasetPreparationException) {
      // Already an actionable, per-file message (e.g. "Dataset 'x' is no
      // longer readable at '...'. Choose the file again..."). Without this
      // branch it fell through to the generic "Could not reach the backend"
      // text below, which is actively misleading when the real cause is a
      // dataset that isn't present on the current device.
      return e.message;
    }
    if (e is ApiException) {
      // A generic 500 means the backend crashed internally — the detail field
      // will just say "Internal Server Error" which is useless. Replace it with
      // an actionable suggestion (most likely the architecture or pipeline isn't
      // in a state the generator can handle yet).
      if (e.statusCode == 500) {
        return 'The notebook couldn\'t be generated yet. '
            'Make sure your architecture is fully defined and validated in '
            'the Architecture step, then retry.';
      }
      try {
        final decoded = jsonDecode(e.body);
        if (decoded is Map<String, dynamic>) {
          final detail = decoded['detail'];
          if (detail is String && detail.trim().isNotEmpty) {
            return detail.trim();
          }
        }
      } catch (_) {
        // body is not JSON — fall through.
      }
      return 'Notebook generation failed (HTTP ${e.statusCode}). '
          'Check that the backend and Jupyter server are running, then retry.';
    }
    return 'Could not reach the backend to prepare the notebook. '
        'Make sure the suite services are running, then retry.';
  }

  /// Builds the full raw error string shown in the details dialog.
  static String _rawErrorText(Object error, StackTrace? trace) {
    final buf = StringBuffer();
    if (error is ApiException) {
      buf.writeln('HTTP ${error.statusCode}');
      buf.writeln();
      buf.writeln('Response body:');
      buf.writeln(error.body);
    } else {
      buf.writeln(error.toString());
    }
    if (trace != null) {
      buf.writeln();
      buf.writeln('Stack trace:');
      buf.write(trace.toString());
    }
    return buf.toString().trimRight();
  }

  /// Shows an [AlertDialog] with the full raw error and stack trace.
  /// The content is selectable so the user can copy it.
  void _showErrorDetails(BuildContext context) {
    final text = _rawErrorText(_rawError!, _stackTrace);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              ZetaIcons.info,
              size: 18,
              color: Zeta.of(context).colors.mainNegative,
            ),
            const SizedBox(width: 8),
            const Text('Error Details'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              text,
              // ZETA-MIGRATION-EXEMPT: error trace is monospace — Zeta (IBM Plex
              // Sans) has no monospace text style.
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          ZetaButton.text(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              NmtkSnackBars.success(ctx, 'Copied to clipboard');
            },
            label: 'Copy',
          ),
          ZetaButton.text(
            onPressed: () => Navigator.of(ctx).pop(),
            label: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildUnsupportedView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ZetaIcons.info,
            size: 32,
            color: Zeta.of(context).colors.mainSubtle,
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'The notebook opens JupyterLab from your backend. Open this '
              'workspace in the NeuroMorphicToolKit desktop app to edit and '
              'run it.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsEmbeddedWebView) {
      return _buildUnsupportedView(context);
    }

    ref.listen(pipelineProvider.select((p) => p.validateStatus), (prev, next) {
      if (prev != StepStatus.success && next == StepStatus.success) {
        _generateAndLoad();
      }
    });

    ref.listen(workspaceProvider.select((w) => w.selectedPlatforms), (
      prev,
      next,
    ) {
      if (prev != null && !listEquals(prev, next)) {
        _generateAndLoad();
      }
    });

    ref.listen(unlockedStepsProvider.select((steps) => steps.contains('run')), (
      prev,
      next,
    ) {
      if (prev == false && next == true) {
        _generateAndLoad();
      }
    });

    ref.listen(workspaceProvider.select((w) => w.workspaceName), (prev, next) {
      if (prev != null && prev != next) {
        _generateAndLoad();
      }
    });

    if (_isGenerating) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Preparing notebook…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ZetaIcons.error_outline,
              size: 32,
              color: Zeta.of(context).colors.mainNegative,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                      color: Zeta.of(context).colors.mainNegative,
                    ),
                  ),
                ),
                if (_rawError != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Show error details',
                    child: ZetaIconButton.negative(
                      icon: ZetaIcons.info,
                      size: ZetaWidgetSize.small,
                      semanticLabel: 'Show error details',
                      onPressed: () => _showErrorDetails(context),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _generateAndLoad,
              icon: const Icon(ZetaIcons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_controller != null) {
      return Stack(
        children: [
          WebViewWidget(controller: _controller!),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
              color: Colors.transparent,
              child: Tooltip(
                message: 'Reload notebook',
                child: ZetaIconButton.text(
                  icon: ZetaIcons.refresh,
                  size: ZetaWidgetSize.small,
                  semanticLabel: 'Reload notebook',
                  onPressed: _generateAndLoad,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return const Center(child: CircularProgressIndicator());
  }
}
