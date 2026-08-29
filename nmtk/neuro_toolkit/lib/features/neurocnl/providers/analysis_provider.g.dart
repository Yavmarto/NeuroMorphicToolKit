// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analysis_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AnalysisController)
final analysisControllerProvider = AnalysisControllerProvider._();

final class AnalysisControllerProvider
    extends $NotifierProvider<AnalysisController, AnalysisState> {
  AnalysisControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'analysisControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$analysisControllerHash();

  @$internal
  @override
  AnalysisController create() => AnalysisController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AnalysisState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AnalysisState>(value),
    );
  }
}

String _$analysisControllerHash() =>
    r'870117e0dd97b438e1279bab68ed082f1f6cd44b';

abstract class _$AnalysisController extends $Notifier<AnalysisState> {
  AnalysisState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AnalysisState, AnalysisState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AnalysisState, AnalysisState>,
              AnalysisState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
