import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/project.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/canvas/project_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ProjectScreen loads a saved project into the shared canvas', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final loadedGraph = CanvasGraph(
      nodes: <CanvasNode>[
        CanvasNode(
          id: 'node-1',
          componentId: 'lif',
          parameters: const <String, dynamic>{'threshold': 1.0},
          position: const <double>[120, 240],
        ),
      ],
      edges: <CanvasEdge>[
        CanvasEdge(
          id: 'edge-1',
          sourceNodeId: 'node-1',
          sourcePort: 'spike',
          targetNodeId: 'node-1',
          targetPort: 'input',
          parameters: const <String, dynamic>{'weight': 0.5},
        ),
      ],
      metadata: const <String, dynamic>{
        'zoom': 1.25,
        'pan': <double>[8, 16],
      },
    );

    final mockHttpClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/neurosim/projects') {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'project-1',
              'name': 'Visual Cortex Demo',
              'description': 'Merged canvas project',
              'updated_at': '2026-05-01T07:00:00Z',
            },
          ]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }

      if (request.method == 'GET' &&
          request.url.path == '/api/neurosim/projects/project-1') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'project-1',
            'name': 'Visual Cortex Demo',
            'description': 'Merged canvas project',
            'updated_at': '2026-05-01T07:00:00Z',
            'graph': loadedGraph.toJson(),
            'cnl_spec': 'The neuron MUST spike.',
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }

      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });

    final container = ProviderContainer(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test', httpClient: mockHttpClient),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(canvasProvider, (_, _) {});
    addTearDown(subscription.close);

    String? selectedProjectId;
    String? loadedProjectId;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ProjectScreen(
              onProjectSelected: (value) => selectedProjectId = value,
              onLoadIntoCanvas: (project) => loadedProjectId = project.id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visual Cortex Demo'), findsOneWidget);
    expect(find.text('Merged canvas project'), findsOneWidget);

    await tester.tap(find.text('Visual Cortex Demo'));
    await tester.pumpAndSettle();

    expect(selectedProjectId, 'project-1');
    expect(find.text('Nodes: 1, Edges: 1'), findsOneWidget);
    expect(find.text('Load into Canvas'), findsOneWidget);

    await tester.tap(find.text('Load into Canvas'));
    await tester.pumpAndSettle();

    expect(loadedProjectId, 'project-1');

    final canvasState = container.read(canvasProvider);
    expect(canvasState.graph.nodes.length, 1);
    expect(canvasState.graph.nodes.single.id, 'node-1');
    expect(canvasState.graph.edges.length, 1);
    expect(canvasState.viewport.zoom, 1.25);
    expect(canvasState.viewport.pan, const <double>[8, 16]);
  });

  testWidgets('ProjectScreen saves current canvas design as a new project', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final currentGraph = CanvasGraph(
      nodes: <CanvasNode>[
        CanvasNode(
          id: 'n1',
          componentId: 'lif',
          parameters: const <String, dynamic>{'threshold': 0.9},
          position: const <double>[10, 20],
        ),
      ],
      edges: const <CanvasEdge>[],
      metadata: const <String, dynamic>{
        'zoom': 1.0,
        'pan': <double>[0.0, 0.0],
      },
    );

    var createCalled = false;
    String? receivedName;

    final mockHttpClient = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/neurosim/projects') {
        return http.Response(
          jsonEncode(<Object>[]),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }

      if (request.method == 'POST' &&
          request.url.path == '/api/neurosim/projects') {
        createCalled = true;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        receivedName = body['name'] as String;
        final savedProject = Project(
          id: 'new-project-1',
          name: receivedName!,
          description: body['description'] as String? ?? '',
          updatedAt: '2026-05-01T10:00:00Z',
          graph: currentGraph,
        );
        return http.Response(
          jsonEncode(savedProject.toJson()),
          201,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }

      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });

    final container = ProviderContainer(
      overrides: <Override>[
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test', httpClient: mockHttpClient),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(canvasProvider, (_, _) {});
    addTearDown(subscription.close);

    container.read(canvasProvider.notifier).setGraph(currentGraph);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ProjectScreen(
              onProjectSelected: (_) {},
              onLoadIntoCanvas: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save Current Design'), findsOneWidget);

    await tester.tap(find.text('Save Current Design'));
    await tester.pumpAndSettle();

    // The save dialog should appear.
    expect(find.text('Save Current Design'), findsWidgets);

    // Fill in the project name.
    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'Motor Cortex Network');
    await tester.pumpAndSettle();

    // Confirm the save.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(createCalled, isTrue);
    expect(receivedName, 'Motor Cortex Network');
  });
}
