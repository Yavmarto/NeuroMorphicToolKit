import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';

part 'environment_package_notifier.g.dart';

/// Per-environment package list notifier.
///
/// Keyed by environment slug so each card gets its own isolated cache.
/// `autoDispose` ensures memory is freed when the card collapses or unmounts.
@riverpod
class EnvironmentPackageNotifier extends _$EnvironmentPackageNotifier {
  @override
  EnvironmentPackageState build(String slug) => const EnvironmentPackageState();

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final pkgs = await ref.read(environmentProvider.notifier).packages(slug);
      state = state.copyWith(loading: false, packages: pkgs);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

/// Per-environment requirements export notifier.
///
/// Keyed by (slug, mode) pair and `autoDispose`d so it reloads on each dialog
/// open. The mode switch triggers a manual call to [reload].
@riverpod
class EnvironmentExportNotifier extends _$EnvironmentExportNotifier {
  @override
  Future<EnvironmentExportState> build(String slug) async {
    final body = await ref
        .read(environmentProvider.notifier)
        .exportRequirements(slug, mode: 'delta');
    return EnvironmentExportState(loading: false, body: body);
  }

  Future<void> reload(String mode) async {
    final current = state.value ?? const EnvironmentExportState();
    state = AsyncData(current.copyWith(loading: true, mode: mode, error: null));
    try {
      final body = await ref
          .read(environmentProvider.notifier)
          .exportRequirements(slug, mode: mode);
      state =
          AsyncData(current.copyWith(loading: false, mode: mode, body: body));
    } catch (e) {
      state = AsyncData(
          current.copyWith(loading: false, mode: mode, error: e.toString()));
    }
  }
}
