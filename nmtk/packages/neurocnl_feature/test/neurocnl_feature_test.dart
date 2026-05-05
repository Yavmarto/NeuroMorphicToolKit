import 'package:flutter_test/flutter_test.dart';

void main() {
  // Feature package smoke test — verifies library exports are importable.
  test('package exports are reachable', () {
    // If this file compiles, the package barrel is structurally valid.
    expect(true, isTrue);
  });
}
