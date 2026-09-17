import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/dataset_generation_preparer.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfigService.initialize();
  });

  test(
    'uploads each unique client path once and rewrites only returned JSON',
    () async {
      final api = _FakeApiClient();
      var readCount = 0;
      final phases = PipelinePhases(
        train: PipelineDAG(
          nodes: <PipelineDagNode>[
            _loader(
              id: 'train-loader',
              path: '/local/mnist.pt',
              fileName: 'mnist.pt',
            ),
          ],
        ),
        eval: PipelineDAG(
          nodes: <PipelineDagNode>[
            _loader(
              id: 'test-loader',
              path: '/local/mnist.pt',
              fileName: 'mnist.pt',
              type: PipelineDagNodeType.testLoader,
            ),
          ],
        ),
      );

      final preparation = await DatasetGenerationPreparer(
        apiClient: api,
        readFile: (path) async {
          readCount += 1;
          expect(path, '/local/mnist.pt');
          return Uint8List.fromList(<int>[1, 2, 3]);
        },
      ).prepare(phases);
      final prepared = preparation.phases;

      expect(readCount, 1);
      expect(api.uploadedFilenames, <String>['mnist.pt']);
      expect(
        _parameters(prepared, 'train', 0)['dataset_path'],
        '/server/pipeline_uploads/1/mnist.pt',
      );
      expect(
        _parameters(prepared, 'eval', 0)['dataset_path'],
        '/server/pipeline_uploads/1/mnist.pt',
      );
      expect(
        _parameters(prepared, 'train', 0),
        isNot(contains(kDatasetPathScopeKey)),
      );
      expect(
        _parameters(prepared, 'train', 0),
        isNot(contains(kDatasetFileNameKey)),
      );
      expect(
        phases.train.nodes.single.parameters['dataset_path'],
        '/local/mnist.pt',
        reason:
            'generation preparation must not replace the persisted client path',
      );
      // The caller (run_step.dart/notebook_step.dart/notebook_generate_service.dart)
      // uses these to promote the *persisted* canvas state to the durable
      // server path -- without this, every device re-uploads from scratch or
      // fails outright on a device that never had the file locally.
      expect(preparation.uploads, hasLength(2));
      expect(
        preparation.uploads.map((u) => (u.phase, u.nodeId, u.serverPath)),
        containsAll(<(PipelinePhaseId, String, String)>[
          (
            PipelinePhaseId.train,
            'train-loader',
            '/server/pipeline_uploads/1/mnist.pt',
          ),
          (
            PipelinePhaseId.eval,
            'test-loader',
            '/server/pipeline_uploads/1/mnist.pt',
          ),
        ]),
      );
    },
  );

  test(
    'legacy and explicit server paths pass through without file reads',
    () async {
      final api = _FakeApiClient();
      final phases = const PipelinePhases(
        train: PipelineDAG(
          nodes: <PipelineDagNode>[
            PipelineDagNode(
              id: 'legacy',
              type: PipelineDagNodeType.dataLoader,
              parameters: <String, dynamic>{
                'format': 'pt',
                'dataset_path': '/server/legacy.pt',
              },
            ),
            PipelineDagNode(
              id: 'server',
              type: PipelineDagNodeType.dataLoader,
              parameters: <String, dynamic>{
                'format': 'pt',
                'dataset_path': '/server/current.pt',
                kDatasetPathScopeKey: kServerDatasetPathScope,
                kDatasetFileNameKey: '',
              },
            ),
          ],
        ),
      );

      final preparation = await DatasetGenerationPreparer(
        apiClient: api,
        readFile: (_) => throw StateError('must not read server paths'),
      ).prepare(phases);
      final prepared = preparation.phases;

      expect(api.uploadedFilenames, isEmpty);
      expect(
        _parameters(prepared, 'train', 0)['dataset_path'],
        '/server/legacy.pt',
      );
      expect(
        _parameters(prepared, 'train', 1)['dataset_path'],
        '/server/current.pt',
      );
      expect(
        _parameters(prepared, 'train', 1),
        isNot(contains(kDatasetPathScopeKey)),
      );
      expect(preparation.uploads, isEmpty);
    },
  );

  test(
    'rereads and reuploads the local path for every generation action',
    () async {
      final api = _FakeApiClient();
      var revision = 0;
      final preparer = DatasetGenerationPreparer(
        apiClient: api,
        readFile: (_) async => Uint8List.fromList(<int>[++revision]),
      );
      final phases = PipelinePhases(
        train: PipelineDAG(
          nodes: <PipelineDagNode>[
            _loader(
              id: 'loader',
              path: '/local/changing.pt',
              fileName: 'changing.pt',
            ),
          ],
        ),
      );

      await preparer.prepare(phases);
      await preparer.prepare(phases);

      expect(revision, 2);
      expect(api.uploadedPayloads, <List<int>>[
        <int>[1],
        <int>[2],
      ]);
    },
  );

  test(
    'missing local file fails before upload with reselect guidance',
    () async {
      final api = _FakeApiClient();
      final phases = PipelinePhases(
        train: PipelineDAG(
          nodes: <PipelineDagNode>[
            _loader(id: 'loader', path: '/gone/mnist.pt', fileName: 'mnist.pt'),
          ],
        ),
      );

      await expectLater(
        DatasetGenerationPreparer(
          apiClient: api,
          readFile: (_) => throw const FileSystemException('not found'),
        ).prepare(phases),
        throwsA(
          isA<DatasetPreparationException>()
              .having(
                (error) => error.message,
                'message',
                contains('no longer readable'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('Choose the file again'),
              ),
        ),
      );
      expect(api.uploadedFilenames, isEmpty);
    },
  );

  test('empty local file fails before upload', () async {
    final api = _FakeApiClient();

    await expectLater(
      DatasetGenerationPreparer(
        apiClient: api,
        readFile: (_) async => Uint8List(0),
      ).prepare(
        PipelinePhases(
          train: PipelineDAG(
            nodes: <PipelineDagNode>[
              _loader(
                id: 'loader',
                path: '/local/empty.pt',
                fileName: 'empty.pt',
              ),
            ],
          ),
        ),
      ),
      throwsA(
        isA<DatasetPreparationException>().having(
          (error) => error.message,
          'message',
          contains('is empty'),
        ),
      ),
    );
    expect(api.uploadedFilenames, isEmpty);
  });

  testWidgets(
    'applyDatasetUploadRemaps promotes an uploaded node from client to '
    'server scope',
    (tester) async {
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(_FakeApiClient())],
      );
      addTearDown(container.dispose);
      container
          .read(canvasProvider.notifier)
          .addPipelineDagNode(
            PipelinePhaseId.train,
            _loader(
              id: 'loader',
              path: '/local/mnist.pt',
              fileName: 'mnist.pt',
            ),
          );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      // Flush canvasProvider's internal undo-history debounce timer (started
      // by addPipelineDagNode above) so it doesn't fire after the widget
      // tree is torn down.
      await tester.pump(const Duration(milliseconds: 350));

      applyDatasetUploadRemaps(capturedRef, const <DatasetUploadRemap>[
        DatasetUploadRemap(
          phase: PipelinePhaseId.train,
          nodeId: 'loader',
          serverPath: '/server/pipeline_uploads/1/mnist.pt',
        ),
      ]);
      // Same flush, for the debounce timer updatePipelineDagNodeParams above
      // just started.
      await tester.pump(const Duration(milliseconds: 350));

      final node = container
          .read(canvasProvider)
          .pipelinePhases
          .dagFor(PipelinePhaseId.train)
          .nodes
          .single;
      expect(
        node.parameters['dataset_path'],
        '/server/pipeline_uploads/1/mnist.pt',
        reason:
            'a fresh upload must promote the persisted path, not just the '
            'one sent in this one request',
      );
      expect(node.parameters[kDatasetPathScopeKey], kServerDatasetPathScope);
    },
  );

  test(
    'upload failure is reported as a generation-time server error',
    () async {
      final api = _FakeApiClient(uploadError: StateError('network down'));

      await expectLater(
        DatasetGenerationPreparer(
          apiClient: api,
          readFile: (_) async => Uint8List.fromList(<int>[1]),
        ).prepare(
          PipelinePhases(
            train: PipelineDAG(
              nodes: <PipelineDagNode>[
                _loader(
                  id: 'loader',
                  path: '/local/mnist.pt',
                  fileName: 'mnist.pt',
                ),
              ],
            ),
          ),
        ),
        throwsA(
          isA<DatasetPreparationException>()
              .having(
                (error) => error.message,
                'message',
                contains('while generating'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('try Generate again'),
              ),
        ),
      );
    },
  );
}

