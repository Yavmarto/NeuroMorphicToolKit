import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets(
    'shows selectable live output and copies the complete transcript',
    (tester) async {
      MethodCall? clipboardCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') clipboardCall = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkLogViewerDialog(
              title: 'Raw SSH output — 192.168.2.34',
              lines: <String>[r'$ podman info', 'host:', '  arch: amd64'],
              isRunning: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Raw SSH output — 192.168.2.34'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Copy output'));
      await tester.pump();

      expect(clipboardCall?.arguments.toString(), contains(r'$ podman info'));
      expect(clipboardCall?.arguments.toString(), contains('arch: amd64'));
    },
  );

  testWidgets('fits a mobile viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NmtkLogViewerDialog(
            title: 'Raw SSH output — 192.168.2.34',
            lines: <String>[r'$ uname -s', 'Linux'],
            isRunning: false,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('nmtk-log-viewer-scroll')), findsOneWidget);
  });
}
