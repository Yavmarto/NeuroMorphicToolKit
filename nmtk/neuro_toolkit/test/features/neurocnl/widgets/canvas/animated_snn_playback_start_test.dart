import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/animated_snn_playback.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

/// The raster reveals progressively as its clock advances, so where the clock
/// starts decides whether the panel arrives showing data or showing nothing.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    AnimationController? controller,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedSnnPlayback(
            spikes: const {
              '0': [1.0, 20.0],
              '1': [50.0, 90.0],
            },
            duration: 100,
            playbackController: controller,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('arrives fully drawn rather than blank', (tester) async {
    await pump(tester);
    // A blank plot beside a populated one reads as a broken chart, not an
    // unplayed one.
    expect(find.textContaining('100.0 / 100 ms'), findsOneWidget);
  });

  testWidgets('play restarts the reveal from zero', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(ZetaIcons.play));
    await tester.pump();
    expect(find.textContaining('0.0 / 100 ms'), findsOneWidget);
    // Let the controller finish so no timer outlives the test.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('leaves a parent-owned clock where the parent put it', (
    tester,
  ) async {
    // The Results step drives its tile grid and this raster from one clock;
    // seeking it here would jump the grid too.
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);

    await pump(tester, controller: controller);
    expect(controller.value, 0.0);
  });
}
