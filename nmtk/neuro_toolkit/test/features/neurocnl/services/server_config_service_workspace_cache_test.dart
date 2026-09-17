import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/workspace_cache_storage.dart';
import 'package:neuro_toolkit/features/neurocnl/services/workspace_cache_storage_io.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryWorkspaceCacheStorage implements WorkspaceCacheStorage {
  String? value;
  bool failWrites = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    if (failWrites) {
      throw const FileSystemException('test write failure');
    }
    this.value = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(ServerConfigService.debugResetForTests);

  test('migrates an oversized workspace without losing its contents', () async {
    final weights = List<double>.filled(900000, 0.25);
    final legacy = jsonEncode(<String, Object?>{
      'version': 1,
      'workspace': <String, Object?>{
        'files': <Object?>[
          <String, Object?>{
            'id': 'untitled-1',
            'canonicalDocument': <String, Object?>{
              'ir_json': <String, Object?>{
                'connections': <Object?>[
                  <String, Object?>{'weight': weights},
                ],
              },
            },
          },
        ],
      },
    });
    expect(legacy.length, greaterThan(4 * 1024 * 1024));

    SharedPreferences.setMockInitialValues(<String, Object>{
      ServerConfigService.workspaceCacheKey: legacy,
      'launcher_control_api_base_url': 'http://192.168.2.51:8090',
    });
    final storage = _MemoryWorkspaceCacheStorage();
    ServerConfigService.debugResetForTests();
    ServerConfigService.debugUseWorkspaceCacheStorage(storage);

    await ServerConfigService.initialize();

    expect(storage.value, legacy);
    expect(
      ServerConfigService.getString(ServerConfigService.workspaceCacheKey),
      legacy,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(ServerConfigService.workspaceCacheKey),
      isFalse,
    );
    expect(
      preferences.getString('launcher_control_api_base_url'),
      'http://192.168.2.51:8090',
    );

    ServerConfigService.debugResetForTests();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ServerConfigService.debugUseWorkspaceCacheStorage(storage);
    await ServerConfigService.initialize();
    expect(
      ServerConfigService.getString(ServerConfigService.workspaceCacheKey),
      legacy,
      reason: 'The migrated workspace must survive a process restart.',
    );
  });

  test(
    'keeps the legacy workspace when migration cannot be verified',
    () async {
      const legacy = '{"version":1,"workspace":{"files":[]}}';
      SharedPreferences.setMockInitialValues(<String, Object>{
        ServerConfigService.workspaceCacheKey: legacy,
      });
      final storage = _MemoryWorkspaceCacheStorage()..failWrites = true;
      ServerConfigService.debugResetForTests();
      ServerConfigService.debugUseWorkspaceCacheStorage(storage);

      await ServerConfigService.initialize();

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(ServerConfigService.workspaceCacheKey),
        legacy,
      );
      expect(
        ServerConfigService.getString(ServerConfigService.workspaceCacheKey),
        legacy,
      );
    },
  );

  test(
    'file-backed workspace merges preserve independently owned sections',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = _MemoryWorkspaceCacheStorage();
      ServerConfigService.debugResetForTests();
      ServerConfigService.debugUseWorkspaceCacheStorage(storage);
      await ServerConfigService.initialize();

      await Future.wait(<Future<void>>[
        ServerConfigService.mergeJsonString(
          ServerConfigService.workspaceCacheKey,
          (current) => <String, Object?>{
            ...current,
            'workspace': <String, Object?>{'name': 'Wake word'},
          },
        ),
        ServerConfigService.mergeJsonString(
          ServerConfigService.workspaceCacheKey,
          (current) => <String, Object?>{
            ...current,
            'canvas': <String, Object?>{'trainingHistory': <Object?>[]},
          },
        ),
      ]);

      final decoded = jsonDecode(storage.value!) as Map<String, dynamic>;
      expect(decoded['workspace'], <String, Object?>{'name': 'Wake word'});
      expect(decoded['canvas'], <String, Object?>{
        'trainingHistory': <Object?>[],
      });
    },
  );

  test('native workspace storage atomically replaces its cache file', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'neurocnl-workspace-cache-test',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final storage = FileWorkspaceCacheStorage(
      supportDirectory: () async => temporaryDirectory,
    );

    await storage.write('{"version":1}');
    await storage.write('{"version":2,"workspace":{"files":[]}}');

    expect(await storage.read(), '{"version":2,"workspace":{"files":[]}}');
    final cacheDirectory = Directory(
      [temporaryDirectory.path, 'neurocnl'].join(Platform.pathSeparator),
    );
    expect(
      cacheDirectory
          .listSync()
          .map((entry) => entry.uri.pathSegments.last)
          .toList(),
      <String>['workspace-cache-v1.json'],
    );
  });
}
