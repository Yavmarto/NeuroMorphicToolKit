import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_suggestions.dart' show levenshteinDistance;

/// Ranked "what node did the user mean" lookup, shared by every canvas.
///
/// The Architecture canvas's stylus handwriting-to-node used to own this
/// ranking privately (over `NirNodeType`s), so the Train/Eval canvases — which
/// have their own node-type enum — could not offer handwriting at all. The
/// ranking is now generic over the candidate type; callers supply how to read
/// a candidate's id and display name.
///
/// Four phases, in priority order, each contributing only candidates an
/// earlier phase didn't:
///
/// 1. **Exact** — id or display name equals the normalised input.
/// 2. **Prefix** — display name starts with the input.
/// 3. **Substring** — display name contains the input anywhere.
/// 4. **Fuzzy** — Levenshtein distance to the display name ≤ [maxDistance]
///    (4 by default: enough to absorb handwriting-OCR errors such as
///    `"LI F"` → `"LIF"` or `"Sinaps"` → `"Synapse"`), closest first.
///
/// [idPrefixes] are namespace prefixes an id may carry that the user would
/// never write by hand (`nir.`, `cnl.`), so `"lif"` still matches `nir.LIF`.
///
/// Returns an empty list for blank input.
List<T> suggestCanvasNodeTypes<T>(
  String input,
  Iterable<T> candidates, {
  required String Function(T) idOf,
  required String Function(T) nameOf,
  List<String> idPrefixes = const <String>[],
  int max = 5,
  int maxDistance = 4,
}) {
  final String query = input.trim().toLowerCase();
  if (query.isEmpty) return <T>[];

  final Set<String> seen = <String>{};
  final List<T> results = <T>[];

  void add(T candidate) {
    if (seen.add(idOf(candidate)) && results.length < max) {
      results.add(candidate);
    }
  }

  // Phase 1 — exact match on id (with or without a namespace prefix) or name
  for (final T c in candidates) {
    if (results.length >= max) break;
    final String id = idOf(c).toLowerCase();
    final bool prefixed = idPrefixes.any(
      (String p) => id == '${p.toLowerCase()}$query',
    );
    if (id == query || prefixed || nameOf(c).toLowerCase() == query) {
      add(c);
    }
  }

  // Phase 2 — prefix match on display name
  for (final T c in candidates) {
    if (results.length >= max) break;
    if (nameOf(c).toLowerCase().startsWith(query)) add(c);
  }

  // Phase 3 — substring match on display name
  for (final T c in candidates) {
    if (results.length >= max) break;
    if (nameOf(c).toLowerCase().contains(query)) add(c);
  }

  // Phase 4 — fuzzy match, closest first
  final List<({T candidate, int distance})> fuzzy =
      <({T candidate, int distance})>[];
  for (final T c in candidates) {
    if (seen.contains(idOf(c))) continue;
    final int d = levenshteinDistance(query, nameOf(c).toLowerCase());
    if (d <= maxDistance) fuzzy.add((candidate: c, distance: d));
  }
  fuzzy.sort(
    (({T candidate, int distance}) a, ({T candidate, int distance}) b) =>
        a.distance.compareTo(b.distance),
  );
  for (final ({T candidate, int distance}) entry in fuzzy) {
    if (results.length >= max) break;
    add(entry.candidate);
  }

  return results;
}

/// Candidate pipeline (Train / Eval) node types for handwritten [input].
List<PipelineDagNodeType> suggestPipelineNodeTypes(
  String input, {
  int max = 5,
}) => suggestCanvasNodeTypes<PipelineDagNodeType>(
  input,
  PipelineDagNodeType.values,
  idOf: (PipelineDagNodeType t) => t.name,
  nameOf: (PipelineDagNodeType t) => t.label,
  max: max,
);

/// Resolves handwritten [input] to a single pipeline node type, or null when
/// nothing plausible matches. Mirrors `resolveNirNodeType` for the
/// Architecture canvas.
PipelineDagNodeType? resolvePipelineNodeType(String input) {
  final List<PipelineDagNodeType> matches = suggestPipelineNodeTypes(
    input,
    max: 1,
  );
  return matches.isEmpty ? null : matches.first;
}
