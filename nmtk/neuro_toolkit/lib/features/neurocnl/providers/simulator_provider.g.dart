// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'simulator_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SimulatorCapabilitiesController)
final simulatorCapabilitiesControllerProvider =
    SimulatorCapabilitiesControllerProvider._();

final class SimulatorCapabilitiesControllerProvider
    extends
        $AsyncNotifierProvider<
          SimulatorCapabilitiesController,
          List<SimulatorCapability>
        > {
  SimulatorCapabilitiesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'simulatorCapabilitiesControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$simulatorCapabilitiesControllerHash();

  @$internal
  @override
  SimulatorCapabilitiesController create() => SimulatorCapabilitiesController();
}

String _$simulatorCapabilitiesControllerHash() =>
    r'b86b21c45274da48fcdd436d37f0dce7e024f107';

abstract class _$SimulatorCapabilitiesController
    extends $AsyncNotifier<List<SimulatorCapability>> {
  FutureOr<List<SimulatorCapability>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<SimulatorCapability>>,
              List<SimulatorCapability>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<SimulatorCapability>>,
                List<SimulatorCapability>
              >,
              AsyncValue<List<SimulatorCapability>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The newest trained NIR graph in [workspaceFolder], or null when there is none.
///
/// Without it a run simulates the CNL spec's zeros — correct shapes, every value
/// 0.0, so no neuron can reach threshold and the raster comes back empty. This is
/// the same artifact the PYNQ deploy path reads, so a network trained once feeds
/// both.
///
/// A missing artifact is a null, not an error: "you have not trained this yet" is
/// a state the Run button reports, not a failure to surface.

@ProviderFor(simulatorTrainedNir)
final simulatorTrainedNirProvider = SimulatorTrainedNirFamily._();

/// The newest trained NIR graph in [workspaceFolder], or null when there is none.
///
/// Without it a run simulates the CNL spec's zeros — correct shapes, every value
/// 0.0, so no neuron can reach threshold and the raster comes back empty. This is
/// the same artifact the PYNQ deploy path reads, so a network trained once feeds
/// both.
///
/// A missing artifact is a null, not an error: "you have not trained this yet" is
/// a state the Run button reports, not a failure to surface.

final class SimulatorTrainedNirProvider
    extends
        $FunctionalProvider<
          AsyncValue<TrainedNirArtifact?>,
          TrainedNirArtifact?,
          FutureOr<TrainedNirArtifact?>
        >
    with
        $FutureModifier<TrainedNirArtifact?>,
        $FutureProvider<TrainedNirArtifact?> {
  /// The newest trained NIR graph in [workspaceFolder], or null when there is none.
  ///
  /// Without it a run simulates the CNL spec's zeros — correct shapes, every value
  /// 0.0, so no neuron can reach threshold and the raster comes back empty. This is
  /// the same artifact the PYNQ deploy path reads, so a network trained once feeds
  /// both.
  ///
  /// A missing artifact is a null, not an error: "you have not trained this yet" is
  /// a state the Run button reports, not a failure to surface.
  SimulatorTrainedNirProvider._({
    required SimulatorTrainedNirFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'simulatorTrainedNirProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$simulatorTrainedNirHash();

  @override
  String toString() {
    return r'simulatorTrainedNirProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<TrainedNirArtifact?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TrainedNirArtifact?> create(Ref ref) {
    final argument = this.argument as String;
    return simulatorTrainedNir(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SimulatorTrainedNirProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$simulatorTrainedNirHash() =>
    r'574ba87d231df0a0278c5a7836724d584bf705ad';

/// The newest trained NIR graph in [workspaceFolder], or null when there is none.
///
/// Without it a run simulates the CNL spec's zeros — correct shapes, every value
/// 0.0, so no neuron can reach threshold and the raster comes back empty. This is
/// the same artifact the PYNQ deploy path reads, so a network trained once feeds
/// both.
///
/// A missing artifact is a null, not an error: "you have not trained this yet" is
/// a state the Run button reports, not a failure to surface.

final class SimulatorTrainedNirFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<TrainedNirArtifact?>, String> {
  SimulatorTrainedNirFamily._()
    : super(
        retry: null,
        name: r'simulatorTrainedNirProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The newest trained NIR graph in [workspaceFolder], or null when there is none.
  ///
  /// Without it a run simulates the CNL spec's zeros — correct shapes, every value
  /// 0.0, so no neuron can reach threshold and the raster comes back empty. This is
  /// the same artifact the PYNQ deploy path reads, so a network trained once feeds
  /// both.
  ///
  /// A missing artifact is a null, not an error: "you have not trained this yet" is
  /// a state the Run button reports, not a failure to surface.

  SimulatorTrainedNirProvider call(String workspaceFolder) =>
      SimulatorTrainedNirProvider._(argument: workspaceFolder, from: this);

  @override
  String toString() => r'simulatorTrainedNirProvider';
}

@ProviderFor(SimulatorRunController)
final simulatorRunControllerProvider = SimulatorRunControllerFamily._();

final class SimulatorRunControllerProvider
    extends $NotifierProvider<SimulatorRunController, SimulatorRunState> {
  SimulatorRunControllerProvider._({
    required SimulatorRunControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'simulatorRunControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$simulatorRunControllerHash();

  @override
  String toString() {
    return r'simulatorRunControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SimulatorRunController create() => SimulatorRunController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SimulatorRunState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SimulatorRunState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SimulatorRunControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$simulatorRunControllerHash() =>
    r'd813bee406349b7a668439c380a46354c591a3d3';

final class SimulatorRunControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SimulatorRunController,
          SimulatorRunState,
          SimulatorRunState,
          SimulatorRunState,
          String
        > {
  SimulatorRunControllerFamily._()
    : super(
        retry: null,
        name: r'simulatorRunControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SimulatorRunControllerProvider call(String backendName) =>
      SimulatorRunControllerProvider._(argument: backendName, from: this);

  @override
  String toString() => r'simulatorRunControllerProvider';
}

abstract class _$SimulatorRunController extends $Notifier<SimulatorRunState> {
  late final _$args = ref.$arg as String;
  String get backendName => _$args;

  SimulatorRunState build(String backendName);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SimulatorRunState, SimulatorRunState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SimulatorRunState, SimulatorRunState>,
              SimulatorRunState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(SimulatorSettingsController)
final simulatorSettingsControllerProvider =
    SimulatorSettingsControllerFamily._();

final class SimulatorSettingsControllerProvider
    extends $NotifierProvider<SimulatorSettingsController, SimulatorSettings> {
  SimulatorSettingsControllerProvider._({
    required SimulatorSettingsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'simulatorSettingsControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$simulatorSettingsControllerHash();

  @override
  String toString() {
    return r'simulatorSettingsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SimulatorSettingsController create() => SimulatorSettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SimulatorSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SimulatorSettings>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SimulatorSettingsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$simulatorSettingsControllerHash() =>
    r'd3e6474b0e230b4b88f318fb4cf3a89b5cfc2a5c';

final class SimulatorSettingsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SimulatorSettingsController,
          SimulatorSettings,
          SimulatorSettings,
          SimulatorSettings,
          String
        > {
  SimulatorSettingsControllerFamily._()
    : super(
        retry: null,
        name: r'simulatorSettingsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SimulatorSettingsControllerProvider call(String backendName) =>
      SimulatorSettingsControllerProvider._(argument: backendName, from: this);

  @override
  String toString() => r'simulatorSettingsControllerProvider';
}

abstract class _$SimulatorSettingsController
    extends $Notifier<SimulatorSettings> {
  late final _$args = ref.$arg as String;
  String get backendName => _$args;

  SimulatorSettings build(String backendName);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SimulatorSettings, SimulatorSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SimulatorSettings, SimulatorSettings>,
              SimulatorSettings,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
