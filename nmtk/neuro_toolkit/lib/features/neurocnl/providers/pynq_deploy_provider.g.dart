// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pynq_deploy_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PynqDeployController)
final pynqDeployControllerProvider = PynqDeployControllerProvider._();

final class PynqDeployControllerProvider
    extends $NotifierProvider<PynqDeployController, PynqDeployState> {
  PynqDeployControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pynqDeployControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pynqDeployControllerHash();

  @$internal
  @override
  PynqDeployController create() => PynqDeployController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PynqDeployState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PynqDeployState>(value),
    );
  }
}

String _$pynqDeployControllerHash() =>
    r'f1449c9a42b45abf7169b2c8e4c3e470b953e5f3';

abstract class _$PynqDeployController extends $Notifier<PynqDeployState> {
  PynqDeployState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PynqDeployState, PynqDeployState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PynqDeployState, PynqDeployState>,
              PynqDeployState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
