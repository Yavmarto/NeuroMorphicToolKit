// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pipeline_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PipelineController)
final pipelineControllerProvider = PipelineControllerProvider._();

final class PipelineControllerProvider
    extends $NotifierProvider<PipelineController, PipelineState> {
  PipelineControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pipelineControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pipelineControllerHash();

  @$internal
  @override
  PipelineController create() => PipelineController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PipelineState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PipelineState>(value),
    );
  }
}

String _$pipelineControllerHash() =>
    r'844404758961e5e1f94f7420918b83c78b23d523';

abstract class _$PipelineController extends $Notifier<PipelineState> {
  PipelineState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PipelineState, PipelineState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PipelineState, PipelineState>,
              PipelineState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
