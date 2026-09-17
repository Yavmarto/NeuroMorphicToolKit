import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/server/connect/connect_build_policy.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/features/server/shared/target_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecretStorage implements ConnectSecretStorage {
  _FakeSecretStorage({this.throwOnWrite = false});

  final bool throwOnWrite;
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (throwOnWrite) {
      throw Exception('secure storage unavailable');
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _TrackingSecretStorage implements ConnectSecretStorage {
  _TrackingSecretStorage({this.onRead});

  final void Function()? onRead;

  @override
  Future<String?> read(String key) async {
    onRead?.call();
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

Future<TargetStore> _fakeTargetStore({bool throwOnWrite = false}) async {
  return TargetStore(
    preferences: await SharedPreferences.getInstance(),
    secureStorage: _FakeSecretStorage(throwOnWrite: throwOnWrite),
  );
}

/// In debug/profile (the default test mode) the connect flow probes reachability
/// only — login/reconnect are release-only (CEL-220).
class _FakeConnectService implements ConnectService {
  _FakeConnectService({
    this.reachable = true,
    this.loginResult,
    this.reconnectResult,
  });

  bool reachable;
  Object? loginResult;
  Object? reconnectResult;
  int probeCalls = 0;
  String? lastProbedHost;

  @override
  Future<ConnectSession> login({
    required String host,
    required String username,
    required String credential,
  }) async {
    final result = loginResult;
    if (result is Exception) throw result;
    return result as ConnectSession;
  }

  @override
  Future<ConnectSession> reconnect(ConnectTarget target) async {
    final result = reconnectResult;
    if (result == null) {
      throw const ConnectException('no saved session');
    }
    if (result is Exception) throw result;
    return result as ConnectSession;
  }

  @override
  Future<bool> probe({
    required String host,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    probeCalls++;
    lastProbedHost = host;
    return reachable;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('build starts idle with no saved host', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        connectServiceProvider.overrideWithValue(_FakeConnectService()),
        targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
      ],
    );
    addTearDown(container.dispose);

    final state = container.read(connectNotifierProvider);
    expect(state.phase, ConnectPhase.idle);
    expect(state.savedHost, isNull);
  });

  test(
    'connect succeeds with no credential when the host answers, and saves it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = _FakeConnectService(reachable: true);
      final container = ProviderContainer(
        overrides: [
          connectServiceProvider.overrideWithValue(service),
          targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(connectNotifierProvider.notifier)
          .connect(const ConnectRequest(host: '192.168.2.90'));

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.connected);
      expect(state.session?.host, '192.168.2.90');
      expect(state.savedHost, '192.168.2.90');
      expect(service.probeCalls, 1);
      expect(service.lastProbedHost, '192.168.2.90');

      final store = await container.read(targetStoreProvider.future);
      final saved = await store.loadLastTarget();
      expect(saved?.host, '192.168.2.90');
    },
    skip: ConnectBuildPolicy.requiresCredentialAuth
        ? 'release-only credential connect'
        : false,
  );

  test(
    'connect fails with a could-not-reach message when the host does not answer',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          connectServiceProvider.overrideWithValue(
            _FakeConnectService(reachable: false),
          ),
          targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(connectNotifierProvider.notifier)
          .connect(const ConnectRequest(host: '192.168.2.90'));

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.failed);
      expect(state.failureCause, contains('Could not reach'));
      expect(state.savedHost, '192.168.2.90');
    },
    skip: ConnectBuildPolicy.requiresCredentialAuth
        ? 'release-only credential connect'
        : false,
  );

  test(
    'reconnectOnOpen probes the default dev host when nothing is saved',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = _FakeConnectService(reachable: true);
      final container = ProviderContainer(
        overrides: [
          connectServiceProvider.overrideWithValue(service),
          targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.connected);
      expect(state.savedHost, ConnectBuildPolicy.defaultDevServerHost);
      expect(service.lastProbedHost, ConnectBuildPolicy.defaultDevServerHost);
    },
    skip: ConnectBuildPolicy.requiresCredentialAuth
        ? 'release-only credential connect'
        : false,
  );

  test(
    'reconnectOnOpen restores a saved host via probe',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = _FakeConnectService(reachable: true);
      final container = ProviderContainer(
        overrides: [
          connectServiceProvider.overrideWithValue(service),
          targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
        ],
      );
      addTearDown(container.dispose);

      final store = await container.read(targetStoreProvider.future);
      await store.saveTarget(
        const ConnectTarget(host: '10.0.0.5', appUsername: ''),
      );

      await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.connected);
      expect(state.savedHost, '10.0.0.5');
      expect(service.lastProbedHost, '10.0.0.5');
    },
    skip: ConnectBuildPolicy.requiresCredentialAuth ? 'release-only' : false,
  );

  test(
    'connect still succeeds when saving the target fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          connectServiceProvider.overrideWithValue(
            _FakeConnectService(reachable: true),
          ),
          targetStoreProvider.overrideWith(
            (ref) => _fakeTargetStore(throwOnWrite: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(connectNotifierProvider.notifier)
          .connect(const ConnectRequest(host: '192.168.2.90'));

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.connected);
      expect(state.session?.host, '192.168.2.90');
    },
    skip: ConnectBuildPolicy.requiresCredentialAuth
        ? 'release-only credential connect'
        : false,
  );

  test(
    'reconnectOnOpen probes saved host without reading secure storage',
    () async {
      SharedPreferences.setMockInitialValues({});
      var secureReads = 0;
      final container = ProviderContainer(
        overrides: [
          connectServiceProvider.overrideWithValue(
            _FakeConnectService(reachable: true),
          ),
          targetStoreProvider.overrideWith((ref) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              'connect.targets.v1',
              '[{"host":"10.0.0.5","appUsername":"","updatedAt":"2026-09-13T00:00:00.000"}]',
            );
            return TargetStore(
              preferences: prefs,
              secureStorage: _TrackingSecretStorage(
                onRead: () => secureReads++,
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.connected);
      expect(state.savedHost, '10.0.0.5');
      expect(secureReads, 0);
    },
    skip: ConnectBuildPolicy.requiresCredentialAuth ? 'release-only' : false,
  );

  test(
    'reconnectOnOpen does not leave reconnecting when save fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          connectServiceProvider.overrideWithValue(
            _FakeConnectService(reachable: true),
          ),
          targetStoreProvider.overrideWith(
            (ref) => _fakeTargetStore(throwOnWrite: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.connected);
      expect(state.phase, isNot(ConnectPhase.reconnecting));
    },
    skip: ConnectBuildPolicy.requiresCredentialAuth
        ? 'release-only credential connect'
        : false,
  );
}
