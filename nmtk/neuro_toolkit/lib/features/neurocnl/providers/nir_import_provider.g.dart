// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nir_import_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(NirImportController)
final nirImportControllerProvider = NirImportControllerProvider._();

final class NirImportControllerProvider
    extends $NotifierProvider<NirImportController, NirImportState> {
  NirImportControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'nirImportControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$nirImportControllerHash();

  @$internal
  @override
  NirImportController create() => NirImportController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NirImportState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NirImportState>(value),
    );
  }
}

String _$nirImportControllerHash() =>
    r'78ab25a3e122faa76c1a0ecaa1148796a61ce6ff';

abstract class _$NirImportController extends $Notifier<NirImportState> {
  NirImportState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<NirImportState, NirImportState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NirImportState, NirImportState>,
              NirImportState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
