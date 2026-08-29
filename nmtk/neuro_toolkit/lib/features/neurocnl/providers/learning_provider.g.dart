// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'learning_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LearningController)
final learningControllerProvider = LearningControllerProvider._();

final class LearningControllerProvider
    extends $NotifierProvider<LearningController, LearningState> {
  LearningControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'learningControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$learningControllerHash();

  @$internal
  @override
  LearningController create() => LearningController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LearningState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LearningState>(value),
    );
  }
}

String _$learningControllerHash() =>
    r'341665bd11fea6c9deb5f5ae916ec976454487b3';

abstract class _$LearningController extends $Notifier<LearningState> {
  LearningState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<LearningState, LearningState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LearningState, LearningState>,
              LearningState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
