import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown when no working Python interpreter can be found.
class PythonNotFoundException implements Exception {
  @override
  String toString() => 'Python not found. Install Python 3.10+ to continue.';
}

/// Abstraction for environment-dependent operations to enable unit testing.
abstract class BundleEnvironment {
  bool get isMacOS;
  bool get isWindows;
  bool get isLinux;
  String get resolvedExecutable;
  Map<String, String> get environment;
  String get currentDirectory;

  Future<String> getApplicationSupportPath();

  bool directoryExists(String path);
  Future<bool> fileExists(String path);
  DateTime getFileModificationTime(String path);
  Future<String> readFileAsString(String path);
  Future<void> writeFileAsString(String path, String contents);
  Future<void> createDirectory(String path, {bool recursive = false});
  Stream<FileSystemEntity> listDirectory(String path, {bool recursive = false});
  Future<void> copyFile(String source, String destination);

  Future<ProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  });

  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  });
}

class DefaultBundleEnvironment implements BundleEnvironment {
  @override
  bool get isMacOS => Platform.isMacOS;
  @override
  bool get isWindows => Platform.isWindows;
  @override
  bool get isLinux => Platform.isLinux;
  @override
  String get resolvedExecutable => Platform.resolvedExecutable;
  @override
  Map<String, String> get environment => Platform.environment;
  @override
  String get currentDirectory => Directory.current.path;

  @override
  Future<String> getApplicationSupportPath() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  @override
  bool directoryExists(String path) => Directory(path).existsSync();

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  DateTime getFileModificationTime(String path) => File(path).statSync().modified;

  @override
  Future<String> readFileAsString(String path) => File(path).readAsString();

  @override
  Future<void> writeFileAsString(String path, String contents) =>
      File(path).writeAsString(contents);

  @override
  Future<void> createDirectory(String path, {bool recursive = false}) =>
      Directory(path).create(recursive: recursive);

  @override
  Stream<FileSystemEntity> listDirectory(String path, {bool recursive = false}) =>
      Directory(path).list(recursive: recursive);

  @override
  Future<void> copyFile(String source, String destination) =>
      File(source).copy(destination);

  @override
  Future<ProcessResult> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
  }

  @override
  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) {
    return Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
  }
}

/// Manages path resolution for both development (repo checkout) and
/// release (self-contained .app bundle) modes.
///
/// In dev mode: modules are resolved relative to the git repo root.
/// In bundled mode: modules are extracted from .app/Contents/Resources/modules/
/// to ~/Library/Application Support/ on first launch, and a bundled Python
/// interpreter is used instead of system python3.
class BundleManager {
  static final BundleManager _instance = BundleManager._internal();
  factory BundleManager({BundleEnvironment? env}) {
    if (env != null) {
      _instance._env = env;
    }
    return _instance;
  }
  BundleManager._internal();

  BundleEnvironment _env = DefaultBundleEnvironment();

  @visibleForTesting
  set env(BundleEnvironment value) {
    _env = value;
    clearCache();
  }

  String? _cachedAppSupportPath;
  String? _cachedPythonPath;
  String? _cachedModulesBasePath;

  bool? _isBundledCache;

  /// Whether the app is running from a STANDALONE bundle that has
  /// bundled modules inside.
  ///
  /// Returns false for debug builds and for command-line runs.
  bool get isBundled {
    if (_isBundledCache != null) return _isBundledCache!;
    final exe = _env.resolvedExecutable;

    if (_env.isMacOS) {
      if (!exe.contains('.app/Contents/MacOS/')) {
        _isBundledCache = false;
        return false;
      }
      // Distinguish standalone (has Resources/modules/) from debug (doesn't).
      final bundlePath = p.dirname(p.dirname(p.dirname(exe)));
      final modulesDir =
          Directory(p.join(bundlePath, 'Contents', 'Resources', 'modules'));
      _isBundledCache = modulesDir.existsSync();
    } else if (Platform.isWindows || Platform.isLinux) {
      // On Windows and Linux, modules are placed next to the executable in the installer.
      final exeDir = p.dirname(exe);
      final modulesDir = p.join(exeDir, 'modules');
      _isBundledCache = _env.directoryExists(modulesDir);
    } else if (_env.isLinux) {
      // On Linux (AppImage), modules are usually in usr/bin/modules relative to AppRun,
      // but Platform.resolvedExecutable points to the actual binary in the mounted squashfs.
      final exeDir = p.dirname(exe);
      final modulesDir = p.join(exeDir, 'modules');
      _isBundledCache = _env.directoryExists(modulesDir);
    } else {
      _isBundledCache = false;
    }

    if (_isBundledCache == true) {
      debugPrint('BundleManager: Running in BUNDLED mode');
    } else {
      debugPrint('BundleManager: Running in DEV mode');
    }
    return _isBundledCache!;
  }

