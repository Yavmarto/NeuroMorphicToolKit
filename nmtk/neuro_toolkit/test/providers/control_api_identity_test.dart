import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';

/// Lets the test push a ConnectState without going over the network.
class _TestConnectNotifier extends ConnectNotifier {
  @override
  ConnectState build() => const ConnectState();

  void emit(ConnectState next) => state = next;
}

// Deliberately non-const: every call returns a fresh instance, the way
// ConnectNotifier builds its state after a real login. A const literal would
// be canonicalised to one object and hide the very thing under test.
ConnectState connectedTo(String host) => ConnectState(
  phase: ConnectPhase.connected,
  session: ConnectSession(
    host: host,
    username: 'dev',
    sessionToken: 'token-abc',
  ),
);

ProviderContainer makeContainer() {
  final container = ProviderContainer(
    overrides: [
      analyticsServiceProvider.overrideWithValue(AnalyticsService()),
      connectNotifierProvider.overrideWith(_TestConnectNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('re-publishing the same session does not re-emit downstream', () {
    final container = makeContainer();

    var serviceEmissions = 0;
    var bootstrapEmissions = 0;
    container.listen(
      selectedControlApiServiceProvider,
      (_, _) => serviceEmissions++,
    );
    container.listen(
      launcherBootstrapStateProvider,
      (_, _) => bootstrapEmissions++,
    );

    final notifier =
        container.read(connectNotifierProvider.notifier)
            as _TestConnectNotifier;

    notifier.emit(connectedTo('203.0.113.90'));
    container.read(selectedControlApiServiceProvider);
    container.read(launcherBootstrapStateProvider);
    expect(serviceEmissions, 1, reason: 'first connect is a real change');
    expect(bootstrapEmissions, 1);

    // Same host, same token, new objects. Without value equality this emitted
    // a fresh ControlApiService and a fresh LauncherBootstrapState, which
    // cascaded a rebuild into moduleProvider while it was still building
    // (CEL-270).
    notifier.emit(connectedTo('203.0.113.90'));
    container.read(selectedControlApiServiceProvider);
    container.read(launcherBootstrapStateProvider);
    expect(serviceEmissions, 1);
    expect(bootstrapEmissions, 1);
  });

  test('connecting to a different host does re-emit', () {
    final container = makeContainer();

    var serviceEmissions = 0;
    container.listen(
      selectedControlApiServiceProvider,
      (_, _) => serviceEmissions++,
    );

    final notifier =
        container.read(connectNotifierProvider.notifier)
            as _TestConnectNotifier;

    notifier.emit(connectedTo('203.0.113.90'));
    container.read(selectedControlApiServiceProvider);
    notifier.emit(connectedTo('203.0.113.91'));
    container.read(selectedControlApiServiceProvider);

    expect(serviceEmissions, 2);
  });
}
