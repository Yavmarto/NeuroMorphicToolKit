import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';

void main() {
  group('ServerConfigController mobile address helpers', () {
    test('isReachableHealthStatus accepts degraded health responses', () {
      expect(ServerConfigController.isReachableHealthStatus(200), isTrue);
      expect(ServerConfigController.isReachableHealthStatus(503), isTrue);
      expect(ServerConfigController.isReachableHealthStatus(500), isFalse);
    });
  });
}
