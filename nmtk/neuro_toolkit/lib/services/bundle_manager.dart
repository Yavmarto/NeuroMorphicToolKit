import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown when no working Python interpreter can be found.
class PythonNotFoundException implements Exception {
  @override
  String toString() => 'Python not found. Install Python 3.10+ to continue.';
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
  factory BundleManager() => _instance;
  BundleManager._internal();

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
    final exe = Platform.resolvedExecutable;

    if (Platform.isMacOS) {
      if (!exe.contains('.app/Contents/MacOS/')) {
        _isBundledCache = false;
        return false;
      }
      // Distinguish standalone (has Resources/modules/) from debug (doesn't).
      final bundlePath = p.dirname(p.dirname(p.dirname(exe)));
      final modulesDir = Directory(p.join(bundlePath, 'Contents', 'Resources', 'modules'));
      _isBundledCache = modulesDir.existsSync();
    } else if (Platform.isWindows) {
      // On Windows, modules are placed next to the executable in the installer.
      final exeDir = p.dirname(exe);
      final modulesDir = Directory(p.join(exeDir, 'modules'));
      _isBundledCache = modulesDir.existsSync();
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
    final exe = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      return p.dirname(p.dirname(p.dirname(exe)));
    } else {
      return p.dirname(exe);
    }
  }

  /// The path to the bundled modules directory.
  String get bundledModulesPath {
    if (Platform.isMacOS) {
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
      if (Platform.isMacOS) {
        bundledPaths.addAll([
          p.join(bundleRootPath, 'Contents', 'Frameworks', 'python', 'bin', 'python3'),
          p.join(bundleRootPath, 'Contents', 'Frameworks', 'python', 'bin', 'python'),
        ]);
      } else if (Platform.isWindows) {
        bundledPaths.addAll([
          p.join(bundleRootPath, 'python', 'python.exe'),
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
    if (!Platform.isWindows) {
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
      final home = Platform.environment['HOME'] ?? '/Users/${Platform.environment['USER']}';
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
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      final programFiles = Platform.environment['ProgramFiles'];
      if (localAppData != null) {
        knownPaths.add(p.join(localAppData, 'Programs', 'Python', 'Python312', 'python.exe'));
        knownPaths.add(p.join(localAppData, 'Programs', 'Python', 'Python311', 'python.exe'));
        knownPaths.add(p.join(localAppData, 'Programs', 'Python', 'Python310', 'python.exe'));
      }
      if (programFiles != null) {
        knownPaths.add(p.join(programFiles, 'Python312', 'python.exe'));
        knownPaths.add(p.join(programFiles, 'Python311', 'python.exe'));
        knownPaths.add(p.join(programFiles, 'Python310', 'python.exe'));
      }
    }

    for (final absPath in knownPaths) {
      if (await File(absPath).exists() && await _isPythonWorking(absPath)) {
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
      final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
      final result = await Process.run(
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
      final result = await Process.run(path, ['--version']);
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
    _cachedModulesBasePath = null;
    _cachedAppSupportPath = null;
  }

  /// Checks whether a given binary is a working Python (exits 0 on --version).
  Future<bool> _isPythonWorking(String path) async {
    try {
      final result = await Process.run(path, ['--version'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        debugPrint('BundleManager: "$path" -> ${result.stdout.toString().trim()}');
        return true;
      }
      debugPrint('BundleManager: "$path" exited with ${result.exitCode}: ${result.stderr}');
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
    return _cachedModulesBasePath!;
  }

  /// Whether first-run extraction is needed.
  Future<bool> get needsExtraction async {
    if (!isBundled) return false;

    final targetDir = Directory(await _appSupportModulesDir);
    if (!await targetDir.exists()) return true;

    // Check version marker
    final markerFile = File(p.join(targetDir.path, '.bundle_version'));
    if (!await markerFile.exists()) return true;

    final installedVersion = await markerFile.readAsString();
    return installedVersion.trim() != _appVersion;
  }

  /// Extract bundled module sources to the application support directory.
  Future<void> extractModules({void Function(double)? onProgress}) async {
    if (!isBundled) return;

    final sourceDir = Directory(bundledModulesPath);
    if (!await sourceDir.exists()) {
      debugPrint('BundleManager: no bundled modules at ${sourceDir.path}');
      return;
    }

    final targetBase = await _appSupportModulesDir;
    final targetDir = Directory(targetBase);
    await targetDir.create(recursive: true);

    final entries = await sourceDir.list().toList();
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] is Directory) {
        final moduleName = p.basename(entries[i].path);
        final dest = Directory(p.join(targetBase, moduleName));

        debugPrint('BundleManager: extracting $moduleName...');
        await _copyDirectory(entries[i] as Directory, dest);
      }
      onProgress?.call((i + 1) / entries.length);
    }

    // Write version marker
    final markerFile = File(p.join(targetBase, '.bundle_version'));
    await markerFile.writeAsString(_appVersion);

    debugPrint('BundleManager: extraction complete');
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// The app version string for tracking extraction state.
  String get _appVersion {
    try {
      final stat = File(Platform.resolvedExecutable).statSync();
      return stat.modified.toIso8601String();
    } catch (_) {
      return 'unknown';
    }
  }

  Future<String> get _appSupportModulesDir async {
    if (_cachedAppSupportPath != null) return _cachedAppSupportPath!;
    final appSupportDir = await getApplicationSupportDirectory();
    _cachedAppSupportPath = p.join(appSupportDir.path, 'modules');
    return _cachedAppSupportPath!;
  }

  /// Recursively copy a directory tree.
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }
}
