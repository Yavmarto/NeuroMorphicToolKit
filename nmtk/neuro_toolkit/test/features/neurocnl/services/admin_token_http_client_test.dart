import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/features/neurocnl/services/admin_token_http_client.dart';

void main() {
  group('AdminTokenHttpClient', () {
    test(
      'a successful request reports recovery and clears the stale banner',
      () async {
        var recovered = 0;
        final errors = <NmtkFeatureErrorKind>[];
        final client = AdminTokenHttpClient(
          adminToken: 'token',
          onReportError: (event) async => errors.add(event.kind),
          onRecovered: () async => recovered++,
          inner: MockClient((request) async => http.Response('{}', 200)),
        );
        addTearDown(client.close);

        final response = await client.get(Uri.parse('http://localhost/health'));

        expect(response.statusCode, 200);
        expect(recovered, 1);
        expect(errors, isEmpty);
      },
    );

    test('the admin token header is attached to every request', () async {
      http.Request? seen;
      final client = AdminTokenHttpClient(
        adminToken: 'secret',
        onReportError: (event) async {},
        onRecovered: () async {},
        inner: MockClient((request) async {
          seen = request;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);

      await client.get(Uri.parse('http://localhost/health'));

      expect(seen!.headers['X-NMTK-Admin-Token'], 'secret');
    });

    test(
      'a 401 response reports an authentication error, not recovery',
      () async {
        var recovered = 0;
        final errors = <NmtkFeatureErrorKind>[];
        final client = AdminTokenHttpClient(
          adminToken: 'token',
          onReportError: (event) async => errors.add(event.kind),
          onRecovered: () async => recovered++,
          inner: MockClient(
            (request) async => http.Response(
              json.encode({'detail': 'unauthorized'}),
              401,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        addTearDown(client.close);

        final response = await client.get(
          Uri.parse('http://localhost/protected'),
        );

        expect(response.statusCode, 401);
        expect(errors, [NmtkFeatureErrorKind.authentication]);
        expect(recovered, 0);
      },
    );

    test(
      'a network failure reports a connection error, not recovery',
      () async {
        var recovered = 0;
        final errors = <NmtkFeatureErrorKind>[];
        final client = AdminTokenHttpClient(
          adminToken: 'token',
          onReportError: (event) async => errors.add(event.kind),
          onRecovered: () async => recovered++,
          inner: MockClient(
            (request) async => throw Exception('connection refused'),
          ),
        );
        addTearDown(client.close);

        await expectLater(
          client.get(Uri.parse('http://localhost/health')),
          throwsA(isA<Exception>()),
        );

        expect(errors, [NmtkFeatureErrorKind.connection]);
        expect(recovered, 0);
      },
    );
  });
}
