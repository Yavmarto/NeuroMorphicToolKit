import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';

void main() {
  group('FileAdapter.openTextFiles', () {
    test(
      'returns an empty list when the backend reports cancellation',
      () async {
        final backend = _FakeNativeFileBackend(openTextFilesResult: null);
        final adapter = FileAdapter(backend);

        final result = await adapter.openTextFiles();

        expect(result, isEmpty);
      },
    );

    test('preserves empty, single, and multiple opened text files', () async {
      final emptyBackend = _FakeNativeFileBackend(
        openTextFilesResult: const <OpenedTextFile>[],
      );
      expect(await FileAdapter(emptyBackend).openTextFiles(), isEmpty);

      const singleFile = OpenedTextFile(
        name: 'model.cnl',
        text: 'neuron A',
        path: '/tmp/model.cnl',
      );
      final singleBackend = _FakeNativeFileBackend(
        openTextFilesResult: const <OpenedTextFile>[singleFile],
      );
      expect(await FileAdapter(singleBackend).openTextFiles(), [singleFile]);

      const secondFile = OpenedTextFile(name: 'notes.txt', text: 'hello');
      final multipleBackend = _FakeNativeFileBackend(
        openTextFilesResult: const <OpenedTextFile>[singleFile, secondFile],
      );
      expect(await FileAdapter(multipleBackend).openTextFiles(), [
        singleFile,
        secondFile,
      ]);
    });
  });

  group('FileAdapter.openWorkspaceFile', () {
    test(
      'returns a parsed workspace object with original name and path',
      () async {
        final backend = _FakeNativeFileBackend(
          openWorkspaceFileResult: const OpenedTextFile(
            name: 'session.nmtk',
            text: '{ "version": 1, "files": [] }',
            path: '/tmp/session.nmtk',
          ),
        );

        final result = await FileAdapter(backend).openWorkspaceFile();

        expect(result, isNotNull);
        expect(result!.name, 'session.nmtk');
        expect(result.path, '/tmp/session.nmtk');
        expect(result.payload, <String, Object?>{
          'version': 1,
          'files': <Object?>[],
        });
      },
    );

    test('returns null when the backend reports cancellation', () async {
      final backend = _FakeNativeFileBackend(openWorkspaceFileResult: null);

      expect(await FileAdapter(backend).openWorkspaceFile(), isNull);
    });

    test('throws FormatException for invalid JSON text', () async {
      final backend = _FakeNativeFileBackend(
        openWorkspaceFileResult: const OpenedTextFile(
          name: 'session.nmtk',
          text: '{ invalid json',
        ),
      );

      expect(FileAdapter(backend).openWorkspaceFile, throwsFormatException);
    });

    test('throws FormatException for non-object JSON text', () async {
      final backend = _FakeNativeFileBackend(
        openWorkspaceFileResult: const OpenedTextFile(
          name: 'session.nmtk',
          text: '[]',
        ),
      );

      expect(FileAdapter(backend).openWorkspaceFile, throwsFormatException);
    });
  });

  group('FileAdapter.saveTextFile', () {
    test(
      'passes through text save arguments and preserves backend result',
      () async {
        const results = <SaveResult>[
          SaveResult(outcome: SaveOutcome.saved, path: '/tmp/model.cnl'),
          SaveResult(outcome: SaveOutcome.cancelled),
          SaveResult(outcome: SaveOutcome.failed, message: 'permission denied'),
        ];

        for (final saveResult in results) {
          final backend = _FakeNativeFileBackend(
            saveTextFileResult: saveResult,
          );

          final result = await FileAdapter(
            backend,
          ).saveTextFile(suggestedName: 'model.cnl', contents: 'neuron A');

          expect(identical(result, saveResult), isTrue);
          expect(backend.lastTextSuggestedName, 'model.cnl');
          expect(backend.lastTextContents, 'neuron A');
        }
      },
    );
  });

  group('FileAdapter.saveWorkspaceFile', () {
    test(
      'passes stable pretty JSON with a trailing newline to the backend',
      () async {
        final backend = _FakeNativeFileBackend(
          saveWorkspaceFileResult: const SaveResult(
            outcome: SaveOutcome.saved,
            path: '/tmp/session.nmtk',
          ),
        );

        await FileAdapter(backend).saveWorkspaceFile(
          suggestedName: 'session.nmtk',
          payload: <String, Object?>{'version': 1},
        );

        expect(backend.lastWorkspaceSuggestedName, 'session.nmtk');
        expect(backend.lastWorkspaceContents, '{\n  "version": 1\n}\n');
      },
    );

    test('preserves backend cancellation and failure results', () async {
      const results = <SaveResult>[
        SaveResult(outcome: SaveOutcome.cancelled),
        SaveResult(outcome: SaveOutcome.failed, message: 'disk full'),
      ];

      for (final saveResult in results) {
        final backend = _FakeNativeFileBackend(
          saveWorkspaceFileResult: saveResult,
        );

        final result = await FileAdapter(backend).saveWorkspaceFile(
          suggestedName: 'session.nmtk',
          payload: <String, Object?>{'version': 1},
        );

        expect(identical(result, saveResult), isTrue);
      }
    });
  });

  group('FileAdapter.saveBinaryFile', () {
    test(
      'passes through binary save arguments and preserves backend result',
      () async {
        const saveResult = SaveResult(
          outcome: SaveOutcome.saved,
          path: '/tmp/network.nir',
        );
        final payload = Uint8List.fromList(<int>[0x89, 0x48, 0x44, 0x46]);
        final backend = _FakeNativeFileBackend(
          saveBinaryFileResult: saveResult,
        );

        final result = await FileAdapter(
          backend,
        ).saveBinaryFile(suggestedName: 'network.nir', bytes: payload);

        expect(identical(result, saveResult), isTrue);
        expect(backend.lastBinarySuggestedName, 'network.nir');
        expect(backend.lastBinaryBytes, payload);
        expect(backend.lastBinaryAllowedExtensions, const <String>['nir']);
      },
    );
  });
}

