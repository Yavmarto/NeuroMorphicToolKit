// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CanvasSyncIssueController)
final canvasSyncIssueControllerProvider = CanvasSyncIssueControllerProvider._();

final class CanvasSyncIssueControllerProvider
    extends $NotifierProvider<CanvasSyncIssueController, CanvasSyncIssue?> {
  CanvasSyncIssueControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canvasSyncIssueControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canvasSyncIssueControllerHash();

  @$internal
  @override
  CanvasSyncIssueController create() => CanvasSyncIssueController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanvasSyncIssue? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CanvasSyncIssue?>(value),
    );
  }
}

String _$canvasSyncIssueControllerHash() =>
    r'bd2f1db0948bc95260ca32ab919dbd5cac1242bc';

abstract class _$CanvasSyncIssueController extends $Notifier<CanvasSyncIssue?> {
  CanvasSyncIssue? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CanvasSyncIssue?, CanvasSyncIssue?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CanvasSyncIssue?, CanvasSyncIssue?>,
              CanvasSyncIssue?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
