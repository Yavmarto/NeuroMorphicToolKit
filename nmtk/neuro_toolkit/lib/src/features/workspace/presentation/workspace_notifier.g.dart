// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WorkspaceNotifier)
final workspaceProvider = WorkspaceNotifierProvider._();

final class WorkspaceNotifierProvider
    extends $AsyncNotifierProvider<WorkspaceNotifier, WorkspaceState> {
  WorkspaceNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceNotifierHash();

  @$internal
  @override
  WorkspaceNotifier create() => WorkspaceNotifier();
}

String _$workspaceNotifierHash() => r'9a5a9dbbe00ebb3a3b433e20f52ed560ccd0e176';

abstract class _$WorkspaceNotifier extends $AsyncNotifier<WorkspaceState> {
  FutureOr<WorkspaceState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<WorkspaceState>, WorkspaceState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<WorkspaceState>, WorkspaceState>,
              AsyncValue<WorkspaceState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
