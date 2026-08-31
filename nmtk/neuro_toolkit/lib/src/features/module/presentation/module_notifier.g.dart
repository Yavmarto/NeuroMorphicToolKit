// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'module_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ModuleNotifier)
final moduleProvider = ModuleNotifierProvider._();

final class ModuleNotifierProvider
    extends $AsyncNotifierProvider<ModuleNotifier, ModuleState> {
  ModuleNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'moduleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$moduleNotifierHash();

  @$internal
  @override
  ModuleNotifier create() => ModuleNotifier();
}

String _$moduleNotifierHash() => r'f2ea47df262085d0d81f1284b6d61c0ec4dd19f5';

abstract class _$ModuleNotifier extends $AsyncNotifier<ModuleState> {
  FutureOr<ModuleState> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ModuleState>, ModuleState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ModuleState>, ModuleState>,
              AsyncValue<ModuleState>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
