import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/features/server/shared/target_store.dart';

void main() {
  test('login posts username/password and returns a session', () async {
    Uri? requestedUri;
    Map<String, dynamic>? requestedBody;
    final client = MockClient((request) async {
      requestedUri = request.url;
      requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'token': 'session-token-1', 'username': 'ada'}),
        200,
      );
    });

    final session = await ConnectService(
      httpClient: client,
    ).login(host: '203.0.113.90', username: 'ada', credential: 'hunter2');

    expect(
      requestedUri.toString(),
      'http://203.0.113.90:8090/api/launcher/auth/login',
    );
    expect(requestedBody, {'username': 'ada', 'password': 'hunter2'});
    expect(session.host, '203.0.113.90');
    expect(session.username, 'ada');
    expect(session.sessionToken, 'session-token-1');
  });

  test('login throws ConnectException on wrong credentials', () async {
    final client = MockClient((request) async => http.Response('', 401));
    expect(
      () => ConnectService(
        httpClient: client,
      ).login(host: '203.0.113.90', username: 'ada', credential: 'wrong'),
      throwsA(isA<ConnectException>()),
    );
  });

  test('login throws ConnectException when unreachable', () async {
    final client = MockClient((request) async => throw Exception('refused'));
    expect(
      () => ConnectService(
        httpClient: client,
      ).login(host: '203.0.113.90', username: 'ada', credential: 'hunter2'),
      throwsA(isA<ConnectException>()),
    );
  });

  test('login throws ConnectException on a malformed response', () async {
    final client = MockClient(
      (request) async => http.Response('not json', 200),
    );
    expect(
      () => ConnectService(
        httpClient: client,
      ).login(host: '203.0.113.90', username: 'ada', credential: 'hunter2'),
      throwsA(isA<ConnectException>()),
    );
  });

  test('reconnect re-logs in with the saved app credential', () async {
    Map<String, dynamic>? requestedBody;
    final client = MockClient((request) async {
      requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'token': 'session-token-2'}), 200);
    });

    final session = await ConnectService(httpClient: client).reconnect(
      const ConnectTarget(
        host: '203.0.113.90',
        appUsername: 'ada',
        sessionToken: 'session-token-1',
        credential: 'hunter2',
      ),
    );

    expect(requestedBody, {'username': 'ada', 'password': 'hunter2'});
    expect(session.sessionToken, 'session-token-2');
  });

  test('reconnect throws without a saved credential', () async {
    final client = MockClient((request) async => http.Response('', 200));
    expect(
      () => ConnectService(httpClient: client).reconnect(
        const ConnectTarget(
          host: '203.0.113.90',
          appUsername: 'ada',
          sessionToken: 'session-token-1',
        ),
      ),
      throwsA(isA<ConnectException>()),
    );
  });

  test('probe reports liveness from the /health endpoint', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/health');
      return http.Response('{"status":"ok"}', 200);
    });
    final service = ConnectService(httpClient: client);
    expect(await service.probe(host: '203.0.113.90'), isTrue);
  });

  test('probe reports unreachable hosts as not alive', () async {
    final client = MockClient((request) async => throw Exception('refused'));
    final service = ConnectService(httpClient: client);
    expect(await service.probe(host: '203.0.113.90'), isFalse);
  });
}
