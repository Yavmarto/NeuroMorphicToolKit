import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart';

/// Lets a test swap the "selected" control API mid-run, since
/// [selectedControlApiServiceProvider] is normally derived from the Connect
/// session rather than settable directly.
final _controlApiOverrideProvider = StateProvider<ControlApiService?>(
  (ref) => null,
);

/// Counts calls to [reconnectOnOpen] instead of performing a real HTTP
/// login, so tests can assert the notifier's repair path invokes it exactly
/// once per outage without needing a fake server.
class _CountingConnectNotifier extends ConnectNotifier {
  _CountingConnectNotifier({this.throwsOnReconnect = false});

  final bool throwsOnReconnect;
  int reconnectCalls = 0;

  @override
  Future<void> reconnectOnOpen() async {
    reconnectCalls++;
    if (throwsOnReconnect) {
      throw StateError('no saved credential to reconnect with');
    }
  }
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('health state becomes unstable, disconnected, then recovers', () async {
    final responses = Queue<bool>.from([true, false, false, false, true]);
    final connectNotifier = _CountingConnectNotifier();
    final container = ProviderContainer(
      overrides: [
        selectedControlApiServiceProvider.overrideWith(
          (ref) => ref.watch(_controlApiOverrideProvider),
        ),
        connectNotifierProvider.overrideWith(() => connectNotifier),
        serverHealthProbeProvider.overrideWithValue(
          (_) async => responses.removeFirst(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(_controlApiOverrideProvider.notifier).state =
        ControlApiService(baseUri: Uri.parse('http://192.168.2.90:8090'));

    container.listen(serverConnectionProvider, (_, _) {});
    await _flushMicrotasks();
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.connected,
    );

    final notifier = container.read(serverConnectionProvider.notifier);
    await notifier.checkNow();
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.unstable,
    );
    await notifier.checkNow();
    expect(container.read(serverConnectionProvider).consecutiveFailures, 2);
    await notifier.checkNow();
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.disconnected,
    );
    await _flushMicrotasks();
    expect(connectNotifier.reconnectCalls, 1);
    final recovered = container.read(serverConnectionProvider);
    expect(recovered.phase, ServerConnectionPhase.connected);
    expect(recovered.consecutiveFailures, 0);
  });

  test('automatic repair runs only once during one outage', () async {
    final connectNotifier = _CountingConnectNotifier();
    final container = ProviderContainer(
      overrides: [
        selectedControlApiServiceProvider.overrideWith(
          (ref) => ref.watch(_controlApiOverrideProvider),
        ),
        connectNotifierProvider.overrideWith(() => connectNotifier),
        serverHealthProbeProvider.overrideWithValue((_) async => false),
      ],
    );
    addTearDown(container.dispose);
    container.read(_controlApiOverrideProvider.notifier).state =
        ControlApiService(baseUri: Uri.parse('http://192.168.2.90:8090'));

    container.listen(serverConnectionProvider, (_, _) {});
    await _flushMicrotasks();
    final notifier = container.read(serverConnectionProvider.notifier);
    for (var attempt = 0; attempt < 6; attempt++) {
      await notifier.checkNow();
    }
    await _flushMicrotasks();

    expect(connectNotifier.reconnectCalls, 1);
  });

  test('missing repair credential does not create a repair loop', () async {
    final connectNotifier = _CountingConnectNotifier(throwsOnReconnect: true);
    final container = ProviderContainer(
      overrides: [
        selectedControlApiServiceProvider.overrideWith(
          (ref) => ref.watch(_controlApiOverrideProvider),
        ),
        connectNotifierProvider.overrideWith(() => connectNotifier),
        serverHealthProbeProvider.overrideWithValue((_) async => false),
      ],
    );
    addTearDown(container.dispose);
    container.read(_controlApiOverrideProvider.notifier).state =
        ControlApiService(baseUri: Uri.parse('http://192.168.2.90:8090'));

    container.listen(serverConnectionProvider, (_, _) {});
    await _flushMicrotasks();
    final notifier = container.read(serverConnectionProvider.notifier);
    for (var attempt = 0; attempt < 6; attempt++) {
      await notifier.checkNow();
    }
    await _flushMicrotasks();

    expect(connectNotifier.reconnectCalls, 1);
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.disconnected,
    );
  });

  test('late health response from the previous server is ignored', () async {
    final oldServerProbe = Completer<bool>();
    final container = ProviderContainer(
      overrides: [
        selectedControlApiServiceProvider.overrideWith(
          (ref) => ref.watch(_controlApiOverrideProvider),
        ),
        serverHealthProbeProvider.overrideWithValue((controlApi) {
          if (controlApi.baseUri.host == '192.168.2.90') {
            return oldServerProbe.future;
          }
          return Future<bool>.value(true);
        }),
      ],
    );
    addTearDown(container.dispose);
    final overrideNotifier = container.read(
      _controlApiOverrideProvider.notifier,
    );
    overrideNotifier.state = ControlApiService(
      baseUri: Uri.parse('http://192.168.2.90:8090'),
    );

    container.listen(serverConnectionProvider, (_, _) {});
    await _flushMicrotasks();

    overrideNotifier.state = ControlApiService(
      baseUri: Uri.parse('http://192.168.2.34:8090'),
    );
    await _flushMicrotasks();
    var state = container.read(serverConnectionProvider);
    expect(state.baseUri?.host, '192.168.2.34');
    expect(state.phase, ServerConnectionPhase.connected);

    oldServerProbe.complete(false);
    await _flushMicrotasks();
    state = container.read(serverConnectionProvider);
    expect(state.baseUri?.host, '192.168.2.34');
    expect(state.phase, ServerConnectionPhase.connected);
  });
}
