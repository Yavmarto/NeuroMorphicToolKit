import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:neuro_toolkit/features/neurocnl/services/workspace_cache_storage_base.dart';

WorkspaceCacheStorage createWorkspaceCacheStorage() =>
    FileWorkspaceCacheStorage();

class FileWorkspaceCacheStorage implements WorkspaceCacheStorage {
  FileWorkspaceCacheStorage({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const _directoryName = 'neurocnl';
  static const _fileName = 'workspace-cache-v1.json';
  final Future<Directory> Function() _supportDirectory;

  Future<File> _file() async {
    final supportDirectory = await _supportDirectory();
    return File(
      [
        supportDirectory.path,
        _directoryName,
        _fileName,
      ].join(Platform.pathSeparator),
    );
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    final file = await _file();
    await file.parent.create(recursive: true);

    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(value, flush: true);

    if (await backup.exists()) {
      await backup.delete();
    }

    final hadExisting = await file.exists();
    if (hadExisting) {
      await file.rename(backup.path);
    }

    try {
      await temporary.rename(file.path);
      if (await backup.exists()) {
        await backup.delete();
      }
    } on Object {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}
