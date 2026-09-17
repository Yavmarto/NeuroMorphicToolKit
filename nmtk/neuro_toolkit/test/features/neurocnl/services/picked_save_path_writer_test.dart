import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/picked_save_path_writer.dart';

void main() {
  group('writeToPath', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'picked_save_path_writer_test',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writes bytes straight to the given path with no dialog', () async {
      final path = '${tempDir.path}/workspace.json';
      final ok = await writeToPath(
        path,
        Uint8List.fromList(utf8.encode('{"a":1}')),
      );

      expect(ok, isTrue);
      expect(File(path).readAsStringSync(), equals('{"a":1}'));
    });

    test('returns false and does not throw for a null/empty path', () async {
      expect(await writeToPath(null, Uint8List(0)), isFalse);
      expect(await writeToPath('', Uint8List(0)), isFalse);
    });

    test(
      'returns false and does not throw when the directory does not exist',
      () async {
        final ok = await writeToPath(
          '${tempDir.path}/does-not-exist/workspace.json',
          Uint8List(0),
        );
        expect(ok, isFalse);
      },
    );
  });

  group('mergeJsonFile', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'picked_save_path_writer_test',
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates the file from an empty base when none exists yet', () async {
      final path = '${tempDir.path}/workspace.json';

      final ok = await mergeJsonFile(
        path,
        (current) => {...current, 'workspace': 'w1'},
      );

      expect(ok, isTrue);
      final decoded = jsonDecode(File(path).readAsStringSync());
      expect(decoded, equals({'workspace': 'w1'}));
    });

    test('preserves a section the caller does not own — mirrors two '
        'independent autosave writers sharing one file', () async {
      final path = '${tempDir.path}/workspace.json';

      // Writer A (e.g. workspace-section autosave) writes first.
      await mergeJsonFile(path, (current) => {...current, 'workspace': 'w1'});
      // Writer B (e.g. canvas-section autosave) writes next — must not
      // clobber writer A's 'workspace' key.
      final ok = await mergeJsonFile(
        path,
        (current) => {...current, 'canvas': 'c1'},
      );

      expect(ok, isTrue);
      final decoded = jsonDecode(File(path).readAsStringSync());
      expect(decoded, equals({'workspace': 'w1', 'canvas': 'c1'}));
    });

    test('returns false for a null/empty path', () async {
      expect(await mergeJsonFile(null, (c) => c), isFalse);
      expect(await mergeJsonFile('', (c) => c), isFalse);
    });

    test('starts from an empty base rather than throwing when the existing '
        'file on disk is not valid JSON', () async {
      final path = '${tempDir.path}/workspace.json';
      File(path).writeAsStringSync('not json');

      final ok = await mergeJsonFile(
        path,
        (current) => {...current, 'workspace': 'w1'},
      );

      expect(ok, isTrue);
      final decoded = jsonDecode(File(path).readAsStringSync());
      expect(decoded, equals({'workspace': 'w1'}));
    });
  });
}
