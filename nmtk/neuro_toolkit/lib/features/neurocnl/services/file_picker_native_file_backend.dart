import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/desktop_file_picker_registrar.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/picked_save_path_writer.dart';

class PickedFileData {
  const PickedFileData({required this.name, required this.bytes, this.path});

  final String name;
  final Uint8List bytes;
  final String? path;
}

abstract class NativeFileDialogGateway {
  Future<List<PickedFileData>?> pickFiles({
    required bool allowMultiple,
    required List<String> allowedExtensions,
    bool loadBytes = true,
  });

  Future<String?> saveFile({
    required String suggestedName,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  });
}

class FilePickerDialogGateway implements NativeFileDialogGateway {
  const FilePickerDialogGateway();

  static TargetPlatform? debugOverridePlatform;
  static bool _desktopFilePickerRegistered = false;
  static bool _macOSEntitlementChecksSkipped = false;

  static void _ensureRegistered() {
    if (kIsWeb || _desktopFilePickerRegistered) {
      return;
    }
    _desktopFilePickerRegistered = registerDesktopFilePicker(
      debugOverridePlatform ?? defaultTargetPlatform,
    );
  }

  @visibleForTesting
  static void debugResetRegistrationForTests() {
    _desktopFilePickerRegistered = false;
    _macOSEntitlementChecksSkipped = false;
    debugOverridePlatform = null;
  }

  @visibleForTesting
  static void debugEnsureRegisteredForTests(TargetPlatform platform) {
    debugOverridePlatform = platform;
    _desktopFilePickerRegistered = false;
    _macOSEntitlementChecksSkipped = false;
    _ensureRegistered();
  }

  Future<void> _preparePicker() async {
    _ensureRegistered();
    if (kIsWeb ||
        _macOSEntitlementChecksSkipped ||
        (debugOverridePlatform ?? defaultTargetPlatform) !=
            TargetPlatform.macOS) {
      return;
    }

    // Runner already declares the user-selected file entitlements in Xcode.
    // Skip file_picker's runtime probe so local macOS runs do not fail before
    // the native dialog opens.
    await FilePicker.skipEntitlementsChecks();
    _macOSEntitlementChecksSkipped = true;
  }

  @override
  Future<List<PickedFileData>?> pickFiles({
    required bool allowMultiple,
    required List<String> allowedExtensions,
    bool loadBytes = true,
  }) async {
    await _preparePicker();
    final result = await FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      allowedExtensions: allowedExtensions,
      type: FileType.custom,
      withData: loadBytes,
    );
    if (result == null) {
      return null;
    }
    final pickedFiles = <PickedFileData>[];
    for (var index = 0; index < result.files.length; index += 1) {
      final file = result.files[index];
      final bytes = loadBytes
          ? file.bytes ?? await result.xFiles[index].readAsBytes()
          : Uint8List(0);
      pickedFiles.add(
        PickedFileData(name: file.name, bytes: bytes, path: file.path),
      );
    }
    return pickedFiles;
  }

  @override
  Future<String?> saveFile({
    required String suggestedName,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) async {
    await _preparePicker();
    final path = await FilePicker.saveFile(
      allowedExtensions: allowedExtensions,
      bytes: bytes,
      fileName: suggestedName,
      type: FileType.custom,
    );
    if (kIsWeb && path == null) {
      // Browsers handle the download directly and do not expose a file path.
      return suggestedName;
    }
    await writePickedSavePathIfNeeded(path, bytes);
    return path;
  }
}

NativeFileDialogGateway createDefaultNativeFileDialogGateway({
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) {
  return const FilePickerDialogGateway();
}

const List<String> kDatasetImportAllowedExtensions = <String>[
  'aedat',
  'aedat4',
  'h5',
  'hdf5',
  'bin',
  'zip',
  'tar',
  'gz',
  'tgz',
];

class FilePickerNativeFileBackend implements NativeFileBackend {
  FilePickerNativeFileBackend({NativeFileDialogGateway? gateway})
    : gateway = gateway ?? createDefaultNativeFileDialogGateway();

  final NativeFileDialogGateway gateway;

  @override
  Future<List<OpenedTextFile>?> openTextFiles() async {
    final files = await gateway.pickFiles(
      allowMultiple: true,
      allowedExtensions: const <String>['cnl', 'txt'],
    );
    if (files == null) {
      return null;
    }
    return files
        .map(
          (file) => OpenedTextFile(
            name: file.name,
            path: file.path,
            text: utf8.decode(file.bytes),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<OpenedBinaryFile?> openDatasetImport() async {
    final files = await gateway.pickFiles(
      allowMultiple: false,
      allowedExtensions: kDatasetImportAllowedExtensions,
    );
    if (files == null || files.isEmpty) {
      return null;
    }
    final file = files.first;
    return OpenedBinaryFile(
      name: file.name,
      bytes: file.bytes,
      path: file.path,
    );
  }

  @override
  Future<OpenedTextFile?> openWorkspaceFile() async {
    final files = await gateway.pickFiles(
      allowMultiple: false,
      allowedExtensions: const <String>['nmtk'],
    );
    if (files == null || files.isEmpty) {
      return null;
    }
    final file = files.first;
    return OpenedTextFile(
      name: file.name,
      path: file.path,
      text: utf8.decode(file.bytes),
    );
  }

  @override
  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) {
    return _save(
      suggestedName: suggestedName,
      contents: contents,
      allowedExtensions: const <String>['cnl', 'txt'],
    );
  }

  @override
  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  }) {
    // ponytail: strip .nmtk here since allowedExtensions already declares it
    // below — the native save dialog re-appends allowedExtensions, so a name
    // that already ends in .nmtk would otherwise double to .nmtk.nmtk.
    final baseName = suggestedName.toLowerCase().endsWith('.nmtk')
        ? suggestedName.substring(0, suggestedName.length - 5)
        : suggestedName;
    return _save(
      suggestedName: baseName,
      contents: contents,
      allowedExtensions: const <String>['nmtk'],
    );
  }

  @override
  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) async {
    try {
      final path = await gateway.saveFile(
        suggestedName: suggestedName,
        allowedExtensions: allowedExtensions ?? const <String>['bin'],
        bytes: bytes,
      );
      if (path == null || path.isEmpty) {
        return const SaveResult(outcome: SaveOutcome.cancelled);
      }
      return SaveResult(outcome: SaveOutcome.saved, path: path);
    } catch (error) {
      return SaveResult(outcome: SaveOutcome.failed, message: error.toString());
    }
  }

  Future<SaveResult> _save({
    required String suggestedName,
    required String contents,
    required List<String> allowedExtensions,
  }) async {
    try {
      final path = await gateway.saveFile(
        suggestedName: suggestedName,
        allowedExtensions: allowedExtensions,
        bytes: Uint8List.fromList(utf8.encode(contents)),
      );
      if (path == null) {
        return const SaveResult(outcome: SaveOutcome.cancelled);
      }
      return SaveResult(outcome: SaveOutcome.saved, path: path);
    } catch (error) {
      return SaveResult(
        outcome: SaveOutcome.failed,
        message: 'File save failed: $error',
      );
    }
  }
}
