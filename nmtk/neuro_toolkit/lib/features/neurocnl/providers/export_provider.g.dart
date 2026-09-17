// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'export_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ExportController)
final exportControllerProvider = ExportControllerProvider._();

final class ExportControllerProvider
    extends $NotifierProvider<ExportController, ExportState> {
  ExportControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'exportControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$exportControllerHash();

  @$internal
  @override
  ExportController create() => ExportController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExportState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExportState>(value),
    );
  }
}

String _$exportControllerHash() => r'6592935435e2e776ddd6efa351cd692de1780386';

abstract class _$ExportController extends $Notifier<ExportState> {
  ExportState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ExportState, ExportState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ExportState, ExportState>,
              ExportState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
