// Widget tests for stylus/pen support on NetworkCanvas.
//
// Baseline coverage (touch pans, ports still connect) guards against
// regressing the pre-existing mouse/touch interaction model; the
// stylus-specific cases exercise the new StylusCanvasRecognizer wiring
// (lasso selection, handwriting-to-node, eraser) end-to-end through the
// real widget tree.
//
// Most drags use tester.dragFrom, which sends a slop-crossing move followed
// by the remainder -- Flutter's built-in pan recognizers (used by node/port
// dragging) need that to register the drag. The stylus port-drag case below
// instead uses many small manual moveTo steps: dragFrom's 2-jump algorithm
// does not reliably deliver intermediate onPanUpdate callbacks for
// PointerDeviceKind.stylus specifically (reproduced against the unmodified
// widget too, so it is a test-harness quirk, not a regression). The canvas
// body is sized above the 840px mobile breakpoint so all ports use the
// desktop (left/right) layout this test's port-position math assumes, and
// the test surface is enlarged to match via _pumpCanvas.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart'
    hide CanvasNode;
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_canvas.dart';

/// Stands in for the real backend so addNode/removeNode's fire-and-forget
/// canonical-doc/validation sync never makes a real HTTP call in tests.
class _FakeCanvasApiClient extends ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:0');

  @override
  Future<ParseCnlResponse> canvasToCanonical(CanvasGraph graph) async =>
      const ParseCnlResponse(document: CanonicalEditorDocument(irJson: {}));

  @override
  Future<ValidationResult> validateGraph(CanvasGraph graph) async =>
      ValidationResult(valid: true, errors: const []);
}

CanvasNode _lifNode({required String id, required List<double> position}) =>
    CanvasNode(
      id: id,
      componentId: 'lif_population',
      nirType: 'nir.LIF',
      label: 'LIF',
      parameters: const <String, dynamic>{'name': 'LIF 1'},
      position: position,
      width: 200,
      height: 160,
    );

ProviderContainer _makeContainer({List<CanvasNode> nodes = const []}) {
  final container = ProviderContainer(
    overrides: [
      canvas_sync.apiClientProvider.overrideWithValue(_FakeCanvasApiClient()),
    ],
  );
  container
      .read(canvasProvider.notifier)
      .setGraph(CanvasGraph(nodes: nodes, edges: const [], metadata: const {}));
  return container;
}

Widget _buildApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 1200, height: 900, child: NetworkCanvas()),
      ),
    ),
  );
}

