import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/bundle_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BundleManager', () {
    late BundleManager bundleManager;

    setUp(() {
      bundleManager = BundleManager();
      bundleManager.clearCache();
    });

    test('isBundled returns false in test environment', () {
      expect(bundleManager.isBundled, isFalse);
    });

    test('modulesBasePath in dev mode points to repo root', () async {
      final path = await bundleManager.modulesBasePath;
      // In tests, Directory.current is usually the project root (nmtk/neuro_toolkit)
      // so modulesBasePath should be ../..
      final expected = p.normalize(p.join(Directory.current.path, '..', '..'));
      expect(path, expected);
    });

    test('findPython finds system python', () async {
      final python = await bundleManager.findPython();
      expect(python, isNotNull);
      expect(await bundleManager.isPythonAvailable, isTrue);
    });

    test('pythonVersion returns a version string', () async {
      final version = await bundleManager.pythonVersion;
      if (await bundleManager.isPythonAvailable) {
        expect(version, isNotNull);
        expect(version, isNotEmpty);
      }
    });

    test('needsExtraction is false in dev mode', () async {
      expect(await bundleManager.needsExtraction, isFalse);
    });
  });
}
