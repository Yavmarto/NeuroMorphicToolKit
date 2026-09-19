// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_voyager_deploy_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StudioVoyagerDeployController)
final studioVoyagerDeployControllerProvider =
    StudioVoyagerDeployControllerProvider._();

final class StudioVoyagerDeployControllerProvider
    extends
        $NotifierProvider<
          StudioVoyagerDeployController,
          StudioVoyagerDeployState
        > {
  StudioVoyagerDeployControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioVoyagerDeployControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioVoyagerDeployControllerHash();

  @$internal
  @override
  StudioVoyagerDeployController create() => StudioVoyagerDeployController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioVoyagerDeployState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioVoyagerDeployState>(value),
    );
  }
}

String _$studioVoyagerDeployControllerHash() =>
    r'f55058344d5aa8e86a741492471ae06bd3afcd1e';

abstract class _$StudioVoyagerDeployController
    extends $Notifier<StudioVoyagerDeployState> {
  StudioVoyagerDeployState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<StudioVoyagerDeployState, StudioVoyagerDeployState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StudioVoyagerDeployState, StudioVoyagerDeployState>,
              StudioVoyagerDeployState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
