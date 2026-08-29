import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_node_suggestions.dart';

/// Returns up to [max] candidate [NirNodeType]s from [registry] that are
/// plausible completions for [input].
///
/// A thin wrapper over the canvas-wide [suggestCanvasNodeTypes] ranking — the
/// same one the Train/Eval canvases use — so handwriting recognition behaves
/// identically on every canvas.
List<NirNodeType> suggestNirNodeTypes(
  String input,
  Map<String, NirNodeType> registry, {
  int max = 5,
  int maxDistance = 4,
}) => suggestCanvasNodeTypes<NirNodeType>(
  input,
  registry.values,
  idOf: (NirNodeType t) => t.id,
  nameOf: (NirNodeType t) => t.displayName,
  idPrefixes: const <String>['nir.', 'cnl.'],
  max: max,
  maxDistance: maxDistance,
);

/// Levenshtein edit distance between [a] and [b].
///
/// Public because the canvas palette search
/// (`utils/canvas_palette_search.dart`) ranks with the same fuzzy phase and
/// must not carry a second copy of this.
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> prev = List<int>.generate(b.length + 1, (int i) => i);
  List<int> curr = List<int>.filled(b.length + 1, 0);

  for (int i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final int cost = a[i] == b[j] ? 0 : 1;
      curr[j + 1] = <int>[
        prev[j + 1] + 1, // deletion
        curr[j] + 1, // insertion
        prev[j] + cost, // substitution
      ].reduce((int x, int y) => x < y ? x : y);
    }
    final List<int> tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}
