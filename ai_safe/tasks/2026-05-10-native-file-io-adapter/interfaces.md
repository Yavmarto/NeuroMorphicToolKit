# Interfaces

Document only signatures, types, schemas, and stub bodies here.

## file_adapter.dart

```dart
import 'dart:convert';

enum SaveOutcome { saved, cancelled, failed }

class SaveResult {
  const SaveResult({
    required this.outcome,
    this.path,
    this.message,
  });

  final SaveOutcome outcome;
  final String? path;
  final String? message;
}

class OpenedTextFile {
  const OpenedTextFile({
    required this.name,
    required this.text,
    this.path,
  });

  final String name;
  final String text;
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

  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  });

  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required String contents,
  });
}

class FileAdapter {
  const FileAdapter(this.backend);

  final NativeFileBackend backend;

  Future<List<OpenedTextFile>> openTextFiles() async {
    throw UnimplementedError();
  }

  Future<OpenedWorkspaceFile?> openWorkspaceFile() async {
    throw UnimplementedError();
  }

  Future<SaveResult> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    throw UnimplementedError();
  }

  Future<SaveResult> saveWorkspaceFile({
    required String suggestedName,
    required Map<String, Object?> payload,
  }) async {
    throw UnimplementedError();
  }
}
```

## file_adapter_test.dart

```dart
import 'package:test/test.dart';

import 'file_adapter.dart';

void main() {
  // Add tests for the examples in examples.md.
}
```

## Reference Notes

- `openTextFiles()` should normalize backend `null` to an empty list.
- `openWorkspaceFile()` must decode JSON text and reject non-object JSON.
- `saveWorkspaceFile()` must JSON-encode the provided payload before passing it to the backend save method.
