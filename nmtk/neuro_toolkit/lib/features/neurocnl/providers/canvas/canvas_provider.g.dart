// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'canvas_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CanvasController)
final canvasControllerProvider = CanvasControllerProvider._();

final class CanvasControllerProvider
    extends $NotifierProvider<CanvasController, CanvasState> {
  CanvasControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'canvasControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$canvasControllerHash();

  @$internal
  @override
  CanvasController create() => CanvasController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CanvasState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CanvasState>(value),
    );
  }
}

String _$canvasControllerHash() => r'035e7c94a95958d73fe8d837bce0f1a3f59270e6';

abstract class _$CanvasController extends $Notifier<CanvasState> {
  CanvasState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<CanvasState, CanvasState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<CanvasState, CanvasState>,
              CanvasState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
