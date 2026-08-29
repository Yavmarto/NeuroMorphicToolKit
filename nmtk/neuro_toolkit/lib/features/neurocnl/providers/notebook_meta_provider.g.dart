// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notebook_meta_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(NotebookMeta)
final notebookMetaProvider = NotebookMetaProvider._();

final class NotebookMetaProvider
    extends
        $NotifierProvider<NotebookMeta, Map<String, NotebookGenerationMeta>> {
  NotebookMetaProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notebookMetaProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notebookMetaHash();

  @$internal
  @override
  NotebookMeta create() => NotebookMeta();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, NotebookGenerationMeta> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, NotebookGenerationMeta>>(
        value,
      ),
    );
  }
}

String _$notebookMetaHash() => r'd44089ad1bdded86fbfb740810e33ffae91abfa4';

abstract class _$NotebookMeta
    extends $Notifier<Map<String, NotebookGenerationMeta>> {
  Map<String, NotebookGenerationMeta> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, NotebookGenerationMeta>,
              Map<String, NotebookGenerationMeta>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, NotebookGenerationMeta>,
                Map<String, NotebookGenerationMeta>
              >,
              Map<String, NotebookGenerationMeta>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