  /// The root of the bundle (e.g., .app on macOS or exe dir on Windows).
  /// Only valid when [isBundled] is true.
  String get bundleRootPath {
    assert(isBundled, 'bundleRootPath called outside of a bundled app');
    final exe = _env.resolvedExecutable;
    if (_env.isMacOS) {
      return p.dirname(p.dirname(p.dirname(exe)));
    } else {
      return p.dirname(exe);
    }
  }

  /// The path to the bundled modules directory.
  String get bundledModulesPath {
    if (_env.isMacOS) {
      return p.join(bundleRootPath, 'Contents', 'Resources', 'modules');
    } else {
      return p.join(bundleRootPath, 'modules');
    }
  }

  // ---------------------------------------------------------------------------
  // Python detection — tries bundled first, then system python3, then python
  // ---------------------------------------------------------------------------

  /// Probes for a working Python interpreter.
  /// Returns the path to the first working Python found, or null.
  ///
  /// Search order:
  /// 1. Bundled Python inside .app (release mode)
  /// 2. Simple command names (python3, python) — works when PATH is inherited
  /// 3. User's login shell PATH via `bash -lc 'which python3'` — handles
  ///    Finder-launched apps that inherit a minimal system PATH
  /// 4. Well-known absolute paths (Homebrew, Anaconda, pyenv, system)
  Future<String?> findPython() async {
    if (_cachedPythonPath != null) return _cachedPythonPath;

    // 1. If running from a bundle, check bundled Python first
    if (isBundled) {
      final List<String> bundledPaths = [];
      if (_env.isMacOS) {
        bundledPaths.addAll([
          p.join(
            bundleRootPath,
            'Contents',
            'Frameworks',
            'python',
            'bin',
            'python3',
          ),
          p.join(
            bundleRootPath,
            'Contents',
            'Frameworks',
            'python',
            'bin',
            'python',
          ),
        ]);
      } else if (_env.isWindows || _env.isLinux) {
        bundledPaths.addAll([
          p.join(bundleRootPath, 'python', 'python.exe'),
          p.join(bundleRootPath, 'python', 'bin', 'python3'),
          p.join(bundleRootPath, 'python', 'bin', 'python'),
        ]);
      }

      for (final path in bundledPaths) {
        if (await _isPythonWorking(path)) {
          debugPrint('BundleManager: using bundled Python at $path');
          _cachedPythonPath = path;
          return path;
        }
      }
      debugPrint('BundleManager: bundled Python not found, trying system...');
    }

    // 2. Try simple command names (works when PATH is properly inherited)
    for (final name in ['python3', 'python', 'python.exe']) {
      if (await _isPythonWorking(name)) {
        debugPrint('BundleManager: using system Python "$name"');
        _cachedPythonPath = name;
        return name;
      }
    }

    // 3. On macOS/Linux, try resolving via login shell if simple names fail
    if (!_env.isWindows) {
      debugPrint('BundleManager: simple names failed, trying login shell...');
      for (final name in ['python3', 'python']) {
        final resolved = await _resolveViaLoginShell(name);
        if (resolved != null && await _isPythonWorking(resolved)) {
          debugPrint('BundleManager: found via login shell: $resolved');
          _cachedPythonPath = resolved;
          return resolved;
        }
      }
    }

    // 4. Last resort: probe well-known absolute paths
    debugPrint('BundleManager: probing known paths...');
    final List<String> knownPaths = [];

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ??
          '/Users/${Platform.environment['USER']}';
      knownPaths.addAll([
        '/opt/homebrew/bin/python3',
        '/opt/homebrew/bin/python',
        '/usr/local/bin/python3',
        '/usr/local/bin/python',
        '$home/anaconda3/bin/python3',
        '$home/anaconda3/bin/python',
        '$home/miniconda3/bin/python3',
        '$home/miniconda3/bin/python',
        '$home/.pyenv/shims/python3',
        '$home/.pyenv/shims/python',
        '/usr/bin/python3',
      ]);
    } else if (_env.isWindows) {
      final envVars = _env.environment;
      final localAppData = envVars['LOCALAPPDATA'];
      final programFiles = envVars['ProgramFiles'];
      if (localAppData != null) {
        knownPaths.add(
          p.join(
            localAppData,
            'Programs',
            'Python',
            'Python312',
            'python.exe',
          ),
        );
        knownPaths.add(
          p.join(
            localAppData,
            'Programs',
            'Python',
            'Python311',
            'python.exe',
          ),
        );
        knownPaths.add(
          p.join(
            localAppData,
            'Programs',
            'Python',
            'Python310',
            'python.exe',
          ),
        );
      }
      if (programFiles != null) {
        knownPaths.add(p.join(programFiles, 'Python312', 'python.exe'));
        knownPaths.add(p.join(programFiles, 'Python311', 'python.exe'));
        knownPaths.add(p.join(programFiles, 'Python310', 'python.exe'));
      }
    }

