// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'execution_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(BenchmarkExecutionController)
final benchmarkExecutionControllerProvider =
    BenchmarkExecutionControllerProvider._();

final class BenchmarkExecutionControllerProvider
    extends
        $NotifierProvider<
          BenchmarkExecutionController,
          BenchmarkExecutionState
        > {
  BenchmarkExecutionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'benchmarkExecutionControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$benchmarkExecutionControllerHash();

  @$internal
  @override
  BenchmarkExecutionController create() => BenchmarkExecutionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BenchmarkExecutionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BenchmarkExecutionState>(value),
    );
  }
}

String _$benchmarkExecutionControllerHash() =>
    r'477f3eb71efe61fda038604b4ddc49f169e8ae54';

abstract class _$BenchmarkExecutionController
    extends $Notifier<BenchmarkExecutionState> {
  BenchmarkExecutionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<BenchmarkExecutionState, BenchmarkExecutionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BenchmarkExecutionState, BenchmarkExecutionState>,
              BenchmarkExecutionState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
