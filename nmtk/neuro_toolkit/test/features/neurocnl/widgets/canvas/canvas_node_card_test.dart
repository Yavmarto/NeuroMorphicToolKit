// Widget tests for CanvasNodeCard — the one node card every canvas draws.
//
// The Architecture canvas and the Train/Eval canvases used to each assemble
// their own card, which is why they drifted into different sizes, different
// port spacing and different header content. These tests pin the shared
// contract; the per-canvas tests then only have to cover their own adapters.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';

// NmtkShellTokens.of falls back to deriving tokens from the ambient
// ColorScheme, so a plain MaterialApp is enough of a host here.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: Stack(children: [child])),
  ),
);

CanvasNodeCard _card({
  List<CanvasCardPort> ports = const <CanvasCardPort>[],
  String? subtitle,
  bool compact = false,
  bool collapsed = false,
  bool armedForDelete = false,
  Widget? trailingBadge,
}) {
  final Size size = canvasNodeSize(
    inputs: ports.where((CanvasCardPort p) => p.isInput).length,
    outputs: ports.where((CanvasCardPort p) => !p.isInput).length,
    compact: compact,
    collapsed: collapsed,
  );
  return CanvasNodeCard(
    nodeId: 'n1',
    cardSize: size,
    accentColor: const Color(0xFF43A047),
    icon: Icons.hub,
    title: 'LIF',
    subtitle: subtitle,
    background: const Color(0xFF202020),
    compact: compact,
    collapsed: collapsed,
    ports: ports,
    armedForDelete: armedForDelete,
    onDelete: () {},
    trailingBadge: trailingBadge,
  );
}

void main() {
  testWidgets('renders at the shared footprint for its port count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _card(
          ports: const [
            CanvasCardPort(id: 'in', label: 'in', isInput: true),
            CanvasCardPort(id: 'out', label: 'out', isInput: false),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CanvasNodeCard)),
      const Size(kCanvasNodeWidth, kCanvasNodeBaseHeight),
    );
  });

  testWidgets('draws one port dot per port, keyed by node and port id', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _card(
          ports: const [
            CanvasCardPort(id: 'in', label: 'in', isInput: true),
            CanvasCardPort(id: 'a', label: 'a', isInput: false),
            CanvasCardPort(id: 'b', label: 'b', isInput: false),
          ],
        ),
      ),
    );

    expect(find.byType(CanvasPortWidget), findsNWidgets(3));
    expect(find.byKey(const ValueKey<String>('port_n1_in')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('port_n1_b')), findsOneWidget);
  });

  testWidgets('shows the key-parameter subtitle under the title', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_card(subtitle: 'τ: 0.02 · θ: 1')));

    expect(find.text('LIF'), findsOneWidget);
    expect(find.text('τ: 0.02 · θ: 1'), findsOneWidget);
  });

  testWidgets('the compact layout drops the header bar and centres the title', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _card(
          compact: true,
          ports: const [CanvasCardPort(id: 'in', label: 'in', isInput: true)],
        ),
      ),
    );

    expect(find.byType(NodeCardHeaderBar), findsNothing);
    expect(find.text('LIF'), findsOneWidget);
  });

  testWidgets('the horizontal layout uses the shared header bar', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_card()));

    expect(find.byType(NodeCardHeaderBar), findsOneWidget);
  });

  testWidgets('the delete badge appears only while armed', (tester) async {
    await tester.pumpWidget(_host(_card()));
    expect(find.byType(NodeDeleteBadge), findsNothing);

    await tester.pumpWidget(_host(_card(armedForDelete: true)));
    expect(find.byType(NodeDeleteBadge), findsOneWidget);
  });

  testWidgets('a trailing badge renders in the card corner', (tester) async {
    await tester.pumpWidget(_host(_card(trailingBadge: const Text('42%'))));

    expect(find.text('42%'), findsOneWidget);
  });
}
