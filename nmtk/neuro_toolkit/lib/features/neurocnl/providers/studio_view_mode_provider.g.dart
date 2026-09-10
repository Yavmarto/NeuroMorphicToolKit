// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'studio_view_mode_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StudioViewModeController)
final studioViewModeControllerProvider = StudioViewModeControllerProvider._();

final class StudioViewModeControllerProvider
    extends $NotifierProvider<StudioViewModeController, StudioSyncState> {
  StudioViewModeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'studioViewModeControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$studioViewModeControllerHash();

  @$internal
  @override
  StudioViewModeController create() => StudioViewModeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StudioSyncState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StudioSyncState>(value),
    );
  }
}

String _$studioViewModeControllerHash() =>
    r'fd937068747fe6d9c7f94353ce4a077cfc23ea40';

abstract class _$StudioViewModeController extends $Notifier<StudioSyncState> {
  StudioSyncState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<StudioSyncState, StudioSyncState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StudioSyncState, StudioSyncState>,
              StudioSyncState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
