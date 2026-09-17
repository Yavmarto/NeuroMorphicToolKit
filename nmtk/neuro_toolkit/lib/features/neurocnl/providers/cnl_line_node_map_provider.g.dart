// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cnl_line_node_map_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Derived mapping between CNL line numbers and canvas node IDs.
///
/// Built by joining [pipelineProvider]'s parsed sentences against
/// [canvasProvider]'s nodes using a case-insensitive label/name match.
/// Recomputed automatically by Riverpod whenever either source changes.
///
/// **Match priority** (first hit wins per node):
///   1. `CanvasNode.label`
///   2. `CanvasNode.parameters['name']`
///   3. `CanvasNode.id`
///
/// Cost: O(sentences + nodes) per update — negligible for typical CNL
/// documents (<200 lines).

@ProviderFor(cnlLineNodeMap)
final cnlLineNodeMapProvider = CnlLineNodeMapProvider._();

/// Derived mapping between CNL line numbers and canvas node IDs.
///
/// Built by joining [pipelineProvider]'s parsed sentences against
/// [canvasProvider]'s nodes using a case-insensitive label/name match.
/// Recomputed automatically by Riverpod whenever either source changes.
///
/// **Match priority** (first hit wins per node):
///   1. `CanvasNode.label`
///   2. `CanvasNode.parameters['name']`
///   3. `CanvasNode.id`
///
/// Cost: O(sentences + nodes) per update — negligible for typical CNL
/// documents (<200 lines).

final class CnlLineNodeMapProvider
    extends
        $FunctionalProvider<
          ({Map<int, String> lineToNode, Map<String, int> nodeToLine}),
          ({Map<int, String> lineToNode, Map<String, int> nodeToLine}),
          ({Map<int, String> lineToNode, Map<String, int> nodeToLine})
        >
    with
        $Provider<
          ({Map<int, String> lineToNode, Map<String, int> nodeToLine})
        > {
  /// Derived mapping between CNL line numbers and canvas node IDs.
  ///
  /// Built by joining [pipelineProvider]'s parsed sentences against
  /// [canvasProvider]'s nodes using a case-insensitive label/name match.
  /// Recomputed automatically by Riverpod whenever either source changes.
  ///
  /// **Match priority** (first hit wins per node):
  ///   1. `CanvasNode.label`
  ///   2. `CanvasNode.parameters['name']`
  ///   3. `CanvasNode.id`
  ///
  /// Cost: O(sentences + nodes) per update — negligible for typical CNL
  /// documents (<200 lines).
  CnlLineNodeMapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cnlLineNodeMapProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cnlLineNodeMapHash();

  @$internal
  @override
  $ProviderElement<({Map<int, String> lineToNode, Map<String, int> nodeToLine})>
  $createElement($ProviderPointer pointer) => $ProviderElement(pointer);

  @override
  ({Map<int, String> lineToNode, Map<String, int> nodeToLine}) create(Ref ref) {
    return cnlLineNodeMap(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(
    ({Map<int, String> lineToNode, Map<String, int> nodeToLine}) value,
  ) {
    return $ProviderOverride(
      origin: this,
      providerOverride:
          $SyncValueProvider<
            ({Map<int, String> lineToNode, Map<String, int> nodeToLine})
          >(value),
    );
  }
}

String _$cnlLineNodeMapHash() => r'b311e9fa12db9fbec16f31eadfc62a981778167b';
