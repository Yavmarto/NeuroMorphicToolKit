import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

void main() {
  group('ApiClient.simulate', () {
    test('surfaces the deprecated NIR-only simulation error', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/simulate' && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'detail': {
                'error': 'nir_simulation_unsupported',
                'messages': [
                  'Simulation is no longer supported on the NIR-only NeuroCNL surface.',
                ],
              },
            }),
            410,
            headers: {'content-type': 'application/json'},
          );
        }

        fail('Unexpected request: ${request.method} ${request.url}');
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);

      await expectLater(
        () => api.simulate('spec'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 410)
              .having(
                (e) => e.body,
                'body',
                contains('nir_simulation_unsupported'),
              ),
        ),
      );
    });
  });

  group('ApiClient.generateNotebookV2', () {
    test('parses generated_at from the response', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/notebook/generate-v2' &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'workspace_folder': 'demo/notebooks',
              'notebooks': [
                {
                  'filename': 'pipeline_snntorch_sim.ipynb',
                  'target': 'snntorch_sim',
                },
              ],
              'jupyter_url': '',
              'generated_at': 1700000000.5,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);
      final result = await api.generateNotebookV2(
        spec: 'spec',
        pipelineConfig: const {'framework': 'snntorch_sim'},
      );

      expect(result.generatedAt, 1700000000.5);
      expect(result.workspaceFolder, 'demo/notebooks');
      expect(result.notebookFilenames, ['pipeline_snntorch_sim.ipynb']);
    });

    test('defaults generated_at to 0 when absent (older backend)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'workspace_folder': 'demo/notebooks',
            'notebooks': [
              {'filename': 'pipeline_nengo.ipynb', 'target': 'nengo'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);
      final result = await api.generateNotebookV2(
        spec: 'spec',
        pipelineConfig: const {'framework': 'nengo'},
      );

      expect(result.generatedAt, 0);
    });
  });

  group('ApiClient.getNotebookLastModified', () {
    test('returns the last_modified value from the response', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/notebook/last-modified');
        expect(
          request.url.queryParameters['workspace_folder'],
          'demo/notebooks',
        );
        expect(
          request.url.queryParameters['filename'],
          'pipeline_snntorch_sim.ipynb',
        );
        return http.Response(
          jsonEncode({'last_modified': 1700000005.0}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);
      final lastModified = await api.getNotebookLastModified(
        workspaceFolder: 'demo/notebooks',
        filename: 'pipeline_snntorch_sim.ipynb',
      );

      expect(lastModified, 1700000005.0);
    });

    test('returns null when the backend reports no last_modified', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'last_modified': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);
      final lastModified = await api.getNotebookLastModified(
        workspaceFolder: 'demo/notebooks',
        filename: 'missing.ipynb',
      );

      expect(lastModified, isNull);
    });
  });

  group('ApiClient.exportNirArtifact', () {
    test('returns raw bytes for binary nir responses', () async {
      final nirBytes = Uint8List.fromList(<int>[
        0x89,
        0x48,
        0x44,
        0x46,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/export');
        expect(request.headers['content-type'], 'application/json');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['format'], 'nir');
        return http.Response.bytes(
          nirBytes,
          200,
          headers: const <String, String>{
            'content-type': 'application/octet-stream',
          },
        );
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);

      final artifact = await api.exportNirArtifact('spec');

      expect(artifact.filename, 'network.nir');
      expect(artifact.mimeType, 'application/octet-stream');
      expect(artifact.textContent, isNull);
      expect(artifact.bytes, nirBytes);
    });
  });

  group('ApiClient.downloadDataset', () {
    test('polls beyond 30 seconds for long-running dataset job', () async {
      // The backend uses a 3600s job timeout; the client must not time out at
      // the old 30-second default. This test simulates a job that takes
      // longer than 30 s by returning pending until the 3rd poll, then done.
      var pollCount = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.endsWith('/download')) {
          return http.Response(
            jsonEncode({'job_id': 'job-slow-123'}),
            202,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/jobs/job-slow-123')) {
          pollCount += 1;
          if (pollCount < 3) {
            return http.Response(
              jsonEncode({
                'job_id': 'job-slow-123',
                'status': 'running',
                'result': null,
                'error': null,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'job_id': 'job-slow-123',
              'status': 'complete',
              'result': {
                'dataset_id': 'nmnist',
                'local_path': '/data/nmnist.h5',
                'downloaded_at': '2026-06-10T00:00:00Z',
                'sha256_verified': true,
              },
              'error': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);
      final result = await api.downloadDataset('nmnist');

      // Job completed on the 3rd poll — must not have timed out.
      expect(pollCount, 3);
      expect(result.localPath, '/data/nmnist.h5');
      expect(result.sha256Verified, isTrue);
    });

    test('surfaces clean error text from a failed dataset job', () async {
      final client = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.endsWith('/download')) {
          return http.Response(
            jsonEncode({'job_id': 'job-fail-456'}),
            202,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/jobs/job-fail-456')) {
          return http.Response(
            jsonEncode({
              'job_id': 'job-fail-456',
              'status': 'failed',
              'result': null,
              'error':
                  'Dataset file was not found in Firebase Storage. Check the live bucket contents and retry from Setup.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        fail('Unexpected request: ${request.method} ${request.url}');
      });

      final api = ApiClient(baseUrl: 'http://test', httpClient: client);

      await expectLater(
        () => api.downloadDataset('nmnist'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.body,
            'body',
            contains('Firebase Storage'),
          ),
        ),
      );
    });
  });

  group('NotebookGenerationResult.trainable', () {
    test('carries the backend trainability verdict and its reason', () {
      // The Run step skips execution on this: a notebook for a target with no
      // training adapter has no optimiser cell, and running it produced a
      // failure that read as the user's mistake.
      final result = NotebookGenerationResult.fromJson(<String, dynamic>{
        'workspace_folder': 'demo/notebooks',
        'notebooks': [
          {'filename': 'pipeline_akida.ipynb'},
        ],
        'trainable': false,
        'not_trainable_reason': 'akida has no Studio training adapter.',
      });

      expect(result.trainable, isFalse);
      expect(result.notTrainableReason, contains('no Studio training adapter'));
    });

    test('defaults to trainable when an older backend omits the field', () {
      // Absent must mean "run it", i.e. today's behaviour — otherwise pointing
      // the app at an older backend would silently stop training altogether.
      final result = NotebookGenerationResult.fromJson(<String, dynamic>{
        'workspace_folder': 'demo/notebooks',
        'notebooks': [
          {'filename': 'pipeline_snntorch_sim.ipynb'},
        ],
      });

      expect(result.trainable, isTrue);
      expect(result.notTrainableReason, isEmpty);
    });
  });
}
