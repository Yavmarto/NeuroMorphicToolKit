// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hardware_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HardwareController)
final hardwareControllerProvider = HardwareControllerProvider._();

final class HardwareControllerProvider
    extends $NotifierProvider<HardwareController, HardwareState> {
  HardwareControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hardwareControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hardwareControllerHash();

  @$internal
  @override
  HardwareController create() => HardwareController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HardwareState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HardwareState>(value),
    );
  }
}

String _$hardwareControllerHash() =>
    r'4e13292f8ff3da7a075fc125889095041d98f97e';

abstract class _$HardwareController extends $Notifier<HardwareState> {
  HardwareState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<HardwareState, HardwareState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HardwareState, HardwareState>,
              HardwareState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
