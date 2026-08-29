import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'compare_selection_provider.g.dart';

/// Result IDs selected on the Results tab for multi-run comparison (max 2).
@riverpod
class CompareSelection extends _$CompareSelection {
  @override
  Set<String> build() => <String>{};

  void toggle(String resultId) {
    final current = Set<String>.from(state);
    if (current.contains(resultId)) {
      current.remove(resultId);
    } else {
      if (current.length >= 2) {
        final oldest = current.first;
        current.remove(oldest);
      }
      current.add(resultId);
    }
    state = current;
  }
}
