// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prosthetic_sim_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ProstheticSimController)
final prostheticSimControllerProvider = ProstheticSimControllerProvider._();

final class ProstheticSimControllerProvider
    extends $NotifierProvider<ProstheticSimController, ProstheticSimState> {
  ProstheticSimControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'prostheticSimControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$prostheticSimControllerHash();

  @$internal
  @override
  ProstheticSimController create() => ProstheticSimController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProstheticSimState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProstheticSimState>(value),
    );
  }
}

String _$prostheticSimControllerHash() =>
    r'4dc32cbcf52a3320301883b4db5dea586db33187';

abstract class _$ProstheticSimController extends $Notifier<ProstheticSimState> {
  ProstheticSimState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ProstheticSimState, ProstheticSimState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProstheticSimState, ProstheticSimState>,
              ProstheticSimState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
