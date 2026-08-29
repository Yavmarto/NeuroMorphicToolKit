// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'neurobench_panel_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(NeurobenchPanelController)
final neurobenchPanelControllerProvider = NeurobenchPanelControllerProvider._();

final class NeurobenchPanelControllerProvider
    extends $NotifierProvider<NeurobenchPanelController, NeurobenchPanelState> {
  NeurobenchPanelControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'neurobenchPanelControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$neurobenchPanelControllerHash();

  @$internal
  @override
  NeurobenchPanelController create() => NeurobenchPanelController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NeurobenchPanelState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NeurobenchPanelState>(value),
    );
  }
}

String _$neurobenchPanelControllerHash() =>
    r'c7dbf961a8fb091f98d1c09ff59261e4a67b2cb5';

abstract class _$NeurobenchPanelController
    extends $Notifier<NeurobenchPanelState> {
  NeurobenchPanelState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<NeurobenchPanelState, NeurobenchPanelState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NeurobenchPanelState, NeurobenchPanelState>,
              NeurobenchPanelState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
