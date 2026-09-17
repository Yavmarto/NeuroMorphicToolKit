import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurohub_frontend/neurohub_frontend.dart';

class _MemoryTokenStorage implements GithubTokenStorage {
  String? token;

  @override
  Future<void> delete() async => token = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;
}

class _LinkLauncher implements GithubLinkLauncher {
  String? opened;

  @override
  Future<bool> open(String url) async {
    opened = url;
    return true;
  }
}

http.Response _config() => http.Response(
  jsonEncode(<String, dynamic>{
    'client_id': 'public-client',
    'scopes': <String>['repo', 'read:user'],
  }),
  200,
);

http.Response _started() => http.Response(
  jsonEncode(<String, dynamic>{
    'session_id': 'sess-1',
    'user_code': 'ABCD-1234',
    'verification_uri': 'https://github.com/login/device',
    'expires_in': 900,
    'interval': 1,
  }),
  200,
);

http.Response _poll(String status, {String? accessToken, int? interval}) =>
    http.Response(
      jsonEncode(<String, dynamic>{
        'status': status,
        'access_token': ?accessToken,
        'interval': ?interval,
      }),
      200,
    );

/// Builds the screen with an HTTP layer backed by [handler]. Returns the
/// storage, link launcher, and recorded token so tests can assert on them.
Future<void> _pump(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  _MemoryTokenStorage? storage,
  _LinkLauncher? launcher,
  List<String>? connectedTokens,
}) async {
  // Clipboard access goes through a platform channel that never resolves in
  // the test environment unless mocked.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async => null,
  );
  final client = GithubDeviceFlowClient(
    baseUrl: 'http://test',
    httpClient: MockClient(handler),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: GithubConnectScreen(
        client: client,
        tokenStorage: storage ?? _MemoryTokenStorage(),
        linkLauncher: launcher ?? _LinkLauncher(),
        onConnected: connectedTokens == null
            ? null
            : (token) => connectedTokens.add(token),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows user code and verification URL after starting the flow', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage();
    final launcher = _LinkLauncher();
    await _pump(
      tester,
      (request) async {
        if (request.url.path.endsWith('/oauth/device/start')) {
          return _started();
        }
        if (request.url.path.endsWith('/oauth/device/poll')) {
          return _poll('success', accessToken: 'signed-in-token');
        }
        return _config();
      },
      storage: storage,
      launcher: launcher,
    );

    expect(find.text('Connect GitHub'), findsOneWidget);
    expect(find.text('ABCD-1234'), findsOneWidget);
    expect(find.textContaining('github.com/login/device'), findsOneWidget);
    expect(find.text('15:00 remaining'), findsOneWidget);

    await tester.tap(find.byKey(const Key('github-copy-code')));
    await tester.pump();
    expect(find.text('Sign-in code copied.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('github-open-link')));
    await tester.pump();
    expect(launcher.opened, 'https://github.com/login/device');

    // Let the flow complete so the countdown timer is cancelled.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(storage.token, 'signed-in-token');
  });

  testWidgets(
    'polls the poll endpoint and transitions to the connected state',
    (tester) async {
      final storage = _MemoryTokenStorage();
      final connectedTokens = <String>[];
      var polls = 0;
      await _pump(
        tester,
        (request) async {
          if (request.url.path.endsWith('/oauth/device/start')) {
            return _started();
          }
          if (request.url.path.endsWith('/oauth/device/poll')) {
            polls++;
            if (polls == 1) {
              return _poll('pending', interval: 1);
            }
            return _poll('success', accessToken: 'signed-in-token');
          }
          return _config();
        },
        storage: storage,
        connectedTokens: connectedTokens,
      );

      expect(
        find.text('Waiting for you to finish in the browser…'),
        findsOneWidget,
      );

      // First poll is still pending; the screen keeps waiting.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        find.text('Waiting for you to finish in the browser…'),
        findsOneWidget,
      );
      expect(storage.token, isNull);

      // Second poll succeeds and persists the token.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(polls, 2);
      expect(storage.token, 'signed-in-token');
      expect(connectedTokens, <String>['signed-in-token']);
      expect(find.byKey(const Key('github-connected')), findsOneWidget);
      expect(find.text('Connected to GitHub'), findsOneWidget);
    },
  );

  testWidgets('stops polling and reports when the code expires', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage();
    var polls = 0;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/oauth/device/start')) {
        return _started();
      }
      if (request.url.path.endsWith('/oauth/device/poll')) {
        polls++;
        return _poll('expired');
      }
      return _config();
    }, storage: storage);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(polls, 1);
    expect(
      find.text('This code expired. Request a new code to continue.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('github-connect-error')), findsOneWidget);
    expect(find.byKey(const Key('github-new-code')), findsOneWidget);
    expect(find.byKey(const Key('github-connected')), findsNothing);
    expect(storage.token, isNull);

    // No further polls fire after the terminal state.
    await tester.pump(const Duration(seconds: 1));
    expect(polls, 1);
  });

  testWidgets('stops polling and reports when the request is denied', (
    tester,
  ) async {
    var polls = 0;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/oauth/device/start')) {
        return _started();
      }
      if (request.url.path.endsWith('/oauth/device/poll')) {
        polls++;
        return _poll('denied');
      }
      return _config();
    });

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(polls, 1);
    expect(
      find.text(
        'Sign-in was cancelled. Request a new code when you are ready.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('github-connected')), findsNothing);
  });

  testWidgets('shows an actionable error when the provider is unconfigured', (
    tester,
  ) async {
    await _pump(
      tester,
      (request) async => http.Response(
        jsonEncode(<String, String>{
          'detail':
              'Neurohub sign-in is not configured. '
              'The operator must set GITHUB_OAUTH_CLIENT_ID.',
        }),
        503,
      ),
    );

    await tester.pump();
    expect(
      find.textContaining('Neurohub sign-in is not configured'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('github-new-code')), findsOneWidget);
  });

  testWidgets('disconnect deletes the stored token', (tester) async {
    final storage = _MemoryTokenStorage();
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/oauth/device/start')) {
        return _started();
      }
      if (request.url.path.endsWith('/oauth/device/poll')) {
        return _poll('success', accessToken: 'signed-in-token');
      }
      return _config();
    }, storage: storage);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(storage.token, 'signed-in-token');
    expect(find.byKey(const Key('github-connected')), findsOneWidget);

    await tester.tap(find.byKey(const Key('github-disconnect')));
    await tester.pump();
    expect(storage.token, isNull);
    expect(find.byKey(const Key('github-connected')), findsNothing);
    expect(find.text('Connect GitHub'), findsOneWidget);
  });
}
