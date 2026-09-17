// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'autosave_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracked as an in-flight counter (not a bool) because
/// `WorkspaceController._persist()` and `_scheduleCanvasAutosave()` are two
/// independent local-storage writers that can be in flight at the same time
/// — the indicator must only report "saved" once every writer has finished.

@ProviderFor(AutosaveStatusController)
final autosaveStatusControllerProvider = AutosaveStatusControllerProvider._();

/// Tracked as an in-flight counter (not a bool) because
/// `WorkspaceController._persist()` and `_scheduleCanvasAutosave()` are two
/// independent local-storage writers that can be in flight at the same time
/// — the indicator must only report "saved" once every writer has finished.
final class AutosaveStatusControllerProvider
    extends $NotifierProvider<AutosaveStatusController, AutosaveStatus> {
  /// Tracked as an in-flight counter (not a bool) because
  /// `WorkspaceController._persist()` and `_scheduleCanvasAutosave()` are two
  /// independent local-storage writers that can be in flight at the same time
  /// — the indicator must only report "saved" once every writer has finished.
  AutosaveStatusControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'autosaveStatusControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$autosaveStatusControllerHash();

  @$internal
  @override
  AutosaveStatusController create() => AutosaveStatusController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AutosaveStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AutosaveStatus>(value),
    );
  }
}

String _$autosaveStatusControllerHash() =>
    r'a3a4dbf5bcf9a4f66e641b92c090c9c42536014b';

/// Tracked as an in-flight counter (not a bool) because
/// `WorkspaceController._persist()` and `_scheduleCanvasAutosave()` are two
/// independent local-storage writers that can be in flight at the same time
/// — the indicator must only report "saved" once every writer has finished.

abstract class _$AutosaveStatusController extends $Notifier<AutosaveStatus> {
  AutosaveStatus build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AutosaveStatus, AutosaveStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AutosaveStatus, AutosaveStatus>,
              AutosaveStatus,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
