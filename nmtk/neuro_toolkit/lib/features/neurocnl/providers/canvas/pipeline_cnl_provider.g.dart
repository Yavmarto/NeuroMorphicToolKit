// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pipeline_cnl_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(PipelineCnlController)
final pipelineCnlControllerProvider = PipelineCnlControllerProvider._();

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
final class PipelineCnlControllerProvider
    extends $NotifierProvider<PipelineCnlController, AsyncValue<String>> {
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
  PipelineCnlControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pipelineCnlControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pipelineCnlControllerHash();

  @$internal
  @override
  PipelineCnlController create() => PipelineCnlController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<String>>(value),
    );
  }
}

String _$pipelineCnlControllerHash() =>
    r'ca4dd21802b1d64ce4efd5f2d31b454dfc0c66ed';

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

abstract class _$PipelineCnlController extends $Notifier<AsyncValue<String>> {
  AsyncValue<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<String>, AsyncValue<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<String>, AsyncValue<String>>,
              AsyncValue<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
