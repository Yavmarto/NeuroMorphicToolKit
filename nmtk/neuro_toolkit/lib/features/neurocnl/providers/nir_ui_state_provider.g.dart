// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nir_ui_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(NirUiStateController)
final nirUiStateControllerProvider = NirUiStateControllerProvider._();

final class NirUiStateControllerProvider
    extends $NotifierProvider<NirUiStateController, Map<String, Set<String>>> {
  NirUiStateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nirUiStateControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nirUiStateControllerHash();

  @$internal
  @override
  NirUiStateController create() => NirUiStateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, Set<String>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, Set<String>>>(value),
    );
  }
}

String _$nirUiStateControllerHash() =>
    r'fb699f922b03cbef017dc35ca0b4768566f77866';

abstract class _$NirUiStateController
    extends $Notifier<Map<String, Set<String>>> {
  Map<String, Set<String>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<Map<String, Set<String>>, Map<String, Set<String>>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, Set<String>>, Map<String, Set<String>>>,
              Map<String, Set<String>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
