import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('openTextFiles maps selected file names, text, and paths', () async {
    final gateway = _FakeNativeFileDialogGateway(
      pickFilesResult: <PickedFileData>[
        PickedFileData(
          name: 'a.cnl',
          path: '/tmp/a.cnl',
          bytes: Uint8List.fromList('alpha'.codeUnits),
        ),
        PickedFileData(
          name: 'b.txt',
          path: '/tmp/b.txt',
          bytes: Uint8List.fromList('beta'.codeUnits),
        ),
      ],
    );

    final result = await FilePickerNativeFileBackend(
      gateway: gateway,
    ).openTextFiles();

    expect(gateway.lastAllowMultiple, isTrue);
    expect(gateway.lastLoadBytes, isTrue);
    expect(gateway.lastAllowedExtensions, <String>['cnl', 'txt']);
    expect(result, hasLength(2));
    expect(result!.first.name, 'a.cnl');
    expect(result.first.path, '/tmp/a.cnl');
    expect(result.first.text, 'alpha');
    expect(result.last.name, 'b.txt');
    expect(result.last.text, 'beta');
  });

  test('openDatasetImport uses neuromorphic dataset extensions', () async {
    final gateway = _FakeNativeFileDialogGateway(
      pickFilesResult: <PickedFileData>[
        PickedFileData(
          name: 'events.aedat',
          path: '/tmp/events.aedat',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      ],
    );

    final result = await FilePickerNativeFileBackend(
      gateway: gateway,
    ).openDatasetImport();

    expect(gateway.lastAllowMultiple, isFalse);
    expect(gateway.lastLoadBytes, isTrue);
    expect(gateway.lastAllowedExtensions, kDatasetImportAllowedExtensions);
    expect(result?.name, 'events.aedat');
    expect(result?.path, '/tmp/events.aedat');
    expect(result?.bytes, Uint8List.fromList(<int>[1, 2, 3]));
  });

  test('openWorkspaceFile returns null when the picker is cancelled', () async {
    final gateway = _FakeNativeFileDialogGateway(pickFilesResult: null);

    final result = await FilePickerNativeFileBackend(
      gateway: gateway,
    ).openWorkspaceFile();

    expect(result, isNull);
  });

  test('saveTextFile maps picker cancellation to cancelled result', () async {
    final gateway = _FakeNativeFileDialogGateway(savePathResult: null);

    final result = await FilePickerNativeFileBackend(
      gateway: gateway,
    ).saveTextFile(suggestedName: 'a.cnl', contents: 'alpha');

    expect(result.outcome, SaveOutcome.cancelled);
  });

  test('saveWorkspaceFile maps gateway exceptions to failed result', () async {
    final gateway = _FakeNativeFileDialogGateway(
      saveError: StateError('disk unavailable'),
    );

    final result = await FilePickerNativeFileBackend(
      gateway: gateway,
    ).saveWorkspaceFile(suggestedName: 'session.nmtk', contents: '{}');

    expect(result.outcome, SaveOutcome.failed);
    expect(result.message, contains('disk unavailable'));
  });

  test('saveWorkspaceFile passes UTF-8 bytes to the gateway', () async {
    final gateway = _FakeNativeFileDialogGateway(
      savePathResult: '/tmp/ws.nmtk',
    );

    final result = await FilePickerNativeFileBackend(
      gateway: gateway,
    ).saveWorkspaceFile(suggestedName: 'session.nmtk', contents: '{"v":1}');

    expect(result.outcome, SaveOutcome.saved);
    expect(result.path, '/tmp/ws.nmtk');
    expect(gateway.lastSuggestedName, 'session');
    expect(gateway.lastAllowedExtensions, <String>['nmtk']);
    expect(String.fromCharCodes(gateway.lastSavedBytes!), '{"v":1}');
  });

  test(
    'saveWorkspaceFile strips a pre-suffixed .nmtk to avoid double extension',
    () async {
      final gateway = _FakeNativeFileDialogGateway(
        savePathResult: '/tmp/my-workspace.nmtk',
      );

      await FilePickerNativeFileBackend(
        gateway: gateway,
      ).saveWorkspaceFile(suggestedName: 'my-workspace.NMTK', contents: '{}');

      expect(gateway.lastSuggestedName, 'my-workspace');
    },
  );

  test('saveBinaryFile passes raw bytes to the gateway', () async {
    final gateway = _FakeNativeFileDialogGateway(
      savePathResult: '/tmp/network.nir',
    );
    final payload = Uint8List.fromList(<int>[0x89, 0x48, 0x44, 0x46]);

    final result = await FilePickerNativeFileBackend(gateway: gateway)
        .saveBinaryFile(
          suggestedName: 'network.nir',
          bytes: payload,
          allowedExtensions: const <String>['nir'],
        );

    expect(result.outcome, SaveOutcome.saved);
    expect(result.path, '/tmp/network.nir');
    expect(gateway.lastSuggestedName, 'network.nir');
    expect(gateway.lastAllowedExtensions, const <String>['nir']);
    expect(gateway.lastSavedBytes, payload);
  });

  test('default gateway uses file_picker on macOS', () {
    expect(
      createDefaultNativeFileDialogGateway(
        platform: TargetPlatform.macOS,
        isWeb: false,
      ),
      isA<FilePickerDialogGateway>(),
    );
  });

  test('default gateway keeps file_picker on non-macOS and web', () {
    expect(
      createDefaultNativeFileDialogGateway(
        platform: TargetPlatform.windows,
        isWeb: false,
      ),
      isA<FilePickerDialogGateway>(),
    );
    expect(
      createDefaultNativeFileDialogGateway(
        platform: TargetPlatform.macOS,
        isWeb: true,
      ),
      isA<FilePickerDialogGateway>(),
    );
  });

  test('FilePickerDialogGateway installs Windows desktop implementation', () {
    FilePickerDialogGateway.debugEnsureRegisteredForTests(
      TargetPlatform.windows,
    );

    expect(FilePickerPlatform.instance, isA<FilePickerWindows>());
    FilePickerDialogGateway.debugResetRegistrationForTests();
  });

  test('FilePickerDialogGateway installs macOS desktop implementation', () {
    FilePickerDialogGateway.debugEnsureRegisteredForTests(TargetPlatform.macOS);

    expect(FilePickerPlatform.instance, isA<FilePickerMacOS>());
    FilePickerDialogGateway.debugResetRegistrationForTests();
  });

  test(
    'FilePickerDialogGateway installs Linux desktop implementation',
    () {
      FilePickerDialogGateway.debugEnsureRegisteredForTests(
        TargetPlatform.linux,
      );

      expect(FilePickerPlatform.instance, isA<FilePickerLinux>());
      FilePickerDialogGateway.debugResetRegistrationForTests();
    },
    // FilePickerLinux.registerWith() opens a real DBus session client,
    // which needs a Linux UID and throws on other host OSes.
    skip: !Platform.isLinux,
  );
}

class _FakeNativeFileDialogGateway implements NativeFileDialogGateway {
  _FakeNativeFileDialogGateway({
    this.pickFilesResult,
    this.savePathResult,
    this.saveError,
  });

  final List<PickedFileData>? pickFilesResult;
  final String? savePathResult;
  final Object? saveError;

  bool? lastAllowMultiple;
  bool? lastLoadBytes;
  List<String>? lastAllowedExtensions;
  String? lastSuggestedName;
  Uint8List? lastSavedBytes;

  @override
  Future<List<PickedFileData>?> pickFiles({
    required bool allowMultiple,
    required List<String> allowedExtensions,
    bool loadBytes = true,
  }) async {
    lastAllowMultiple = allowMultiple;
    lastLoadBytes = loadBytes;
    lastAllowedExtensions = allowedExtensions;
    return pickFilesResult;
  }

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) async {
    final error = saveError;
    if (error != null) {
      throw error;
    }
    lastSuggestedName = suggestedName;
    lastAllowedExtensions = allowedExtensions;
    lastSavedBytes = bytes;
    return savePathResult;
  }
}
