// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'training_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TrainingController)
final trainingControllerProvider = TrainingControllerProvider._();

final class TrainingControllerProvider
    extends $NotifierProvider<TrainingController, TrainingProviderState> {
  TrainingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trainingControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trainingControllerHash();

  @$internal
  @override
  TrainingController create() => TrainingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TrainingProviderState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TrainingProviderState>(value),
    );
  }
}

String _$trainingControllerHash() =>
    r'8b83d765b65f50fac00d89a0a2e1e8664f47d7d6';

abstract class _$TrainingController extends $Notifier<TrainingProviderState> {
  TrainingProviderState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TrainingProviderState, TrainingProviderState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TrainingProviderState, TrainingProviderState>,
              TrainingProviderState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
