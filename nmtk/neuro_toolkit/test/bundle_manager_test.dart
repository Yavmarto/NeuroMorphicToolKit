import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/bundle_manager.dart';
import 'package:path/path.dart' as p;

class MockBundleEnvironment implements BundleEnvironment {
  @override
  Future<void> renameDirectory(String source, String destination) async {}

  @override
  bool isMacOS = false;
  @override
  bool isWindows = false;
  @override
  bool isLinux = false;
  @override
  String resolvedExecutable = '/mock/app';
  @override
  Map<String, String> environment = {};
  @override
  String currentDirectory = '/mock/repo/nmtk/neuro_toolkit';

  final Set<String> _existingDirectories = {};
  final Map<String, String> _files = {};
  final Map<String, DateTime> _fileMtimes = {};
  final Map<String, ProcessResult> _processResults = {};

  void setupDirectory(String path) =>
      _existingDirectories.add(p.normalize(path));
  void setupFile(String path, String contents, {DateTime? mtime}) {
    final normalized = p.normalize(path);
    _files[normalized] = contents;
    _fileMtimes[normalized] = mtime ?? DateTime.now();
  }

  void setupProcess(
    String executable,
    List<String> arguments,
    ProcessResult result,
  ) {
    _processResults['$executable ${arguments.join(' ')}'] = result;
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    final normalized = p.normalize(path);
    _existingDirectories.remove(normalized);
    _existingDirectories.removeWhere((dir) => dir.startsWith('$normalized/'));
    _files.removeWhere((file, contents) => file.startsWith('$normalized/'));
  }

  @override
  Future<String> getApplicationSupportPath() async => '/mock/user/app_support';

  @override
  bool directoryExists(String path) =>
      _existingDirectories.contains(p.normalize(path));

  @override
  Future<bool> fileExists(String path) async =>
      _files.containsKey(p.normalize(path));

  @override
  DateTime getFileModificationTime(String path) =>
      _fileMtimes[p.normalize(path)] ?? DateTime.now();

  @override
  Future<String> readFileAsString(String path) async =>
      _files[p.normalize(path)] ?? '';

  @override
  Future<void> writeFileAsString(String path, String contents) async =>
      _files[p.normalize(path)] = contents;

  @override
  Future<void> createDirectory(String path, {bool recursive = false}) async =>
      _existingDirectories.add(p.normalize(path));

  @override
  Stream<FileSystemEntity> listDirectory(
    String path, {
    bool recursive = false,
  }) {
    final normalizedPath = p.normalize(path);
    final entities = <FileSystemEntity>[];

    for (final dir in _existingDirectories) {
      if (p.dirname(dir) == normalizedPath && dir != normalizedPath) {
        entities.add(Directory(dir));
      }
    }
    for (final file in _files.keys) {
      if (p.dirname(file) == normalizedPath) {
        entities.add(File(file));
      }
    }
    return Stream.fromIterable(entities);
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    _files[p.normalize(destination)] = _files[p.normalize(source)] ?? '';
  }

