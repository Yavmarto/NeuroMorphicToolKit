library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReviewCompareModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
