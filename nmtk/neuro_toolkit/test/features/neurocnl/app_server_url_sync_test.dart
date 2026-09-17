// Regression test for the embedded connection dot staying red forever.
//
// Root cause: NeurocnlStudioSurface._bootstrap() persisted the launcher-supplied
// initialServerUrl but never actually called checkConnection() against it, so
// serverConfigProvider's status stayed ConnectionStatus.unknown (-> red dot)
// no matter how the embedding launcher actually connected. didUpdateWidget
// also ignored a changed initialServerUrl on an already-mounted app.
//
// These assertions lock in that mounting (and later updating)
// NeurocnlStudioSurface with an initialServerUrl actually kicks off a health
// check — proven by the state moving off ConnectionStatus.unknown, which
// checkConnection() sets synchronously before its first await, without this
// test needing to mock or wait on a real network round trip.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/app.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/server_config_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';

import 'support/neurocnl_surface_test_host.dart';

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({
      'neurocnl_server_url': 'http://localhost:8000',
    });
    ServerConfigService.debugResetForTests();
    await ServerConfigService.initialize();
  });

  testWidgets('mounting with initialServerUrl checks the connection instead of '
      'leaving it unknown forever', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildNeurocnlSurfaceTestHost(
        initialServerUrl: 'http://192.0.2.5:9000/api/neurocnl',
      ),
    );
    // Bounded pumps rather than pumpAndSettle: the health check's own
    // network round trip can take up to 5s to resolve (checkConnection's
    // timeout) and isn't awaited by _bootstrapFuture, so pumpAndSettle
    // would either hang or just be slow for no reason — the fix under
    // test is that a check was *started* at all, not that it resolves
    // successfully in a test environment with no real backend.
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(NeurocnlStudioSurface)),
    );
    expect(
      container.read(serverConfigProvider).status,
      isNot(ConnectionStatus.unknown),
      reason:
          'checkConnection() sets status to `checking` synchronously '
          'before its first await — status staying `unknown` here means '
          'the embedded bootstrap never called it at all (the reported '
          'bug: the dot stays red regardless of whether the backend is '
          'actually reachable).',
    );
    expect(
      container.read(serverConfigProvider).serverUrl,
      'http://192.0.2.5:9000/api/neurocnl',
    );
  });

  testWidgets(
    'updating initialServerUrl on an already-mounted app re-checks the new '
    'URL',
    (WidgetTester tester) async {
      Widget buildApp(String url) =>
          buildNeurocnlSurfaceTestHost(initialServerUrl: url);

      await tester.pumpWidget(buildApp('http://192.0.2.5:9000/api/neurocnl'));
      await tester.pump();
      await tester.pump();

      // Same widget/State reused (no key change) — this exercises
      // didUpdateWidget, not a remount.
      await tester.pumpWidget(buildApp('http://192.0.2.9:9000/api/neurocnl'));
      await tester.pump();
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(NeurocnlStudioSurface)),
      );
      expect(
        container.read(serverConfigProvider).serverUrl,
        'http://192.0.2.9:9000/api/neurocnl',
        reason:
            'didUpdateWidget must persist and re-check a newly-supplied '
            'initialServerUrl rather than silently dropping it, which left '
            'the app pointed at the stale first-boot URL after a reconnect '
            'to a different host.',
      );
    },
  );
}
