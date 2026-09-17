// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'template_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TemplateController)
final templateControllerProvider = TemplateControllerProvider._();

final class TemplateControllerProvider
    extends
        $NotifierProvider<TemplateController, AsyncValue<List<CnlTemplate>>> {
  TemplateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'templateControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$templateControllerHash();

  @$internal
  @override
  TemplateController create() => TemplateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<CnlTemplate>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<CnlTemplate>>>(
        value,
      ),
    );
  }
}

String _$templateControllerHash() =>
    r'10b042312b630a1991c7f6f3527fef57bcf650cb';

abstract class _$TemplateController
    extends $Notifier<AsyncValue<List<CnlTemplate>>> {
  AsyncValue<List<CnlTemplate>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<CnlTemplate>>,
              AsyncValue<List<CnlTemplate>>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<CnlTemplate>>,
                AsyncValue<List<CnlTemplate>>
              >,
              AsyncValue<List<CnlTemplate>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