/// The default test surface is 800x600 physical pixels; the canvas body is
/// 1200x900, so the surface must be enlarged to match -- otherwise touches
/// outside 800x600 hit nothing at all.
Future<void> _pumpCanvas(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_buildApp(container));
  await tester.pump();
}

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  group('baseline touch/mouse regression coverage', () {
    testWidgets(
      'workspace restore places the first model node in the safe anchor',
      (tester) async {
        final container = _makeContainer(
          nodes: [
            _lifNode(id: 'restored', position: const [40, 100]),
          ],
        );
        addTearDown(container.dispose);
        await _pumpCanvas(tester, container);

        container.read(canvasProvider.notifier).requestWorkspaceRestoreFocus();
        await tester.pump();
        await tester.pump();

        final Finder node = find.byKey(const ValueKey<String>('node_restored'));
        // Card footprint comes from the shared canvasNodeSize (150x132 for a
        // 1-in/1-out node), so the centre sits half a card in from the
        // restored anchor.
        expect(tester.getCenter(node), const Offset(191, 238));
        await tester.pump(const Duration(milliseconds: 1));
      },
    );

    testWidgets('the canvas drag target is bounded to the visible viewport', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      final Finder canvas = find.byType(NetworkCanvas);
      final Finder dragTarget = find.byType(DragTarget<NirNodeType>);

      expect(tester.getSize(dragTarget), tester.getSize(canvas));

      await tester.tapAt(tester.getCenter(canvas));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a touch drag over empty canvas still pans the viewport', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      final initialPan = container.read(canvasProvider).viewport.pan;
      expect(initialPan, CanvasViewport.defaults.pan);

      await tester.dragFrom(
        const Offset(1000, 700),
        const Offset(80, 80),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(canvasProvider).viewport.pan, isNot(initialPan));
    });

    testWidgets(
      'a mouse drag starting on an output port still creates a connection',
      (tester) async {
        final container = _makeContainer(
          nodes: [
            _lifNode(id: 'source', position: const [100, 100]),
            _lifNode(id: 'target', position: const [500, 100]),
          ],
        );
        addTearDown(container.dispose);
        await _pumpCanvas(tester, container);

        final Finder outputPort = find.byKey(
          const ValueKey<String>('port_source_out'),
        );
        final Finder inputPort = find.byKey(
          const ValueKey<String>('port_target_in'),
        );
        expect(outputPort, findsOneWidget);
        expect(inputPort, findsOneWidget);

        final Offset start = tester.getCenter(outputPort);
        final Offset end = tester.getCenter(inputPort);
        await tester.dragFrom(
          start,
          end - start,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(container.read(canvasProvider).graph.edges, isNotEmpty);
      },
    );

    testWidgets(
      'a stylus drag from an output port to an input port still creates a '
      'connection (the empty-canvas recognizer must decline over ports)',
      (tester) async {
        final container = _makeContainer(
          nodes: [
            _lifNode(id: 'source', position: const [100, 100]),
            _lifNode(id: 'target', position: const [500, 100]),
          ],
        );
        addTearDown(container.dispose);
        await _pumpCanvas(tester, container);

        final Finder outputPort = find.byKey(
          const ValueKey<String>('port_source_out'),
        );
        final Finder inputPort = find.byKey(
          const ValueKey<String>('port_target_in'),
        );

        final Offset start = tester.getCenter(outputPort);
        final Offset end = tester.getCenter(inputPort);
        final TestGesture gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.stylus,
        );
        for (int i = 1; i <= 20; i++) {
          await gesture.moveTo(Offset.lerp(start, end, i / 20)!);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 400));

        expect(container.read(canvasProvider).graph.edges, isNotEmpty);
      },
    );
  });

  group('stylus lasso selection', () {
    testWidgets('a stylus drag over empty canvas selects nodes under the rect '
        'and does not pan the viewport', (tester) async {
      final container = _makeContainer(
        nodes: [
          _lifNode(id: 'n1', position: const [300, 300]),
        ],
      );
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      final initialPan = container.read(canvasProvider).viewport.pan;
      expect(initialPan, CanvasViewport.defaults.pan);
      expect(container.read(canvasProvider).selectedNodeIds, isEmpty);

      await tester.dragFrom(
        const Offset(250, 250),
        const Offset(300, 250),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(canvasProvider).selectedNodeIds, {'n1'});
      expect(container.read(canvasProvider).viewport.pan, initialPan);
    });
  });

  group('stylus handwriting-to-node creation', () {
    testWidgets(
      'a short stylus tap on empty canvas opens the handwriting field, '
      'and submitting "LIF" creates an nir.LIF node',
      (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);
        await _pumpCanvas(tester, container);

        expect(container.read(canvasProvider).graph.nodes, isEmpty);

        final TestGesture gesture = await tester.startGesture(
          const Offset(700, 500),
          kind: PointerDeviceKind.stylus,
        );
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 16));

        final Finder handwritingField = find.widgetWithText(
          TextField,
          'Node type…',
        );
        expect(handwritingField, findsOneWidget);

        await tester.enterText(handwritingField, 'LIF');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump(const Duration(milliseconds: 400));

        expect(container.read(canvasProvider).graph.nodes, hasLength(1));
        expect(
          container.read(canvasProvider).graph.nodes.single.nirType,
          'nir.LIF',
        );
      },
    );
  });

  group('stylus hover-snap to nearest port', () {
    testWidgets(
      'hovering (without touching) near a compatible input port snaps the '
      'live preview wire onto it and marks the port isHoverCandidate; '
      'hovering away releases both',
      (tester) async {
        final container = _makeContainer(
          nodes: [
            _lifNode(id: 'source', position: const [100, 100]),
            _lifNode(id: 'target', position: const [500, 100]),
          ],
        );
        addTearDown(container.dispose);
        await _pumpCanvas(tester, container);

        // Start a connection by tapping the output port.
        await tester.tap(find.byKey(const ValueKey<String>('port_source_out')));
        await tester.pump();
        expect(container.read(canvasProvider).connectingFromNodeId, 'source');

        ConnectionPainter currentConnectionPainter() {
          return tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (Widget w) =>
                          w is CustomPaint && w.painter is ConnectionPainter,
                    ),
                  )
                  .painter
              as ConnectionPainter;
        }

        bool targetPortIsHoverCandidate() {
          return tester
              .widget<CanvasPortWidget>(
                find.ancestor(
                  of: find.byKey(const ValueKey<String>('port_target_in')),
                  matching: find.byType(CanvasPortWidget),
                ),
              )
              .isHoverCandidate;
        }

        // Hover near (not exactly on) the target's single input port. With
        // the node at [500,100] and the shared 150x132 card, its one input
        // port centre is (515, 104): x = 500 + hitTarget/2, y = 100 + header
        // 44 + (132 - 44)/2.
        final TestGesture hover = await tester.createGesture(
          kind: PointerDeviceKind.stylus,
        );
        await hover.addPointer(location: const Offset(900, 700));
        await tester.pump();
        await hover.moveTo(const Offset(520, 111));
        await tester.pump();

        expect(targetPortIsHoverCandidate(), isTrue);
        expect(
          currentConnectionPainter().currentConnectingPoint,
          const Offset(515, 104),
        );

        // Hover away, over empty canvas -- both should release.
        await hover.moveTo(const Offset(900, 700));
        await tester.pump();

        expect(targetPortIsHoverCandidate(), isFalse);
        expect(
          currentConnectionPainter().currentConnectingPoint,
          const Offset(900, 700),
        );

        await hover.removePointer();
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });

  group('inverted-stylus eraser', () {
    testWidgets('an inverted-stylus tap over a node removes it', (
      tester,
    ) async {
      final container = _makeContainer(
        nodes: [
          _lifNode(id: 'to_erase', position: const [100, 100]),
        ],
      );
      addTearDown(container.dispose);
      await _pumpCanvas(tester, container);

      expect(container.read(canvasProvider).graph.nodes, hasLength(1));

      final TestGesture gesture = await tester.startGesture(
        const Offset(100, 100), // well inside the 150x132 node body
        kind: PointerDeviceKind.invertedStylus,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(canvasProvider).graph.nodes, isEmpty);
    });
  });
}