PipelineDagNode _loader({
  required String id,
  required String path,
  required String fileName,
  PipelineDagNodeType type = PipelineDagNodeType.dataLoader,
}) {
  return PipelineDagNode(
    id: id,
    type: type,
    parameters: <String, dynamic>{
      'format': 'pt',
      'dataset_path': path,
      kDatasetPathScopeKey: kClientDatasetPathScope,
      kDatasetFileNameKey: fileName,
    },
  );
}

Map<String, dynamic> _parameters(
  Map<String, dynamic> prepared,
  String phase,
  int index,
) {
  final phaseJson = prepared[phase] as Map<String, dynamic>;
  final nodes = phaseJson['nodes'] as List<dynamic>;
  final node = nodes[index] as Map<String, dynamic>;
  return node['parameters'] as Map<String, dynamic>;
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.uploadError}) : super(baseUrl: 'http://localhost:0');

  final Object? uploadError;
  final List<String> uploadedFilenames = <String>[];
  final List<List<int>> uploadedPayloads = <List<int>>[];

  @override
  Future<String> uploadRawDatasetFile({
    required String filename,
    required Uint8List bytes,
  }) async {
    final error = uploadError;
    if (error != null) {
      throw error;
    }
    uploadedFilenames.add(filename);
    uploadedPayloads.add(bytes.toList(growable: false));
    return '/server/pipeline_uploads/${uploadedFilenames.length}/$filename';
  }
}
