// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hardware_config_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SelectedHardwareConfigController)
final selectedHardwareConfigControllerProvider =
    SelectedHardwareConfigControllerProvider._();

final class SelectedHardwareConfigControllerProvider
    extends
        $NotifierProvider<SelectedHardwareConfigController, HardwareConfig?> {
  SelectedHardwareConfigControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedHardwareConfigControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedHardwareConfigControllerHash();

  @$internal
  @override
  SelectedHardwareConfigController create() =>
      SelectedHardwareConfigController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HardwareConfig? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HardwareConfig?>(value),
    );
  }
}

String _$selectedHardwareConfigControllerHash() =>
    r'39b528392377a7199b428a58a6ce9cfed7f27abe';

abstract class _$SelectedHardwareConfigController
    extends $Notifier<HardwareConfig?> {
  HardwareConfig? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<HardwareConfig?, HardwareConfig?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HardwareConfig?, HardwareConfig?>,
              HardwareConfig?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
