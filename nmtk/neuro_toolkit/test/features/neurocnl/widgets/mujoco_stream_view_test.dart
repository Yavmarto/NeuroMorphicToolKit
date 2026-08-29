import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' show ZetaIcons;
import 'package:neuro_toolkit/features/neurocnl/widgets/mujoco_stream_view.dart';

void main() {
  group('MujocoStreamView', () {
    testWidgets('shows unavailable state text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MujocoStreamView(streamUrl: '')),
        ),
      );
      expect(find.text('Simulation stream unavailable'), findsOneWidget);
      expect(find.text('No MuJoCo stream URL configured.'), findsOneWidget);
    });

    testWidgets('shows videocam_off icon when unavailable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MujocoStreamView(streamUrl: '')),
        ),
      );
      expect(find.byIcon(ZetaIcons.video_off), findsOneWidget);
    });

    testWidgets('shows stream badge for configured endpoint', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MujocoStreamView(streamUrl: 'http://example.com/stream'),
          ),
        ),
      );
      expect(find.text('MJPEG stream'), findsOneWidget);
    });
  });
}
