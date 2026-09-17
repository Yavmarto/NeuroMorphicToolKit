// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'simulation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SimulationController)
final simulationControllerProvider = SimulationControllerProvider._();

final class SimulationControllerProvider
    extends $NotifierProvider<SimulationController, SimulationState> {
  SimulationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'simulationControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$simulationControllerHash();

  @$internal
  @override
  SimulationController create() => SimulationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SimulationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SimulationState>(value),
    );
  }
}

String _$simulationControllerHash() =>
    r'd0344844253f8aecd386bebc151d055f181f0f39';

abstract class _$SimulationController extends $Notifier<SimulationState> {
  SimulationState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SimulationState, SimulationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SimulationState, SimulationState>,
              SimulationState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