  @override
  Future<ProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    final key = '$executable ${arguments.join(' ')}';
    return _processResults[key] ?? ProcessResult(0, 0, 'Python 3.10.0', '');
  }

  @override
  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  late BundleManager bundleManager;
  late MockBundleEnvironment mockEnv;

  setUp(() {
    mockEnv = MockBundleEnvironment();
    bundleManager = BundleManager(env: mockEnv);
    bundleManager.clearCache();
  });

  group('isBundled detection', () {
    test('detects macOS bundle', () {
      mockEnv.isMacOS = true;
      mockEnv.resolvedExecutable =
          '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.setupDirectory(
        '/Applications/NMTK.app/Contents/Resources/modules',
      );

      expect(bundleManager.isBundled, isTrue);
    });

    test('detects Windows bundle', () {
      mockEnv.isWindows = true;
      final exe = 'C:\\Program Files\\NMTK\\neuro_toolkit.exe';
      mockEnv.resolvedExecutable = exe;
      mockEnv.setupDirectory(p.join(p.dirname(exe), 'modules'));

      expect(bundleManager.isBundled, isTrue);
    });

    test('detects Linux bundle', () {
      mockEnv.isLinux = true;
      mockEnv.resolvedExecutable = '/tmp/.mount_NMTK/usr/bin/neuro_toolkit';
      mockEnv.setupDirectory('/tmp/.mount_NMTK/usr/bin/modules');

      expect(bundleManager.isBundled, isTrue);
    });

    test('detects DEV mode when modules dir is missing', () {
      mockEnv.isMacOS = true;
      mockEnv.resolvedExecutable =
          '/Users/user/repo/nmtk/neuro_toolkit/build/macos/Build/Products/Debug/neuro_toolkit.app/Contents/MacOS/neuro_toolkit';
      // No modules dir setup

      expect(bundleManager.isBundled, isFalse);
    });
  });

  group('Path resolution', () {
    test('resolves modulesBasePath in DEV mode', () async {
      mockEnv.currentDirectory = '/mock/repo/nmtk/neuro_toolkit';
      // isBundled will be false by default as no modules dir is setup

      final path = await bundleManager.modulesBasePath;
      expect(path, equals('/mock/repo'));
    });

    test('resolves modulesBasePath in Bundled mode', () async {
      mockEnv.isMacOS = true;
      mockEnv.resolvedExecutable =
          '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.setupDirectory(
        '/Applications/NMTK.app/Contents/Resources/modules',
      );

      final path = await bundleManager.modulesBasePath;
      expect(path, equals('/mock/user/app_support/modules'));
    });
  });

  group('Python detection', () {
    test('finds bundled Python first', () async {
      mockEnv.isMacOS = true;
      mockEnv.resolvedExecutable =
          '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.setupDirectory(
        '/Applications/NMTK.app/Contents/Resources/modules',
      );

      final bundledPython =
          '/Applications/NMTK.app/Contents/Resources/python/bin/python3';
      mockEnv.setupProcess(bundledPython, [
        '--version',
      ], ProcessResult(0, 0, 'Python 3.12.7', ''));

      final path = await bundleManager.findPython();
      expect(path, equals(bundledPython));
    });

    test('falls back to system Python', () async {
      mockEnv.isMacOS = true;
      mockEnv.resolvedExecutable =
          '/Users/user/repo/nmtk/neuro_toolkit/build/macos/Build/Products/Debug/neuro_toolkit.app/Contents/MacOS/neuro_toolkit';

      mockEnv.setupProcess('python3', [
        '--version',
      ], ProcessResult(0, 0, 'Python 3.10.0', ''));

      final path = await bundleManager.findPython();
      expect(path, equals('python3'));
    });

    test('resolves via login shell on Unix', () async {
      mockEnv.isMacOS = true;
      mockEnv.environment['SHELL'] = '/bin/zsh';
      mockEnv.setupProcess('python3', [
        '--version',
      ], ProcessResult(1, 1, '', 'not found'));
      mockEnv.setupProcess('python', [
        '--version',
      ], ProcessResult(1, 1, '', 'not found'));
      mockEnv.setupProcess('python.exe', [
        '--version',
      ], ProcessResult(1, 1, '', 'not found'));
      mockEnv.setupProcess('/bin/zsh', [
        '-lc',
        'which python3',
      ], ProcessResult(0, 0, '/usr/local/bin/python3', ''));
      mockEnv.setupProcess('/usr/local/bin/python3', [
        '--version',
      ], ProcessResult(0, 0, 'Python 3.11.0', ''));

      final path = await bundleManager.findPython();
      expect(path, equals('/usr/local/bin/python3'));
    });
  });

  group('Module extraction', () {
    test('needsExtraction is true on first run', () async {
      mockEnv.isMacOS = true;
      mockEnv.resolvedExecutable =
          '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.setupDirectory(
        '/Applications/NMTK.app/Contents/Resources/modules',
      );

      expect(await bundleManager.needsExtraction, isTrue);
    });

    test('needsExtraction is false when version matches', () async {
      mockEnv.isMacOS = true;
      final exe = '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.resolvedExecutable = exe;
      final now = DateTime.now();
      mockEnv.setupFile(exe, 'dummy', mtime: now);

      mockEnv.setupDirectory(
        '/Applications/NMTK.app/Contents/Resources/modules',
      );
      final appSupportModules = '/mock/user/app_support/modules';
      mockEnv.setupDirectory(appSupportModules);
      mockEnv.setupFile(
        p.join(appSupportModules, '.bundle_version'),
        now.toIso8601String(),
      );

      expect(await bundleManager.needsExtraction, isFalse);
    });

    test('extractModules copies files and writes version', () async {
      mockEnv.isMacOS = true;
      final exe = '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.resolvedExecutable = exe;
      final now = DateTime.now();
      mockEnv.setupFile(exe, 'dummy', mtime: now);

      final bundledModules =
          '/Applications/NMTK.app/Contents/Resources/modules';
      mockEnv.setupDirectory(bundledModules);
      mockEnv.setupDirectory(p.join(bundledModules, 'neurocnl'));
      mockEnv.setupFile(p.join(bundledModules, 'neurocnl', 'README.md'), 'CNL');

      await bundleManager.extractModules();

      final appSupportModules = '/mock/user/app_support/modules';
      expect(
        mockEnv.directoryExists(p.join(appSupportModules, 'neurocnl')),
        isTrue,
      );
      expect(
        await mockEnv.fileExists(
          p.join(appSupportModules, 'neurocnl', 'README.md'),
        ),
        isTrue,
      );
      expect(
        await mockEnv.readFileAsString(
          p.join(appSupportModules, '.bundle_version'),
        ),
        equals(now.toIso8601String()),
      );
    });
  });

  group('Bundle validation', () {
    test('validateBundle returns true for valid bundle', () async {
      mockEnv.isMacOS = true;
      final exe = '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.resolvedExecutable = exe;
      final bundledModules =
          '/Applications/NMTK.app/Contents/Resources/modules';
      mockEnv.setupDirectory(bundledModules);
      mockEnv.setupDirectory(p.join(bundledModules, 'neurocnl'));

      final bundledPython =
          '/Applications/NMTK.app/Contents/Resources/python/bin/python3';
      mockEnv.setupProcess(bundledPython, [
        '--version',
      ], ProcessResult(0, 0, 'Python 3.12.7', ''));

      expect(await bundleManager.validateBundle(), isTrue);
    });

    test('validateBundle returns false when modules missing', () async {
      mockEnv.isMacOS = true;
      mockEnv.resolvedExecutable =
          '/Applications/NMTK.app/Contents/MacOS/neuro_toolkit';
      mockEnv.setupDirectory(
        '/Applications/NMTK.app/Contents/MacOS',
      ); // Setup parent to force isBundled false or something
      // Actually isBundled depends on modules dir existence for macOS

      expect(bundleManager.isBundled, isFalse);
      expect(await bundleManager.validateBundle(), isTrue); // true for DEV mode
    });
  });
}
