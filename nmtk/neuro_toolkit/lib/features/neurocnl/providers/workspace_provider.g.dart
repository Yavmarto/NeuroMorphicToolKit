// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspaceBootstrap)
final workspaceBootstrapProvider = WorkspaceBootstrapProvider._();

final class WorkspaceBootstrapProvider
    extends
        $FunctionalProvider<
          WorkspaceBootstrap,
          WorkspaceBootstrap,
          WorkspaceBootstrap
        >
    with $Provider<WorkspaceBootstrap> {
  WorkspaceBootstrapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceBootstrapProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceBootstrapHash();

  @$internal
  @override
  $ProviderElement<WorkspaceBootstrap> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceBootstrap create(Ref ref) {
    return workspaceBootstrap(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceBootstrap value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceBootstrap>(value),
    );
  }
}

String _$workspaceBootstrapHash() =>
    r'43bea27ecdf5cd2ee7ed614f4eee89d6ee6a26ee';

@ProviderFor(WorkspaceController)
final workspaceControllerProvider = WorkspaceControllerProvider._();

final class WorkspaceControllerProvider
    extends $NotifierProvider<WorkspaceController, WorkspaceState> {
  WorkspaceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceControllerHash();

  @$internal
  @override
  WorkspaceController create() => WorkspaceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceState>(value),
    );
  }
}

String _$workspaceControllerHash() =>
    r'18998f45714b347560edcb720f328d31dbaa472b';

abstract class _$WorkspaceController extends $Notifier<WorkspaceState> {
  WorkspaceState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<WorkspaceState, WorkspaceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WorkspaceState, WorkspaceState>,
              WorkspaceState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(workspaceRestoreState)
final workspaceRestoreStateProvider = WorkspaceRestoreStateProvider._();

final class WorkspaceRestoreStateProvider
    extends
        $FunctionalProvider<
          Map<String, dynamic>,
          Map<String, dynamic>,
          Map<String, dynamic>
        >
    with $Provider<Map<String, dynamic>> {
  WorkspaceRestoreStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceRestoreStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceRestoreStateHash();

  @$internal
  @override
  $ProviderElement<Map<String, dynamic>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, dynamic> create(Ref ref) {
    return workspaceRestoreState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, dynamic> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, dynamic>>(value),
    );
  }
}

String _$workspaceRestoreStateHash() =>
    r'2b40648eb72bfef14c828c43a8dd847984cba791';
