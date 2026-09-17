// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'akida_deploy_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AkidaDeployController)
final akidaDeployControllerProvider = AkidaDeployControllerProvider._();

final class AkidaDeployControllerProvider
    extends $NotifierProvider<AkidaDeployController, AkidaDeployState> {
  AkidaDeployControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'akidaDeployControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$akidaDeployControllerHash();

  @$internal
  @override
  AkidaDeployController create() => AkidaDeployController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AkidaDeployState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AkidaDeployState>(value),
    );
  }
}

String _$akidaDeployControllerHash() =>
    r'd964fc9aa2a638ff18fb8c8f4db87e75d7555b28';

abstract class _$AkidaDeployController extends $Notifier<AkidaDeployState> {
  AkidaDeployState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AkidaDeployState, AkidaDeployState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AkidaDeployState, AkidaDeployState>,
              AkidaDeployState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
