// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CurrentProjectController)
final currentProjectControllerProvider = CurrentProjectControllerProvider._();

final class CurrentProjectControllerProvider
    extends $NotifierProvider<CurrentProjectController, AsyncValue<Project?>> {
  CurrentProjectControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentProjectControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentProjectControllerHash();

  @$internal
  @override
  CurrentProjectController create() => CurrentProjectController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<Project?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<Project?>>(value),
    );
  }
}

String _$currentProjectControllerHash() =>
    r'd05ce4e4ea0eeb9dc0a2201c3633b1d4fdf3304f';

abstract class _$CurrentProjectController
    extends $Notifier<AsyncValue<Project?>> {
  AsyncValue<Project?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Project?>, AsyncValue<Project?>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Project?>, AsyncValue<Project?>>,
              AsyncValue<Project?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
