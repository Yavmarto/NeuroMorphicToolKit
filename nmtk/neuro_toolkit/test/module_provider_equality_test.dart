import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';

void main() {
  group('Module equality', () {
    Module base() => Module(
      id: 'neurocnl',
      name: 'NeuroCNL',
      description: 'CNL Studio',
      directory: '/opt/modules/neurocnl',
      status: ModuleStatus.installed,
      installProgress: 1.0,
      version: '1.0.0',
      remoteVersion: '1.0.0',
    );

    test('two modules with identical state are equal', () {
      final a = base();
      final b = base();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('status change breaks equality', () {
      final a = base();
      final b = base()..status = ModuleStatus.running;
      expect(a, isNot(equals(b)));
    });

    test('installProgress change breaks equality', () {
      final a = base();
      final b = base()..installProgress = 0.5;
      expect(a, isNot(equals(b)));
    });

    test('healthStatus change breaks equality', () {
      final a = base();
      final b = base()..healthStatus = 'degraded';
      expect(a, isNot(equals(b)));
    });

    test('version change breaks equality', () {
      final a = base();

      // Simulate a version bump coming in from the API.
      final c = Module(
        id: a.id,
        name: a.name,
        description: a.description,
        directory: a.directory,
        status: a.status,
        installProgress: a.installProgress,
        version: '1.0.1', // changed
        remoteVersion: a.remoteVersion,
      );
      expect(a, isNot(equals(c)));
    });

    test('unrelated field change (description) does not affect equality', () {
      final a = base();
      final b = Module(
        id: a.id,
        name: a.name,
        description: 'Updated description', // not in == key
        directory: a.directory,
        status: a.status,
        installProgress: a.installProgress,
        version: a.version,
        remoteVersion: a.remoteVersion,
      );
      expect(a, equals(b));
    });
  });
}
