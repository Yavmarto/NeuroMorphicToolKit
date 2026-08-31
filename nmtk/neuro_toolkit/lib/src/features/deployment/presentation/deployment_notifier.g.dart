// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deployment_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BackendDeploymentNotifier)
final backendDeploymentProvider = BackendDeploymentNotifierProvider._();

final class BackendDeploymentNotifierProvider
    extends $AsyncNotifierProvider<BackendDeploymentNotifier, DeploymentState> {
  BackendDeploymentNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backendDeploymentProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backendDeploymentNotifierHash();

  @$internal
  @override
  BackendDeploymentNotifier create() => BackendDeploymentNotifier();
}

String _$backendDeploymentNotifierHash() =>
    r'b4880c6458a0f725cc541d3c530f9759964136a9';

abstract class _$BackendDeploymentNotifier
    extends $AsyncNotifier<DeploymentState> {
  FutureOr<DeploymentState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<DeploymentState>, DeploymentState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<DeploymentState>, DeploymentState>,
              AsyncValue<DeploymentState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
