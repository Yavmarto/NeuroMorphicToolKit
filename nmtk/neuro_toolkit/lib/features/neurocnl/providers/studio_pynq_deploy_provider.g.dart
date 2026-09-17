// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_pynq_deploy_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StudioPynqDeployController)
final studioPynqDeployControllerProvider =
    StudioPynqDeployControllerProvider._();

final class StudioPynqDeployControllerProvider
    extends
        $NotifierProvider<StudioPynqDeployController, StudioPynqDeployState> {
  StudioPynqDeployControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioPynqDeployControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioPynqDeployControllerHash();

  @$internal
  @override
  StudioPynqDeployController create() => StudioPynqDeployController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioPynqDeployState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioPynqDeployState>(value),
    );
  }
}

String _$studioPynqDeployControllerHash() =>
    r'b2fc58ef000f1e060c5c845a187f1009ec948879';

abstract class _$StudioPynqDeployController
    extends $Notifier<StudioPynqDeployState> {
  StudioPynqDeployState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<StudioPynqDeployState, StudioPynqDeployState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StudioPynqDeployState, StudioPynqDeployState>,
              StudioPynqDeployState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
