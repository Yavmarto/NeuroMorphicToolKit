// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'neurosim_workspace_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(NeurosimWorkspaceController)
final neurosimWorkspaceControllerProvider =
    NeurosimWorkspaceControllerProvider._();

final class NeurosimWorkspaceControllerProvider
    extends
        $NotifierProvider<NeurosimWorkspaceController, NeurosimWorkspaceState> {
  NeurosimWorkspaceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'neurosimWorkspaceControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$neurosimWorkspaceControllerHash();

  @$internal
  @override
  NeurosimWorkspaceController create() => NeurosimWorkspaceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NeurosimWorkspaceState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NeurosimWorkspaceState>(value),
    );
  }
}

String _$neurosimWorkspaceControllerHash() =>
    r'6b75689a5368703395bc139a935fd6f894517f73';

abstract class _$NeurosimWorkspaceController
    extends $Notifier<NeurosimWorkspaceState> {
  NeurosimWorkspaceState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<NeurosimWorkspaceState, NeurosimWorkspaceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NeurosimWorkspaceState, NeurosimWorkspaceState>,
              NeurosimWorkspaceState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
