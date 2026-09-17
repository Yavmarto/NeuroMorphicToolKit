// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cnl_import_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ImportedCnlSpecController)
final importedCnlSpecControllerProvider = ImportedCnlSpecControllerProvider._();

final class ImportedCnlSpecControllerProvider
    extends $NotifierProvider<ImportedCnlSpecController, ImportedCnlSpec?> {
  ImportedCnlSpecControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importedCnlSpecControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importedCnlSpecControllerHash();

  @$internal
  @override
  ImportedCnlSpecController create() => ImportedCnlSpecController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportedCnlSpec? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportedCnlSpec?>(value),
    );
  }
}

String _$importedCnlSpecControllerHash() =>
    r'0098c947d5d03f72f62dbc1a296404607e7e2eaf';

abstract class _$ImportedCnlSpecController extends $Notifier<ImportedCnlSpec?> {
  ImportedCnlSpec? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ImportedCnlSpec?, ImportedCnlSpec?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ImportedCnlSpec?, ImportedCnlSpec?>,
              ImportedCnlSpec?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