class _FakeNativeFileBackend implements NativeFileBackend {
  _FakeNativeFileBackend({
    this.openTextFilesResult,
    this.openWorkspaceFileResult,
    this.saveTextFileResult = const SaveResult(outcome: SaveOutcome.saved),
    this.saveWorkspaceFileResult = const SaveResult(outcome: SaveOutcome.saved),
    this.saveBinaryFileResult = const SaveResult(outcome: SaveOutcome.saved),
  });

  final List<OpenedTextFile>? openTextFilesResult;
  final OpenedTextFile? openWorkspaceFileResult;
  final SaveResult saveTextFileResult;
  final SaveResult saveWorkspaceFileResult;
  final SaveResult saveBinaryFileResult;

  String? lastTextSuggestedName;
  String? lastTextContents;
  String? lastWorkspaceSuggestedName;
  String? lastWorkspaceContents;
  String? lastBinarySuggestedName;
  Uint8List? lastBinaryBytes;
  List<String>? lastBinaryAllowedExtensions;

  @override
  Future<List<OpenedTextFile>?> openTextFiles() async {
    return openTextFilesResult;
  }

  @override
  Future<OpenedTextFile?> openWorkspaceFile() async {
    return openWorkspaceFileResult;
  }

  @override
  Future<OpenedBinaryFile?> openDatasetImport() async => null;

  @override
  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    lastTextSuggestedName = suggestedName;
    lastTextContents = contents;
    return saveTextFileResult;
  }

  @override
  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  }) async {
    lastWorkspaceSuggestedName = suggestedName;
    lastWorkspaceContents = contents;
    return saveWorkspaceFileResult;
  }

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) async {
    lastBinarySuggestedName = suggestedName;
    lastBinaryBytes = bytes;
    lastBinaryAllowedExtensions = allowedExtensions;
    return saveBinaryFileResult;
  }
}
