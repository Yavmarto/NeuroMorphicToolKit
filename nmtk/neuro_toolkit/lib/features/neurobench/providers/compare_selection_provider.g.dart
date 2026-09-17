// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'compare_selection_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Result IDs selected on the Results tab for multi-run comparison (max 2).

@ProviderFor(CompareSelection)
final compareSelectionProvider = CompareSelectionProvider._();

/// Result IDs selected on the Results tab for multi-run comparison (max 2).
final class CompareSelectionProvider
    extends $NotifierProvider<CompareSelection, Set<String>> {
  /// Result IDs selected on the Results tab for multi-run comparison (max 2).
  CompareSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'compareSelectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$compareSelectionHash();

  @$internal
  @override
  CompareSelection create() => CompareSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$compareSelectionHash() => r'5f5ed36fdc92946d15288d9359ff8994dbb5754c';

/// Result IDs selected on the Results tab for multi-run comparison (max 2).

abstract class _$CompareSelection extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
