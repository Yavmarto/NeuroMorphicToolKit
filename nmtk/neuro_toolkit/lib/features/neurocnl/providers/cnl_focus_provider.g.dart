// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cnl_focus_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider that holds the current CNL editor ↔ canvas focus signal.
///
/// Setting one direction clears the other to prevent stale highlights.
/// Both setters are idempotent — calling with the same value is a no-op.

@ProviderFor(CnlFocusNotifier)
final cnlFocusProvider = CnlFocusNotifierProvider._();

/// Provider that holds the current CNL editor ↔ canvas focus signal.
///
/// Setting one direction clears the other to prevent stale highlights.
/// Both setters are idempotent — calling with the same value is a no-op.
final class CnlFocusNotifierProvider
    extends $NotifierProvider<CnlFocusNotifier, CnlFocusState> {
  /// Provider that holds the current CNL editor ↔ canvas focus signal.
  ///
  /// Setting one direction clears the other to prevent stale highlights.
  /// Both setters are idempotent — calling with the same value is a no-op.
  CnlFocusNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cnlFocusProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cnlFocusNotifierHash();

  @$internal
  @override
  CnlFocusNotifier create() => CnlFocusNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CnlFocusState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CnlFocusState>(value),
    );
  }
}

String _$cnlFocusNotifierHash() => r'fbc06ca8a7ee8e68e7da6efe52d9152c446f3556';

/// Provider that holds the current CNL editor ↔ canvas focus signal.
///
/// Setting one direction clears the other to prevent stale highlights.
/// Both setters are idempotent — calling with the same value is a no-op.

abstract class _$CnlFocusNotifier extends $Notifier<CnlFocusState> {
  CnlFocusState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CnlFocusState, CnlFocusState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CnlFocusState, CnlFocusState>,
              CnlFocusState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
