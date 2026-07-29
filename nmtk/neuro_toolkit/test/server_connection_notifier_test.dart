import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/src/features/launcher_bootstrap/domain/launcher_bootstrap_data.dart';
import 'package:neuro_toolkit/src/features/launcher_bootstrap/presentation/launcher_bootstrap_notifier.dart';
import 'package:neuro_toolkit/src/features/server_connection/presentation/server_connection_notifier.dart';

const _readySettings = LauncherControlSettings(
  logLevel: 'info',
  mujocoAvailable: false,
  pythonAvailable: true,
  pynqBoards: [],
  akidaHosts: [],
  selectedAkidaHostId: null,
  backendDeploymentReady: true,
);

LauncherBootstrapData _readyAt(String url) {
  final baseUri = Uri.parse(url);
  return LauncherBootstrapData.ready(
    bootstrapState: LauncherBootstrapState.ready(baseUri),
    controlApiService: ControlApiService(baseUri: baseUri),
    launcherSettings: _readySettings,
  );
}

class _SwitchableBootstrapNotifier extends LauncherBootstrapNotifier {
  _SwitchableBootstrapNotifier(this.initial);

  final LauncherBootstrapData initial;

  @override
  Future<LauncherBootstrapData> build() async => initial;

  void select(LauncherBootstrapData selection) {
    state = AsyncData(selection);
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
    final container = ProviderContainer(
      overrides: [
        launcherBootstrapProvider.overrideWith(
          () => _SwitchableBootstrapNotifier(
            _readyAt('http://192.168.2.51:8090'),
          ),
        ),
        serverHealthProbeProvider.overrideWithValue(
          (_) async => responses.removeFirst(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.listen(serverConnectionProvider, (_, __) {});
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
    expect(
      container.read(serverConnectionProvider).consecutiveFailures,
      2,
    );
    await notifier.checkNow();
    expect(
      container.read(serverConnectionProvider).phase,
      ServerConnectionPhase.disconnected,
    );

    await notifier.checkNow();
    final recovered = container.read(serverConnectionProvider);
    expect(recovered.phase, ServerConnectionPhase.connected);
    expect(recovered.consecutiveFailures, 0);
  });

  test('late health response from the previous server is ignored', () async {
    final oldServerProbe = Completer<bool>();
    final bootstrap = _SwitchableBootstrapNotifier(
      _readyAt('http://192.168.2.51:8090'),
    );
    final container = ProviderContainer(
      overrides: [
        launcherBootstrapProvider.overrideWith(() => bootstrap),
        serverHealthProbeProvider.overrideWithValue((controlApi) {
          if (controlApi.baseUri.host == '192.168.2.51') {
            return oldServerProbe.future;
          }
          return Future<bool>.value(true);
        }),
      ],
    );
    addTearDown(container.dispose);

    container.listen(serverConnectionProvider, (_, __) {});
    await _flushMicrotasks();

    bootstrap.select(_readyAt('http://192.168.2.34:8090'));
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
