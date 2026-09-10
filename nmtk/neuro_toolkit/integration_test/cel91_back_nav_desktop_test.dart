import 'dart:io';
import 'dart:ui' as ui show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:neuro_toolkit/screens/server_access_gate.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// CEL-91: verify the CEL-90 back-navigation fix on the real macOS embedder.
///
/// Hosts the shipping ServerAccessGate with real services (target store,
/// secure storage, connect/provision clients) on the device, then drives the
/// setup wizard for real:
///   1. connect form -> setup screen -> Back (initial form state)
///   2. setup form -> real failed provision (wrong credentials, reachable
///      local SSH port) -> Back from the failure panel
/// Both must land back on the connect form without dead-ending.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final rootKey = GlobalKey(debugLabel: 'cel91-snap');

  Future<void> snap(WidgetTester tester, String name) async {
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pump();
    final boundary =
        rootKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/cel91_shots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('screenshot saved: $name (${data.lengthInBytes} bytes)');
    image.dispose();
  }

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int seconds = 45,
  }) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 250));
    }
    throw TestFailure('timed out waiting for $finder');
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await waitFor(tester, find.byKey(ValueKey<String>(key)));
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> expectOnConnectScreen(WidgetTester tester) async {
    final form = find.byKey(const Key('server-connect-sign-in'));
    var settled = false;
    for (var i = 0; i < 20 && !settled; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      settled = form.evaluate().isNotEmpty;
    }
    expect(
      find.text('Set up your server').evaluate().isEmpty,
      isTrue,
      reason: 'setup screen must be gone',
    );
    if (!settled) {
      debugPrint(
        'DIAGNOSTIC buttons visible: '
        '${find.byType(ElevatedButton).evaluate().length} elevated, '
        '${find.text('Reconnecting to your server…').evaluate().length} '
        'reconnect label, texts: '
        '${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((t) => t != null && t.isNotEmpty).take(30).toList()}',
      );
    }
    expect(settled, isTrue, reason: 'connect form must be showing again');
  }

  testWidgets(
    'back/cancel returns to the connect screen from every setup state',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: NmtkZetaTheme.wrap(
            builder: (context, light, dark, mode) => MaterialApp(
              theme: light,
              darkTheme: dark,
              themeMode: mode,
              home: RepaintBoundary(
                key: rootKey,
                child: const ServerAccessGate(child: SizedBox.shrink()),
              ),
            ),
          ),
        ),
      );

      // The gate attempts a real reconnect against any saved target first;
      // unreachable host => connect form with "Set up a new server".
      await waitFor(tester, find.byKey(const Key('server-connect-new-server')));
      await tester.pump();
      await snap(tester, '00_connect_form');

      // --- State 1: initial form ---
      await tapKey(tester, 'server-connect-new-server');
      await waitFor(tester, find.text('Set up your server'));
      expect(find.byKey(const Key('server-setup-back')), findsOneWidget);
      await tester.pump();
      await snap(tester, '01_setup_initial_form');

      await tapKey(tester, 'server-setup-back');
      await expectOnConnectScreen(tester);
      await snap(tester, '03_back_on_connect_from_initial');

      // --- State 2: failure panel from a real provision attempt ---
      await tapKey(tester, 'server-connect-new-server');
      await waitFor(tester, find.text('Set up your server'));
      await tester.enterText(
        find.byKey(const Key('server-setup-host')),
        '127.0.0.1',
      );
      await tester.enterText(
        find.byKey(const Key('server-setup-username')),
        'qa-probe',
      );
      await tester.enterText(
        find.byKey(const Key('server-setup-password')),
        'definitely-not-the-password',
      );
      await tapKey(tester, 'server-setup-provision');
      await waitFor(
        tester,
        find.byKey(const Key('server-setup-failure')),
        seconds: 90,
      );
      expect(find.byKey(const Key('server-setup-back')), findsOneWidget);
      await tester.pump();
      await snap(tester, '02_setup_failure_panel');

      await tapKey(tester, 'server-setup-back');
      await expectOnConnectScreen(tester);
      await snap(tester, '04_back_on_connect_from_failure');
    },
  );
}
