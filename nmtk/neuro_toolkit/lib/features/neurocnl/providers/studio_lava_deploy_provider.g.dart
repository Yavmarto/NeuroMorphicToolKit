// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_lava_deploy_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StudioLavaDeployController)
final studioLavaDeployControllerProvider =
    StudioLavaDeployControllerProvider._();

final class StudioLavaDeployControllerProvider
    extends
        $NotifierProvider<StudioLavaDeployController, StudioLavaDeployState> {
  StudioLavaDeployControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioLavaDeployControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioLavaDeployControllerHash();

  @$internal
  @override
  StudioLavaDeployController create() => StudioLavaDeployController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioLavaDeployState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioLavaDeployState>(value),
    );
  }
}

String _$studioLavaDeployControllerHash() =>
    r'dabf3df003a2215d5d2bb060653165b3b175da0d';

abstract class _$StudioLavaDeployController
    extends $Notifier<StudioLavaDeployState> {
  StudioLavaDeployState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<StudioLavaDeployState, StudioLavaDeployState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StudioLavaDeployState, StudioLavaDeployState>,
              StudioLavaDeployState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
