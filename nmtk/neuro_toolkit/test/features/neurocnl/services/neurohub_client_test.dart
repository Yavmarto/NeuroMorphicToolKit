import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurohub_client.dart';

void main() {
  group('NeurohubClient', () {
    test('throws a clear error when NEUROHUB_API_URL is unset', () async {
      final client = NeurohubClient(
        baseUrl: '',
        httpClient: MockClient((request) async {
          fail('Unexpected request: ${request.method} ${request.url}');
        }),
      );

      await expectLater(
        () => client.listWorkspaces(),
        throwsA(
          isA<NeurohubException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
    });

    test(
      'listWorkspaces sends the bearer token and decodes summaries',
      () async {
        final client = NeurohubClient(
          baseUrl: 'http://test',
          accessToken: 'gh-token',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/neurohub/workspaces');
            expect(request.headers['Authorization'], 'Bearer gh-token');
            return http.Response(
              jsonEncode([
                {
                  'owner': 'alice',
                  'slug': 'mnist-akida',
                  'display_name': 'MNIST Akida',
                  'description': '',
                  'tags': ['mnist'],
                  'private': true,
                  'archived': false,
                  'updated_at': '2026-08-18T00:00:00Z',
                  'head_commit': 'commit-1',
                  'repository_url': 'https://github.com/alice/mnist-akida',
                  'permission': 'admin',
                  'neurohub_uri':
                      'neurohub://studio_workspace/alice/mnist-akida',
                },
              ]),
              200,
            );
          }),
        );

        final workspaces = await client.listWorkspaces();
        expect(workspaces, hasLength(1));
        expect(workspaces.single.slug, 'mnist-akida');
        expect(workspaces.single.permission, 'admin');
      },
    );

    test(
      'updateWorkspace surfaces a stable conflict exception on 409',
      () async {
        final client = NeurohubClient(
          baseUrl: 'http://test',
          accessToken: 'gh-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'PUT');
            return http.Response(
              jsonEncode({
                'detail': {
                  'code': 'workspace_conflict',
                  'base_commit': 'commit-1',
                  'remote_commit': 'commit-2',
                  'recovery': ['reload', 'save_copy', 'resolve'],
                },
              }),
              409,
            );
          }),
        );

        await expectLater(
          () => client.updateWorkspace(
            'alice',
            'mnist-akida',
            baseCommit: 'commit-1',
            workspace: const {'revision': 2},
          ),
          throwsA(
            isA<NeurohubConflictException>()
                .having((e) => e.baseCommit, 'baseCommit', 'commit-1')
                .having((e) => e.remoteCommit, 'remoteCommit', 'commit-2')
                .having((e) => e.recovery, 'recovery', [
                  'reload',
                  'save_copy',
                  'resolve',
                ]),
          ),
        );
      },
    );

    test(
      'device flow start and poll round-trip through Neurohub, not GitHub directly',
      () async {
        final client = NeurohubClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            expect(request.url.host, 'test');
            if (request.url.path == '/api/neurohub/oauth/device/start') {
              return http.Response(
                jsonEncode({
                  'session_id': 'sess-1',
                  'user_code': 'ABCD-1234',
                  'verification_uri': 'https://github.com/login/device',
                  'expires_in': 900,
                  'interval': 5,
                }),
                200,
              );
            }
            if (request.url.path == '/api/neurohub/oauth/device/poll') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body['session_id'], 'sess-1');
              return http.Response(
                jsonEncode({'status': 'success', 'access_token': 'gh-token'}),
                200,
              );
            }
            fail('Unexpected request: ${request.method} ${request.url}');
          }),
        );

        final started = await client.startDeviceAuthorization();
        expect(started.userCode, 'ABCD-1234');

        final polled = await client.pollDeviceAuthorization(started.sessionId);
        expect(polled.isSuccess, isTrue);
        expect(polled.accessToken, 'gh-token');
      },
    );
  });
}
