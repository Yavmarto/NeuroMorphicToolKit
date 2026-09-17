import 'package:neuro_toolkit/features/neurocnl/utils/nir_node_type_suggestions.dart';

/// Score returned by [canvasPaletteMatchScore] when a candidate does not match
/// the query at all.
const int kCanvasPaletteNoMatch = -1;

/// Ranks one palette candidate against a search [query]. Lower is better;
/// [kCanvasPaletteNoMatch] means "hide this candidate".
///
/// Phases mirror [suggestNirNodeTypes] so the bottom-bar palettes, the
/// port-anchored connect palette and the stylus handwriting suggestions all
/// agree on what "a better match" means:
///
/// 0. exact label match
/// 1. label starts with the query
/// 2. label contains the query
/// 3. one of [keywords] contains the query — this is what makes a port-id
///    query like `spikes` surface nodes whose *label* says nothing about spikes
/// 4+ fuzzy: `4 + levenshtein`, capped by [maxDistance]
///
/// A blank query matches everything at score 0, so callers can pass the raw
/// field text without special-casing the empty state.
int canvasPaletteMatchScore({
  required String query,
  required String label,
  Iterable<String> keywords = const <String>[],
  int maxDistance = 3,
}) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;

  final String labelLower = label.toLowerCase();
  if (labelLower == q) return 0;
  if (labelLower.startsWith(q)) return 1;
  if (labelLower.contains(q)) return 2;

  for (final String keyword in keywords) {
    if (keyword.toLowerCase().contains(q)) return 3;
  }

  // Fuzzy only against the label. Running it over keywords too would let a
  // three-character typo match almost any node via some port id.
  final int distance = levenshteinDistance(q, labelLower);
  if (distance <= maxDistance) return 4 + distance;

  return kCanvasPaletteNoMatch;
}

/// Filters and ranks [items] for [query], best match first.
///
/// Ties keep their original order — the palettes present node types in a
/// deliberate, category-grouped sequence and an unstable sort would scramble it
/// the moment the user typed a single character.
List<T> filterCanvasPaletteItems<T>(
  Iterable<T> items,
  String query, {
  required String Function(T item) label,
  Iterable<String> Function(T item)? keywords,
}) {
  final String q = query.trim();
  if (q.isEmpty) return items.toList();

  final scored = <({T item, int score, int index})>[];
  int index = 0;
  for (final T item in items) {
    final int score = canvasPaletteMatchScore(
      query: q,
      label: label(item),
      keywords: keywords?.call(item) ?? const <String>[],
    );
    if (score != kCanvasPaletteNoMatch) {
      scored.add((item: item, score: score, index: index));
    }
    index += 1;
  }

  scored.sort((a, b) {
    final int byScore = a.score.compareTo(b.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });

  return scored.map((e) => e.item).toList();
}