    for (final absPath in knownPaths) {
      if (await _env.fileExists(absPath) && await _isPythonWorking(absPath)) {
        debugPrint('BundleManager: found at known path: $absPath');
        _cachedPythonPath = absPath;
        return absPath;
      }
    }

    debugPrint('BundleManager: no Python interpreter found');
    return null;
  }

  /// Uses the user's login shell to resolve a command to its absolute path.
  /// This picks up PATH from ~/.zshrc, ~/.bash_profile, etc.
  Future<String?> _resolveViaLoginShell(String command) async {
    try {
      // Use zsh (macOS default) or bash with login flag to source profile
      final shell = _env.environment['SHELL'] ?? '/bin/zsh';
      final result = await _env.runProcess(
        shell,
        ['-lc', 'which $command'],
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final resolved = result.stdout.toString().trim();
        if (resolved.isNotEmpty && resolved.startsWith('/')) {
          return resolved;
        }
      }
    } catch (e) {
      debugPrint('BundleManager: login shell resolve failed for $command: $e');
    }
    return null;
  }

  /// Returns the path to a working Python interpreter.
  /// Throws [PythonNotFoundException] if none is found.
  Future<String> get pythonPath async {
    final path = await findPython();
    if (path == null) throw PythonNotFoundException();
    return path;
  }

  /// Quick check: is any Python available?
  Future<bool> get isPythonAvailable async => (await findPython()) != null;

  /// Returns the Python version string (e.g. "3.12.7") or null.
  Future<String?> get pythonVersion async {
    final path = await findPython();
    if (path == null) return null;
    try {
      final result = await _env.runProcess(path, ['--version']);
      // stdout: "Python 3.12.7\n"
      return result.stdout.toString().trim().replaceFirst('Python ', '');
    } catch (_) {
      return null;
    }
  }

  /// Clear cached paths. Call when user installs Python and
  /// hits "Retry" so we re-probe.
  void clearCache() {
    _cachedPythonPath = null;
    _isBundledCache = null;
    _cachedAppSupportPath = null;
  }

  /// Checks whether a given binary is a working Python (exits 0 on --version).
  Future<bool> _isPythonWorking(String path) async {
    try {
      final result = await _env.runProcess(path, ['--version'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        debugPrint(
          'BundleManager: "$path" -> ${result.stdout.toString().trim()}',
        );
        return true;
      }
      debugPrint(
        'BundleManager: "$path" exited with ${result.exitCode}: ${result.stderr}',
      );
      return false;
    } catch (e) {
      debugPrint('BundleManager: "$path" failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Module path resolution
  // ---------------------------------------------------------------------------

  /// Base directory where module source trees live.
  /// - Bundled: ~/Library/Application Support/.../modules/
  /// - Dev: two levels up from the Flutter app dir (repo root)
  Future<String> get modulesBasePath async {
    if (_cachedModulesBasePath != null) return _cachedModulesBasePath!;

    if (isBundled) {
      _cachedModulesBasePath = await _appSupportModulesDir;
    } else {
      // Dev mode: nmtk/neuro_toolkit -> ../../ = repo root
      _cachedModulesBasePath = p.normalize(p.join(p.current, '..', '..'));
    }
    // Dev mode: nmtk/neuro_toolkit -> ../../ = repo root
    return p.normalize(p.join(_env.currentDirectory, '..', '..'));
  }

  /// Whether first-run extraction is needed.
  Future<bool> get needsExtraction async {
    if (!isBundled) return false;

    final targetPath = await _appSupportModulesDir;
    if (!_env.directoryExists(targetPath)) return true;

    // Check version marker
    final markerPath = p.join(targetPath, '.bundle_version');
    if (!await _env.fileExists(markerPath)) return true;

    final installedVersion = await _env.readFileAsString(markerPath);
    return installedVersion.trim() != _appVersion;
  }

  /// Extract bundled module sources to the application support directory.
  Future<void> extractModules({void Function(double)? onProgress}) async {
    if (!isBundled) return;

    final sourcePath = bundledModulesPath;
    if (!_env.directoryExists(sourcePath)) {
      debugPrint('BundleManager: no bundled modules at $sourcePath');
      throw Exception('Bundled modules not found at $sourcePath');
    }

    final targetBase = await _appSupportModulesDir;
    final targetDir = Directory(targetBase);

    // If version mismatch or missing marker, clean up first to avoid leftovers
    if (await targetDir.exists()) {
      debugPrint('BundleManager: Cleaning up old modules in Application Support...');
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    final entries = await _env.listDirectory(sourcePath).toList();
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] is Directory) {
        final moduleName = p.basename(entries[i].path);
        final destPath = p.join(targetBase, moduleName);

        debugPrint('BundleManager: extracting $moduleName...');
        await _copyDirectory(entries[i] as Directory, destPath);
      }
      onProgress?.call((i + 1) / entries.length);
    }

    // Write version marker
    final markerPath = p.join(targetBase, '.bundle_version');
    await _env.writeFileAsString(markerPath, _appVersion);

    debugPrint('BundleManager: extraction complete');
  }

  /// Validates that the bundle is intact.
  Future<bool> validateBundle() async {
    if (!isBundled) return true;

    if (!_env.directoryExists(bundledModulesPath)) {
      debugPrint('Bundle validation failed: modules directory missing at $bundledModulesPath');
      return false;
    }

    // Check for at least one module (e.g., Neurohub) or just that it's not empty
    final entries = await _env.listDirectory(bundledModulesPath).toList();
    if (entries.isEmpty) {
      debugPrint('Bundle validation failed: modules directory is empty');
      return false;
    }

    // Check for bundled python
    final python = await findPython();
    if (python == null || !python.contains(bundleRootPath)) {
      debugPrint('Bundle validation failed: bundled Python not found');
      return false;
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// The app version string for tracking extraction state.
  String get _appVersion {
    try {
      final mtime = _env.getFileModificationTime(_env.resolvedExecutable);
      return mtime.toIso8601String();
    } catch (_) {
      return 'unknown';
    }
  }

  Future<String> get _appSupportModulesDir async {
    if (_cachedAppSupportPath != null) return _cachedAppSupportPath!;
    final appSupportPath = await _env.getApplicationSupportPath();
    _cachedAppSupportPath = p.join(appSupportPath, 'modules');
    return _cachedAppSupportPath!;
  }

  /// Recursively copy a directory tree.
  Future<void> _copyDirectory(Directory source, String destinationPath) async {
    await _env.createDirectory(destinationPath, recursive: true);
    await for (final entity in _env.listDirectory(source.path, recursive: false)) {
      final newPath = p.join(destinationPath, p.basename(entity.path));
      if (entity is File) {
        await _env.copyFile(entity.path, newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, newPath);
      }
    }
  }
}
