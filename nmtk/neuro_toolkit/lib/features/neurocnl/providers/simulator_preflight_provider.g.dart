// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'simulator_preflight_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SimulatorPreflightController)
final simulatorPreflightControllerProvider =
    SimulatorPreflightControllerProvider._();

final class SimulatorPreflightControllerProvider
    extends
        $NotifierProvider<
          SimulatorPreflightController,
          SimulatorPreflightState
        > {
  SimulatorPreflightControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'simulatorPreflightControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$simulatorPreflightControllerHash();

  @$internal
  @override
  SimulatorPreflightController create() => SimulatorPreflightController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SimulatorPreflightState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SimulatorPreflightState>(value),
    );
  }
}

String _$simulatorPreflightControllerHash() =>
    r'97878619128063d66975dc75050ad84b09265c90';

abstract class _$SimulatorPreflightController
    extends $Notifier<SimulatorPreflightState> {
  SimulatorPreflightState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<SimulatorPreflightState, SimulatorPreflightState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SimulatorPreflightState, SimulatorPreflightState>,
              SimulatorPreflightState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
