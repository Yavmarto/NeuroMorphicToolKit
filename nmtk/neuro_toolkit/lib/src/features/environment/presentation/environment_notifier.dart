import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';
import 'package:neuro_toolkit/src/features/environment/domain/environment_state.dart';

part 'environment_notifier.g.dart';

@riverpod
class EnvironmentNotifier extends _$EnvironmentNotifier {
  static const Duration _pollInterval = Duration(seconds: 2);
  static const int _maxPolls = 600;

  @override
  Future<EnvironmentState> build() async {
    final api = ref.watch(environmentApiServiceProvider);
    final envs = await api.listEnvironments();
    return EnvironmentState(environments: envs);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final api = ref.read(environmentApiServiceProvider);
      final envs = await api.listEnvironments();
      state = AsyncData(EnvironmentState(environments: envs));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<List<PackageInfo>> packages(String slug) {
    return ref.read(environmentApiServiceProvider).listPackages(slug);
  }

  Future<String> exportRequirements(String slug, {String mode = 'delta'}) {
    return ref
        .read(environmentApiServiceProvider)
        .exportRequirements(slug, mode: mode);
  }

  Future<void> createEnvironment(String displayName) => _runJob(
    'Cloning environment…',
    () =>
        ref.read(environmentApiServiceProvider).createEnvironment(displayName),
  );

  Future<void> importEnvironment(String displayName, String requirements) =>
      _runJob(
        'Importing environment…',
        () => ref
            .read(environmentApiServiceProvider)
            .importEnvironment(displayName, requirements),
      );

  Future<void> installPackages(String slug, List<String> specs) => _runJob(
    'Installing packages…',
    () => ref.read(environmentApiServiceProvider).installPackages(slug, specs),
  );

  Future<void> uninstallPackages(String slug, List<String> names) => _runJob(
    'Removing packages…',
    () =>
        ref.read(environmentApiServiceProvider).uninstallPackages(slug, names),
  );

  Future<void> deleteEnvironment(String slug) async {
    await _withBusy(
      'Deleting environment…',
      () => ref.read(environmentApiServiceProvider).deleteEnvironment(slug),
    );
    await refresh();
  }

  Future<void> _runJob(String label, Future<String> Function() start) async {
    await _withBusy(label, () async {
      final api = ref.read(environmentApiServiceProvider);
      final jobId = await start();
      for (var i = 0; i < _maxPolls; i++) {
        final job = await api.pollJob(jobId);
        if (job.isError) {
          throw EnvironmentApiException(
            [
              job.error,
              job.log,
            ].whereType<String>().where((s) => s.isNotEmpty).join('\n\n'),
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
    final currentState = state.value;
    if (currentState != null) {
      state = AsyncData(
        currentState.copyWith(busy: true, activeOperation: label),
      );
    }

    try {
      await action();
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    } finally {
      final current = state.value;
      if (current != null) {
        state = AsyncData(current.copyWith(busy: false, activeOperation: null));
      }
    }
  }
}
