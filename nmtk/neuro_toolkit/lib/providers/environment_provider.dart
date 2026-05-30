import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/services/environment_api_service.dart';

/// State for the Python Environment Editor. Wraps [EnvironmentApiService],
/// driving the suite_api proxy and polling long-running jobs to completion.
class EnvironmentProvider extends ChangeNotifier {
  EnvironmentProvider(this._api);

  final EnvironmentApiService _api;

  List<EnvironmentInfo> _environments = const <EnvironmentInfo>[];
  List<EnvironmentInfo> get environments => _environments;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// True while a mutating operation (create/install/delete/…) is running.
  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  /// Human-readable description of the operation currently in flight.
  String? _activeOperation;
  String? get activeOperation => _activeOperation;

  static const Duration _pollInterval = Duration(seconds: 2);
  static const int _maxPolls = 600; // ~20 min ceiling for heavy pip installs.

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _environments = await _api.listEnvironments();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<PackageInfo>> packages(String slug) => _api.listPackages(slug);

  Future<String> exportRequirements(String slug, {String mode = 'delta'}) =>
      _api.exportRequirements(slug, mode: mode);

  Future<void> createEnvironment(String displayName) => _runJob(
      'Cloning environment…', () => _api.createEnvironment(displayName));

  Future<void> importEnvironment(String displayName, String requirements) =>
      _runJob(
        'Importing environment…',
        () => _api.importEnvironment(displayName, requirements),
      );

  Future<void> installPackages(String slug, List<String> specs) =>
      _runJob('Installing packages…', () => _api.installPackages(slug, specs));

  Future<void> uninstallPackages(String slug, List<String> names) =>
      _runJob('Removing packages…', () => _api.uninstallPackages(slug, names));

  Future<void> deleteEnvironment(String slug) async {
    await _withBusy(
        'Deleting environment…', () => _api.deleteEnvironment(slug));
    await refresh();
  }

  /// Starts an async backend job and polls until it resolves, then refreshes.
  Future<void> _runJob(String label, Future<String> Function() start) async {
    await _withBusy(label, () async {
      final jobId = await start();
      for (var i = 0; i < _maxPolls; i++) {
        final job = await _api.pollJob(jobId);
        if (job.isError) {
          throw EnvironmentApiException(
            [job.error, job.log]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join('\n\n'),
          );
        }
        if (job.isDone) return;
        await Future<void>.delayed(_pollInterval);
      }
      throw EnvironmentApiException('Operation timed out.');
    });
    await refresh();
  }

  Future<void> _withBusy(String label, Future<void> Function() action) async {
    _busy = true;
    _activeOperation = label;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _busy = false;
      _activeOperation = null;
      notifyListeners();
    }
  }
}
