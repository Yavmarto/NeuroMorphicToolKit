// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_akida_deploy_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StudioAkidaDeployController)
final studioAkidaDeployControllerProvider =
    StudioAkidaDeployControllerProvider._();

final class StudioAkidaDeployControllerProvider
    extends
        $NotifierProvider<StudioAkidaDeployController, StudioAkidaDeployState> {
  StudioAkidaDeployControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioAkidaDeployControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioAkidaDeployControllerHash();

  @$internal
  @override
  StudioAkidaDeployController create() => StudioAkidaDeployController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioAkidaDeployState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioAkidaDeployState>(value),
    );
  }
}

String _$studioAkidaDeployControllerHash() =>
    r'59f73ca8eb2b19a6f47dfe0419b4638a985b2774';

abstract class _$StudioAkidaDeployController
    extends $Notifier<StudioAkidaDeployState> {
  StudioAkidaDeployState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<StudioAkidaDeployState, StudioAkidaDeployState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StudioAkidaDeployState, StudioAkidaDeployState>,
              StudioAkidaDeployState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
