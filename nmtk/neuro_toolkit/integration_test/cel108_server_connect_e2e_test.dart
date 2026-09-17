import 'dart:io';
import 'dart:ui' as ui show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart'
    show analyticsServiceProvider;
import 'package:neuro_toolkit/screens/server_access_gate.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// CEL-108/109: real server-connect e2e against the live dev backend at
/// 203.0.113.90 (dev), NOT mocked and NOT loopback.
///
/// Boots the shipping ServerAccessGate with real services (target store,
/// secure storage, connect client) exactly like cel91, so a cold start with
/// no saved target resolves to "no backend found" and shows the sign-in
/// popup. The test then drives that credential form for real: it enters the
/// host and the app-account credentials, taps Sign in, waits for the Connect
/// session to flip to `connected`, and asserts the gate reaches the
/// connected/home state (popup gone, workspace backdrop visible).
///
/// Note on the repo's non-loopback policy: the current app has no separate
/// "quick-connect" field. The single credential path is this sign-in popup —
/// the same popup the in-app System Health card (`nmtk://system-health`)
/// opens — and it is the only form that links credentials and connects to a
/// non-loopback host. That is the field this test drives.
///
/// No credentials are committed here. Supply them at run time:
///   NMTK_E2E_SERVER_HOST     dev server host (default 203.0.113.90)
///   NMTK_E2E_SERVER_USERNAME the app account minted at provision time
///   NMTK_E2E_SERVER_PASSWORD that account's password
///   NMTK_E2E_CONNECT_TIMEOUT_SECONDS  optional; default 120
///
/// Run (from nmtk/neuro_toolkit):
///   bash ../../scripts/check_dev_server.sh 203.0.113.90   # host healthy first
///   NMTK_E2E_SERVER_USERNAME=`app-user` NMTK_E2E_SERVER_PASSWORD=`pass` \
///     flutter test integration_test/cel108_server_connect_e2e_test.dart \
///     -d macos
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final rootKey = GlobalKey(debugLabel: 'cel108-snap');

  Future<void> snap(WidgetTester tester, String name) async {
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 3));
    await tester.pump();
    final boundary =
        rootKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/cel108_shots')..createSync(recursive: true);
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

  Future<void> waitForGone(
    WidgetTester tester,
    Finder finder, {
    int seconds = 45,
  }) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isEmpty) return;
      await tester.pump(const Duration(milliseconds: 250));
    }
    throw TestFailure('timed out waiting for $finder to disappear');
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await waitFor(tester, find.byKey(ValueKey<String>(key)));
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> waitForConnected(
    WidgetTester tester,
    ProviderContainer container, {
    int seconds = 120,
  }) async {
    for (var i = 0; i < seconds * 4; i++) {
      final state = container.read(connectNotifierProvider);
      if (state.phase == ConnectPhase.connected) {
        return;
      }
      if (state.phase == ConnectPhase.failed) {
        // Capture the failure panel before surfacing it so QA has a visual.
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await tester.pump();
        await snap(tester, '03_failed');
        throw TestFailure(
          'connection to the real server failed: '
          '${state.failureCause ?? 'unknown error'}',
        );
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
    throw TestFailure('timed out waiting for the connect phase to settle');
  }

  testWidgets(
    'cold-start connect to the real dev server via the credential form',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final env = Platform.environment;
      final host = (env['NMTK_E2E_SERVER_HOST']?.trim().isNotEmpty ?? false)
          ? env['NMTK_E2E_SERVER_HOST']!.trim()
          : '203.0.113.90';
      final username = env['NMTK_E2E_SERVER_USERNAME']?.trim();
      final password = env['NMTK_E2E_SERVER_PASSWORD'];
      final timeoutSeconds =
          int.tryParse(env['NMTK_E2E_CONNECT_TIMEOUT_SECONDS'] ?? '') ?? 120;

      expect(
        username,
        isNotNull,
        reason:
            'Set NMTK_E2E_SERVER_USERNAME to the app account to connect '
            'with (see the header of this test).',
      );
      expect(
        password,
        isNotNull,
        reason:
            'Set NMTK_E2E_SERVER_PASSWORD to that account\'s password '
            '(see the header of this test).',
      );
      expect(
        host,
        isNot(anyOf('localhost', '127.0.0.1')),
        reason:
            'this test must reach the real non-loopback dev server, not '
            'loopback.',
      );

      final container = ProviderContainer(
        overrides: [
          analyticsServiceProvider.overrideWithValue(AnalyticsService()),
        ],
      );
      addTearDown(container.dispose);

      // Cold start must see no saved target, or the gate auto-reconnects and
      // never shows the form. Drop every saved connect target first so the
      // boot is deterministic across reruns.
      final store = await container.read(targetStoreProvider.future);
      for (final target in await store.loadTargets()) {
        await store.forgetTarget(target.host);
      }

      debugPrint('CEL-108 e2e: connecting to $host as $username');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // The boundary must wrap the whole app, not just the gate: the
          // sign-in/setup flow lives in the Navigator's dialog overlay, which
          // renders above the gate's own subtree and would otherwise be
          // missing from every screenshot.
          child: RepaintBoundary(
            key: rootKey,
            child: NmtkZetaTheme.wrap(
              builder: (context, light, dark, mode) => MaterialApp(
                theme: light,
                darkTheme: dark,
                themeMode: mode,
                home: const ServerAccessGate(child: _WorkspaceHome()),
              ),
            ),
          ),
        ),
      );

      // 1. No backend found on boot => the sign-in credential form is shown.
      await waitFor(tester, find.byKey(const Key('server-connect-sign-in')));
      await tester.pump();
      await snap(tester, '01_connect_form_no_backend');

      // 2. Link credentials for the real dev server and connect. The fields
      // are asserted by value here (NmtkTextInput only mirrors programmatic
      // controller writes back to Zeta's initialValue once unfocused, so the
      // entered text may not paint in screenshots).
      await tester.enterText(
        find.byKey(const Key('server-connect-host')),
        host,
      );
      await tester.enterText(
        find.byKey(const Key('server-connect-username')),
        username!,
      );
      await tester.enterText(
        find.byKey(const Key('server-connect-password')),
        password!,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text(host),
        findsWidgets,
        reason: 'the server address must be in the host field.',
      );
      expect(
        find.text(username),
        findsWidgets,
        reason: 'the app account must be in the username field.',
      );

      await tapKey(tester, 'server-connect-sign-in');
      await snap(tester, '02_after_submit');

      // 3. Assert the connection succeeds and the app reaches the
      // connected/home state: the session phase flips to connected and the
      // gate drops the sign-in popup, leaving the workspace backdrop bare.
      await waitForConnected(tester, container, seconds: timeoutSeconds);
      expect(
        container.read(connectNotifierProvider).phase,
        ConnectPhase.connected,
        reason: 'the real server login must succeed.',
      );
      // The gate closes the sign-in popup once the session is connected; wait
      // for the close animation to finish so the assertions below are not
      // racing it.
      await waitForGone(tester, find.text('Sign in to your server'));
      await waitForGone(
        tester,
        find.byKey(const Key('server-connect-sign-in')),
      );
      expect(
        find.byKey(const Key('cel108-workspace-home')),
        findsOneWidget,
        reason: 'the workspace home surface must be reachable after connect.',
      );
      await snap(tester, '03_connected_home');
    },
  );
}

/// Minimal stand-in for the workspace surface the gate keeps mounted as its
/// backdrop, so the connected/home state is visible in screenshots and
/// assertable by key.
class _WorkspaceHome extends StatelessWidget {
  const _WorkspaceHome();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF4F5F7),
      child: Center(
        child: Text(
          'NMTK workspace home (connected)',
          key: Key('cel108-workspace-home'),
        ),
      ),
    );
  }
}
