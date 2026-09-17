library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReviewCompareTargetsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void set(Set<String> value) => state = value;
}
