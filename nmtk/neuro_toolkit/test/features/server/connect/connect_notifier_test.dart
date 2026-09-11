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

/// A device connecting to an existing server only ever probes reachability
/// (CEL-171) -- `login`/`reconnect` are the credentialed calls the connect
/// flow no longer uses, so they assert if the notifier ever reaches for them.
class _FakeConnectService implements ConnectService {
  _FakeConnectService({this.reachable = true});

  bool reachable;
  int probeCalls = 0;
  String? lastProbedHost;

  @override
  Future<ConnectSession> login({
    required String host,
    required String username,
    required String credential,
  }) async {
    throw UnimplementedError(
      'connecting to an existing server must not call login()',
    );
  }

  @override
  Future<ConnectSession> reconnect(ConnectTarget target) async {
    throw UnimplementedError(
      'connecting to an existing server must not call reconnect()',
    );
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

      final store = await container.read(targetStoreProvider.future);
      expect(await store.loadTargets(), isEmpty);
    },
  );

  test('reconnectOnOpen reconnects silently when the saved host still answers', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        connectServiceProvider.overrideWithValue(
          _FakeConnectService(reachable: true),
        ),
        targetStoreProvider.overrideWith((ref) => _fakeTargetStore()),
      ],
    );
    addTearDown(container.dispose);

    final store = await container.read(targetStoreProvider.future);
    await store.saveTarget(
      const ConnectTarget(host: '192.168.2.90', appUsername: ''),
    );

    await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

    final state = container.read(connectNotifierProvider);
    expect(state.phase, ConnectPhase.connected);
    expect(state.session?.host, '192.168.2.90');
    expect(state.savedHost, '192.168.2.90');
  });

  test(
    'reconnectOnOpen fails with a could-not-reach message when the saved host is offline',
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

      final store = await container.read(targetStoreProvider.future);
      await store.saveTarget(
        const ConnectTarget(host: '192.168.2.90', appUsername: ''),
      );

      await container.read(connectNotifierProvider.notifier).reconnectOnOpen();

      final state = container.read(connectNotifierProvider);
      expect(state.phase, ConnectPhase.failed);
      expect(state.savedHost, '192.168.2.90');
      expect(state.failureCause, contains('Could not reach'));
    },
  );

  test(
    'reconnectOnOpen with nothing saved fails without a saved host',
    () async {
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
    },
  );
}
