import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';

/// Resolves free-form text (e.g. from stylus handwriting recognition) to a
/// [NirNodeType] from [registry]. Tries, in order: exact id match (with or
/// without an `nir.`/`cnl.` prefix), exact display-name match, display-name
/// prefix match, display-name substring match, then a bounded fuzzy
/// (Levenshtein) match to tolerate handwriting-recognition typos. Returns
/// `null` when nothing matches closely enough.
NirNodeType? resolveNirNodeType(
  String rawInput,
  Map<String, NirNodeType> registry,
) {
  final String query = rawInput.trim().toLowerCase();
  if (query.isEmpty) return null;

  for (final NirNodeType type in registry.values) {
    final String idLower = type.id.toLowerCase();
    if (idLower == query ||
        idLower == 'nir.$query' ||
        idLower == 'cnl.$query') {
      return type;
    }
    if (type.displayName.toLowerCase() == query) {
      return type;
    }
  }

  for (final NirNodeType type in registry.values) {
    if (type.displayName.toLowerCase().startsWith(query)) {
      return type;
    }
  }

  for (final NirNodeType type in registry.values) {
    if (type.displayName.toLowerCase().contains(query)) {
      return type;
    }
  }

  NirNodeType? best;
  int bestDistance = 3;
  for (final NirNodeType type in registry.values) {
    final int distance = _levenshtein(query, type.displayName.toLowerCase());
    if (distance < bestDistance) {
      bestDistance = distance;
      best = type;
    }
  }
  return best;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  List<int> previousRow = List<int>.generate(b.length + 1, (i) => i);
  List<int> currentRow = List<int>.filled(b.length + 1, 0);

  for (int i = 0; i < a.length; i++) {
    currentRow[0] = i + 1;
    for (int j = 0; j < b.length; j++) {
      final int cost = a[i] == b[j] ? 0 : 1;
      currentRow[j + 1] = [
        previousRow[j + 1] + 1, // deletion
        currentRow[j] + 1, // insertion
        previousRow[j] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);
    }
    final List<int> tmp = previousRow;
    previousRow = currentRow;
    currentRow = tmp;
  }

  return previousRow[b.length];
}
