import 'dart:convert';
import 'dart:typed_data';

enum SaveOutcome { saved, cancelled, failed }

class SaveResult {
  const SaveResult({required this.outcome, this.path, this.message});

  final SaveOutcome outcome;
  final String? path;
  final String? message;
}

class OpenedTextFile {
  const OpenedTextFile({required this.name, required this.text, this.path});

  final String name;
  final String text;
  final String? path;
}

class OpenedBinaryFile {
  const OpenedBinaryFile({required this.name, required this.bytes, this.path});

  final String name;
  final Uint8List bytes;
  final String? path;
}

class OpenedWorkspaceFile {
  const OpenedWorkspaceFile({
    required this.name,
    required this.payload,
    this.path,
  });

  final String name;
  final Map<String, Object?> payload;
  final String? path;
}

abstract class NativeFileBackend {
  Future<List<OpenedTextFile>?> openTextFiles();

  Future<OpenedTextFile?> openWorkspaceFile();

  Future<OpenedBinaryFile?> openDatasetImport();

  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  });

  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  });

  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  });
}

class FileAdapter {
  const FileAdapter(this.backend);

  final NativeFileBackend backend;

  Future<List<OpenedTextFile>> openTextFiles() async {
    return await backend.openTextFiles() ?? const <OpenedTextFile>[];
  }

  Future<OpenedBinaryFile?> openDatasetImport() {
    return backend.openDatasetImport();
  }

  Future<OpenedWorkspaceFile?> openWorkspaceFile() async {
    final openedFile = await backend.openWorkspaceFile();
    if (openedFile == null) {
      return null;
    }

    final decoded = jsonDecode(openedFile.text);
    if (decoded is! Map) {
      throw const FormatException('Workspace JSON must be a top-level object.');
    }

    return OpenedWorkspaceFile(
      name: openedFile.name,
      payload: Map<String, Object?>.from(decoded),
      path: openedFile.path,
    );
  }

  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) {
    return backend.saveTextFile(
      suggestedName: suggestedName,
      contents: contents,
    );
  }

  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required Map<String, Object?> payload,
  }) {
    final contents = '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
    return backend.saveWorkspaceFile(
      suggestedName: suggestedName,
      contents: contents,
    );
  }

  Future<SaveResult> saveBinaryFile({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
  }) {
    return backend.saveBinaryFile(
      suggestedName: suggestedName,
      bytes: bytes,
      allowedExtensions:
          allowedExtensions ?? _allowedExtensionsFor(suggestedName),
    );
  }

  List<String> _allowedExtensionsFor(String suggestedName) {
    final dotIndex = suggestedName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == suggestedName.length - 1) {
      return const <String>['bin'];
    }
    return <String>[suggestedName.substring(dotIndex + 1)];
  }
}
