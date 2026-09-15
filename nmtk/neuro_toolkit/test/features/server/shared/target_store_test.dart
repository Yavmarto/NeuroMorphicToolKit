import 'package:flutter_test/flutter_test.dart';
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

class _TrackingSecretStorage implements ConnectSecretStorage {
  _TrackingSecretStorage({this.onRead, this.onWrite});

  final void Function()? onRead;
  final void Function(String key)? onWrite;

  @override
  Future<String?> read(String key) async {
    onRead?.call();
    return null;
  }

  @override
  Future<void> write(String key, String value) async => onWrite?.call(key);

  @override
  Future<void> delete(String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TargetStore> newStore() async {
    SharedPreferences.setMockInitialValues({});
    return TargetStore(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: _FakeSecretStorage(),
    );
  }

  test(
    'save then load round-trips host, username, session token, credential',
    () async {
      final store = await newStore();
      await store.saveTarget(
        const ConnectTarget(
          host: '192.168.2.90',
          appUsername: 'ada',
          sessionToken: 'tok-1',
          credential: 'hunter2',
        ),
      );

      final targets = await store.loadTargets();
      expect(targets, hasLength(1));
      expect(targets.single.host, '192.168.2.90');
      expect(targets.single.appUsername, 'ada');
      expect(targets.single.sessionToken, 'tok-1');
      expect(targets.single.credential, 'hunter2');
    },
  );

  test('credential never lands in plain shared preferences', () async {
    final store = await newStore();
    await store.saveTarget(
      const ConnectTarget(
        host: '192.168.2.90',
        appUsername: 'ada',
        sessionToken: 'tok-1',
        credential: 'hunter2',
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('connect.targets.v1'), isNot(contains('hunter2')));
  });

  test(
    'saving the same host again replaces it instead of duplicating',
    () async {
      final store = await newStore();
      await store.saveTarget(
        const ConnectTarget(
          host: 'a.example',
          appUsername: 'ada',
          sessionToken: 'tok-1',
        ),
      );
      await store.saveTarget(
        const ConnectTarget(
          host: 'a.example',
          appUsername: 'ada',
          sessionToken: 'tok-2',
        ),
      );

      final targets = await store.loadTargets();
      expect(targets, hasLength(1));
      expect(targets.single.sessionToken, 'tok-2');
    },
  );

  test('loadLastTarget returns the most recently saved target', () async {
    final store = await newStore();
    await store.saveTarget(
      const ConnectTarget(
        host: 'old.example',
        appUsername: 'ada',
        sessionToken: 'tok-1',
      ),
    );
    await store.saveTarget(
      const ConnectTarget(
        host: 'new.example',
        appUsername: 'ada',
        sessionToken: 'tok-2',
      ),
    );

    final last = await store.loadLastTarget();
    expect(last?.host, 'new.example');
  });

  test(
    'loadLastHost returns the most recently saved host without secure reads',
    () async {
      var secureReads = 0;
      final trackingStorage = _TrackingSecretStorage(
        onRead: () => secureReads++,
      );
      final storeWithTracking = TargetStore(
        preferences: await SharedPreferences.getInstance(),
        secureStorage: trackingStorage,
      );
      await storeWithTracking.saveTarget(
        const ConnectTarget(
          host: 'old.example',
          appUsername: 'ada',
          sessionToken: 'tok-1',
          credential: 'secret',
        ),
      );
      await storeWithTracking.saveTarget(
        const ConnectTarget(host: 'new.example', appUsername: ''),
      );

      expect(await storeWithTracking.loadLastHost(), 'new.example');
      expect(secureReads, 0);
    },
  );

  test('saveTarget skips secure storage when there are no secrets', () async {
    final secureWrites = <String>[];
    final store = TargetStore(
      preferences: await SharedPreferences.getInstance(),
      secureStorage: _TrackingSecretStorage(onWrite: secureWrites.add),
    );
    await store.saveTarget(
      const ConnectTarget(host: '192.168.2.90', appUsername: ''),
    );

    expect(secureWrites, isEmpty);
    expect(await store.loadLastHost(), '192.168.2.90');
  });

  test('forgetTarget removes both the prefs entry and the secret', () async {
    final store = await newStore();
    await store.saveTarget(
      const ConnectTarget(
        host: 'a.example',
        appUsername: 'ada',
        sessionToken: 'tok-1',
      ),
    );
    await store.forgetTarget('a.example');

    expect(await store.loadTargets(), isEmpty);
  });
}
