import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/akida_deploy_service.dart';

void main() {
  group('AkidaDeployService.resolveNeurochipBaseUrl', () {
    test('prefers an explicit Neurochip base URL override', () {
      final resolved = AkidaDeployService.resolveNeurochipBaseUrl(
        explicitBaseUrl: 'http://10.0.0.8:9000/',
        controlApiBaseUrl: 'http://10.0.0.7:8090',
      );

      expect(resolved, 'http://10.0.0.8:9000');
    });

    test('derives the Neurochip base URL from the control API host', () {
      final resolved = AkidaDeployService.resolveNeurochipBaseUrl(
        controlApiBaseUrl: 'https://akida-host.example.com:8090/launcher',
      );

      expect(resolved, 'https://akida-host.example.com:8002');
    });

    test('falls back to localhost when no remote host is configured', () {
      final resolved = AkidaDeployService.resolveNeurochipBaseUrl();

      expect(resolved, 'http://localhost:8002');
    });
  });
}
