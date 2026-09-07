import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/server/connect/connect_notifier.dart';
import 'package:neuro_toolkit/features/server/connect/connect_service.dart';
import 'package:neuro_toolkit/features/server/shared/target_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecretStorage implements ConnectSecretStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

Future<TargetStore> _fakeTargetStore() async {
  return TargetStore(
    preferences: await SharedPreferences.getInstance(),
    secureStorage: _FakeSecretStorage(),
  );
}

class _FakeConnectService implements ConnectService {
  _FakeConnectService({this.loginResult, this.reconnectResult});

  Object? loginResult;
  Object? reconnectResult;

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
  Future<bool> probe({required String host, Duration timeout = const Duration(seconds: 2)}) async {
    return true;
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

  test('connect success saves the target and reports connected', () async {
    SharedPreferences.setMockInitialValues({});
    const session = ConnectSession(
      host: '192.168.2.90',
      username: 'ada',
      sessionToken: 'tok-1',
    );
    final container = ProviderContainer(
      overrides: [
        connectServiceProvider.overrideWithValue(
          _FakeConnectService(loginResult: session),
        ),
        targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(connectNotifierProvider.notifier)
        .connect(
          const ConnectRequest(
            host: '192.168.2.90',
            appUsername: 'ada',
            credential: 'hunter2',
          ),
        );

    final state = container.read(connectNotifierProvider);
    expect(state.phase, ConnectPhase.connected);
    expect(state.session?.sessionToken, 'tok-1');
    expect(state.savedHost, '192.168.2.90');

    final store = await container.read(targetStoreProvider.future);
    final saved = await store.loadLastTarget();
    expect(saved?.host, '192.168.2.90');
    expect(saved?.sessionToken, 'tok-1');
    expect(saved?.credential, 'hunter2');
  });

  test('connect failure reports the cause, keeps the host, saves nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        connectServiceProvider.overrideWithValue(
          _FakeConnectService(
            loginResult: const ConnectException('Incorrect username or password.'),
          ),
        ),
        targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(connectNotifierProvider.notifier)
        .connect(
          const ConnectRequest(
            host: '192.168.2.90',
            appUsername: 'ada',
            credential: 'wrong',
          ),
        );

    final state = container.read(connectNotifierProvider);
    expect(state.phase, ConnectPhase.failed);
    expect(state.failureCause, 'Incorrect username or password.');
    expect(state.savedHost, '192.168.2.90');

    final store = await container.read(targetStoreProvider.future);
    expect(await store.loadTargets(), isEmpty);
  });

  test('reconnectOnOpen restores a saved session', () async {
    SharedPreferences.setMockInitialValues({});
    const refreshed = ConnectSession(
      host: '192.168.2.90',
      username: 'ada',
      sessionToken: 'tok-2',
    );
    final container = ProviderContainer(
      overrides: [
        connectServiceProvider.overrideWithValue(
          _FakeConnectService(reconnectResult: refreshed),
        ),
        targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
      ],
    );
    addTearDown(container.dispose);

    final store = await container.read(targetStoreProvider.future);
    await store.saveTarget(
      const ConnectTarget(
        host: '192.168.2.90',
        appUsername: 'ada',
        sessionToken: 'tok-1',
        credential: 'hunter2',
      ),
    );

    await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

    final state = container.read(connectNotifierProvider);
    expect(state.phase, ConnectPhase.connected);
    expect(state.session?.sessionToken, 'tok-2');
    expect(state.savedHost, '192.168.2.90');
  });

  test('reconnectOnOpen with nothing saved fails without a saved host', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        connectServiceProvider.overrideWithValue(_FakeConnectService()),
        targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

    final state = container.read(connectNotifierProvider);
    expect(state.phase, ConnectPhase.failed);
    expect(state.savedHost, isNull);
    expect(state.failureCause, isNotNull);
  });
}
