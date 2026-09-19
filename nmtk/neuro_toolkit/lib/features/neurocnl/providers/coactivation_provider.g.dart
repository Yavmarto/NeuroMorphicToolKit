// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'coactivation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// "Fire together, wire together" correlation over the per-layer spike rates
/// already streaming through [trainingModeProvider] (live) or a stored
/// [PreviewPlayback] (review).
///
/// Live ingestion is automatic: every non-empty `trainingModeProvider` write
/// appends a sample to the sliding window. When no live rates are present and
/// [simulationProvider] exposes a stored playback, the provider switches to
/// review mode and derives both a correlation snapshot and a replayable rate
/// series. A later live sample returns it to live mode.
///
/// The initial state is also seeded from whatever already exists when the
/// provider is first built (a live stream already running, or a playback that
/// finished before the network view mounted), because the `ref.listen` hooks
/// below only fire on *later* changes.

@ProviderFor(CoactivationController)
final coactivationControllerProvider = CoactivationControllerProvider._();

/// "Fire together, wire together" correlation over the per-layer spike rates
/// already streaming through [trainingModeProvider] (live) or a stored
/// [PreviewPlayback] (review).
///
/// Live ingestion is automatic: every non-empty `trainingModeProvider` write
/// appends a sample to the sliding window. When no live rates are present and
/// [simulationProvider] exposes a stored playback, the provider switches to
/// review mode and derives both a correlation snapshot and a replayable rate
/// series. A later live sample returns it to live mode.
///
/// The initial state is also seeded from whatever already exists when the
/// provider is first built (a live stream already running, or a playback that
/// finished before the network view mounted), because the `ref.listen` hooks
/// below only fire on *later* changes.
final class CoactivationControllerProvider
    extends $NotifierProvider<CoactivationController, CoactivationState> {
  /// "Fire together, wire together" correlation over the per-layer spike rates
  /// already streaming through [trainingModeProvider] (live) or a stored
  /// [PreviewPlayback] (review).
  ///
  /// Live ingestion is automatic: every non-empty `trainingModeProvider` write
  /// appends a sample to the sliding window. When no live rates are present and
  /// [simulationProvider] exposes a stored playback, the provider switches to
  /// review mode and derives both a correlation snapshot and a replayable rate
  /// series. A later live sample returns it to live mode.
  ///
  /// The initial state is also seeded from whatever already exists when the
  /// provider is first built (a live stream already running, or a playback that
  /// finished before the network view mounted), because the `ref.listen` hooks
  /// below only fire on *later* changes.
  CoactivationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coactivationControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coactivationControllerHash();

  @$internal
  @override
  CoactivationController create() => CoactivationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CoactivationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CoactivationState>(value),
    );
  }
}

String _$coactivationControllerHash() =>
    r'e35f3290a088b38e1a5ecf1635db5cd7264f57ab';

/// "Fire together, wire together" correlation over the per-layer spike rates
/// already streaming through [trainingModeProvider] (live) or a stored
/// [PreviewPlayback] (review).
///
/// Live ingestion is automatic: every non-empty `trainingModeProvider` write
/// appends a sample to the sliding window. When no live rates are present and
/// [simulationProvider] exposes a stored playback, the provider switches to
/// review mode and derives both a correlation snapshot and a replayable rate
/// series. A later live sample returns it to live mode.
///
/// The initial state is also seeded from whatever already exists when the
/// provider is first built (a live stream already running, or a playback that
/// finished before the network view mounted), because the `ref.listen` hooks
/// below only fire on *later* changes.

abstract class _$CoactivationController extends $Notifier<CoactivationState> {
  CoactivationState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CoactivationState, CoactivationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CoactivationState, CoactivationState>,
              CoactivationState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
