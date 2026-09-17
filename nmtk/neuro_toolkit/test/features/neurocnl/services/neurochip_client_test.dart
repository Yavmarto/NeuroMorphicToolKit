import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurochip_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NeurochipClient configuration', () {
    test('uses the root-selected suite origin for the Neurochip proxy', () {
      final api = NeurochipClient(
        baseUrl: 'http://example.test:9000/api/neurocnl',
      );

      expect(api.baseUrl, 'http://example.test:9000');
    });

    test('keeps the root-selected origin without choosing a port', () {
      final api = NeurochipClient(baseUrl: 'http://example.test:8000/api');

      expect(api.baseUrl, 'http://example.test:8000');
    });
  });

  group('NeurochipClient.getSerialPorts', () {
    test('parses bare list payloads', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/neurochip/serial/ports');
        return http.Response(
          jsonEncode([
            {
              'port': '/dev/cu.usbmodem1',
              'description': 'Teensy',
              'is_teensy': true,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = NeurochipClient(baseUrl: 'http://test', httpClient: client);
      final ports = await api.getSerialPorts();

      expect(ports, hasLength(1));
      expect(ports.first['port'], '/dev/cu.usbmodem1');
    });

    test('parses wrapped payloads for compatibility', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'ports': [
              {
                'port': '/dev/cu.usbmodem2',
                'description': 'Fallback',
                'is_teensy': false,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = NeurochipClient(baseUrl: 'http://test', httpClient: client);
      final ports = await api.getSerialPorts();

      expect(ports, hasLength(1));
      expect(ports.first['port'], '/dev/cu.usbmodem2');
    });
  });
}
