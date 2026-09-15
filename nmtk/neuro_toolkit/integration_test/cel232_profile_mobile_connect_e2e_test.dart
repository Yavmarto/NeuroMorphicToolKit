import 'dart:io';
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:neuro_toolkit/features/server/connect/connect_build_policy.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/shared/target_store.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart'
    show analyticsServiceProvider;
import 'package:neuro_toolkit/screens/server_access_gate.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// CEL-232: profile/debug mobile connect without credentials against the live
/// dev backend at 192.168.2.90 (CEL-226 follow-up).
///
/// Covers:
/// 1. Cold start auto-probes the default dev host and reaches connected.
/// 2. Manual host-only connect from the form reaches connected.
/// 3. Unreachable host fails within the 2s probe budget with an actionable error.
///
/// Run (from nmtk/neuro_toolkit):
///   bash ../../scripts/check_dev_server.sh 192.168.2.90 --check-only
///   flutter test integration_test/cel232_profile_mobile_connect_e2e_test.dart \
///     -d `<android-device-id>`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final rootKey = GlobalKey(debugLabel: 'cel232-snap');

  if (ConnectBuildPolicy.requiresCredentialAuth) {
    testWidgets('skipped on release builds', (tester) async {
      expect(
        ConnectBuildPolicy.requiresCredentialAuth,
        isFalse,
        reason: 'CEL-232 targets profile/debug builds only.',
      );
    });
    return;
  }

  Future<void> snap(WidgetTester tester, String name) async {
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
    final boundary =
        rootKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory dir;
    try {
      dir = Directory('build/cel232_shots')..createSync(recursive: true);
    } on FileSystemException {
      dir = Directory('${Directory.systemTemp.path}/cel232_shots')
        ..createSync(recursive: true);
    }
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

  Future<void> waitForConnected(
    WidgetTester tester,
    ProviderContainer container, {
    int seconds = 30,
  }) async {
    for (var i = 0; i < seconds * 4; i++) {
      final state = container.read(connectNotifierProvider);
      if (state.phase == ConnectPhase.connected) return;
      if (state.phase == ConnectPhase.failed) {
        await snap(tester, 'failed_${state.failureCause ?? 'unknown'}');
        throw TestFailure(
          'connect failed: ${state.failureCause ?? 'unknown error'}',
        );
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
    throw TestFailure('timed out waiting for connected phase');
  }

  Future<ProviderContainer> freshContainer() async {
    final container = ProviderContainer(
      overrides: [
        analyticsServiceProvider.overrideWithValue(AnalyticsService()),
      ],
    );
    final store = await container.read(targetStoreProvider.future);
    for (final target in await store.loadTargets()) {
      await store.forgetTarget(target.host);
    }
    return container;
  }

  Future<void> pumpGate(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
  }

  final host =
      (Platform.environment['NMTK_E2E_SERVER_HOST']?.trim().isNotEmpty ?? false)
      ? Platform.environment['NMTK_E2E_SERVER_HOST']!.trim()
      : ConnectBuildPolicy.defaultDevServerHost;

  testWidgets('cold start auto-probes the dev server without credentials', (
    tester,
  ) async {
    expect(host, isNot(anyOf('localhost', '127.0.0.1')));

    final container = await freshContainer();
    addTearDown(container.dispose);

    await pumpGate(tester, container);
    await waitForConnected(tester, container);
    await waitForGone(tester, find.text('Connect to your server'));
    expect(container.read(connectNotifierProvider).session?.host, host);
    expect(find.byKey(const Key('cel232-workspace-home')), findsOneWidget);
    await snap(tester, '01_cold_start_connected');
  });

  testWidgets('manual host-only connect reaches the workspace', (tester) async {
    const deadHost = '10.255.255.254';
    final container = await freshContainer();
    addTearDown(container.dispose);

    // A saved unreachable host makes reconnectOnOpen fail and surface the form.
    final store = await container.read(targetStoreProvider.future);
    await store.saveTarget(
      const ConnectTarget(host: deadHost, appUsername: ''),
    );

    await pumpGate(tester, container);
    await waitFor(tester, find.byKey(const Key('server-connect-connect')));
    await snap(tester, '02_manual_connect_form');

    await tester.enterText(find.byKey(const Key('server-connect-host')), host);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('server-connect-connect')));
    await tester.pump(const Duration(milliseconds: 500));

    await waitForConnected(tester, container);
    await waitForGone(tester, find.text('Connect to your server'));
    expect(find.byKey(const Key('cel232-workspace-home')), findsOneWidget);
    await snap(tester, '03_manual_connected');
  });

  testWidgets('unreachable host fails within the probe budget', (tester) async {
    const deadHost = '10.255.255.254';
    final container = await freshContainer();
    addTearDown(container.dispose);

    await container
        .read(connectNotifierProvider.notifier)
        .connect(const ConnectRequest(host: deadHost));

    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < const Duration(seconds: 5)) {
      final phase = container.read(connectNotifierProvider).phase;
      if (phase == ConnectPhase.failed) break;
      await tester.pump(const Duration(milliseconds: 100));
    }

    final state = container.read(connectNotifierProvider);
    expect(state.phase, ConnectPhase.failed);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 4)));
    expect(state.failureCause, contains('Could not reach'));
    expect(state.failureCause, contains('Wi'));
  });
}

class _WorkspaceHome extends StatelessWidget {
  const _WorkspaceHome();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF4F5F7),
      child: Center(
        child: Text(
          'NMTK workspace home (connected)',
          key: Key('cel232-workspace-home'),
        ),
      ),
    );
  }
}
