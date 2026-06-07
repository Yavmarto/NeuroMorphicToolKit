// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'environment_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(EnvironmentNotifier)
final environmentProvider = EnvironmentNotifierProvider._();

final class EnvironmentNotifierProvider
    extends $AsyncNotifierProvider<EnvironmentNotifier, EnvironmentState> {
  EnvironmentNotifierProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'environmentProvider',
          isAutoDispose: true,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$environmentNotifierHash();

  @$internal
  @override
  EnvironmentNotifier create() => EnvironmentNotifier();
}

String _$environmentNotifierHash() =>
    r'5706a50417fdb6ceb2b18dd30b5a400545928deb';

abstract class _$EnvironmentNotifier extends $AsyncNotifier<EnvironmentState> {
  FutureOr<EnvironmentState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<EnvironmentState>, EnvironmentState>;
    final element = ref.element as $ClassProviderElement<
        AnyNotifier<AsyncValue<EnvironmentState>, EnvironmentState>,
        AsyncValue<EnvironmentState>,
        Object?,
        Object?>;
    element.handleCreate(ref, build);
  }
}
