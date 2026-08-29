import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';

part 'pipeline_cnl_provider.g.dart';

/// Renders [CanvasState.pipeline] as Train/Evaluate/Export CNL text
/// (debounced, for the Pipeline tab's CNL preview panel) and applies
/// hand-edited CNL text back onto [PipelineConfig] on explicit request.
///
/// Deliberately lighter-weight than [CanvasController]'s architecture-CNL
/// sync (`sync_provider.dart` / `studio_sync_notifier.dart`): no
/// re-entrancy guards, no revision tokens. Pipeline CNL is
/// one-way-authoritative-by-default — [PipelineConfig] is always the
/// source of truth; rendering it to CNL text is the common case (a
/// debounced preview), while parsing CNL text back into [PipelineConfig]
/// only happens on an explicit [applyCnlText] call, since
/// `/notebook/parse-pipeline-cnl` is fail-closed and a "preview as you
/// type" experience would surface parse errors on every keystroke.
@riverpod
class PipelineCnlController extends _$PipelineCnlController {
  Timer? _debounceTimer;
  int _renderRequestId = 0;

  @override
  AsyncValue<String> build() {
    ref.listen<PipelineConfig>(canvasProvider.select((s) => s.pipeline), (
      previous,
      next,
    ) {
      if (previous != next) _scheduleRender(next);
    });
    ref.onDispose(() => _debounceTimer?.cancel());
    _scheduleRender(ref.read(canvasProvider).pipeline, debounce: false);
    return const AsyncValue.loading();
  }

  void _scheduleRender(PipelineConfig config, {bool debounce = true}) {
    _debounceTimer?.cancel();
    if (!debounce) {
      unawaited(_render(config));
      return;
    }
    _debounceTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_render(config)),
    );
  }

  Future<void> _render(PipelineConfig config) async {
    final requestId = ++_renderRequestId;
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.generatePipelineCnl(config.toJson());
      if (!ref.mounted || requestId != _renderRequestId) {
        return; // disposed, or a newer render superseded this one
      }
      state = AsyncValue.data(result.cnlText);
    } catch (e, st) {
      if (!ref.mounted || requestId != _renderRequestId) return;
      state = AsyncValue.error(e, st);
    }
  }

  /// Parse [cnlText] and, on success, apply the resulting config onto
  /// [CanvasState.pipeline] via [CanvasController.updatePipeline].
  ///
  /// Rethrows on a fail-closed parse error so the caller (the CNL panel)
  /// can show diagnostics inline — [PipelineConfig] is left untouched
  /// either way; this method never mutates state on failure.
  Future<void> applyCnlText(String cnlText) async {
    final api = ref.read(apiClientProvider);
    final currentConfig = ref.read(canvasProvider).pipeline;
    final result = await api.parsePipelineCnl(cnlText, currentConfig.toJson());
    if (!ref.mounted) return;
    ref.read(canvasProvider.notifier).updatePipeline(result.pipelineConfig);
    state = AsyncValue.data(cnlText);
  }
}

final pipelineCnlProvider = pipelineCnlControllerProvider;
