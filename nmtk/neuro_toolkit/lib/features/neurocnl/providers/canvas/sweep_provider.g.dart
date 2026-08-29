// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sweep_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SweepController)
final sweepControllerProvider = SweepControllerProvider._();

final class SweepControllerProvider
    extends $NotifierProvider<SweepController, SweepState> {
  SweepControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sweepControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sweepControllerHash();

  @$internal
  @override
  SweepController create() => SweepController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SweepState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SweepState>(value),
    );
  }
}

String _$sweepControllerHash() => r'a3156d4310235b076a35ddaa94b80e366e0c6b13';

abstract class _$SweepController extends $Notifier<SweepState> {
  SweepState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SweepState, SweepState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SweepState, SweepState>,
              SweepState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
