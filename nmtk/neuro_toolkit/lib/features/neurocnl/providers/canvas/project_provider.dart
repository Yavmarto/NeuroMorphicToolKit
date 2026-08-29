import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/project.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';

part 'project_provider.g.dart';

final projectListProvider = FutureProvider<List<ProjectSummary>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  return apiClient.listProjects();
});

@riverpod
class CurrentProjectController extends _$CurrentProjectController {
  @override
  AsyncValue<Project?> build() => const AsyncValue.data(null);

  Future<Project> loadProject(String id) async {
    state = const AsyncValue.loading();
    try {
      final project = await ref.read(apiClientProvider).getProject(id);
      state = AsyncValue.data(project);
      return project;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> saveProject(CreateProjectRequest request) async {
    state = const AsyncValue.loading();
    try {
      final project = await ref.read(apiClientProvider).createProject(request);
      state = AsyncValue.data(project);
      ref.invalidate(projectListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateProject(String id, CreateProjectRequest request) async {
    state = const AsyncValue.loading();
    try {
      final project = await ref
          .read(apiClientProvider)
          .updateProject(id, request);
      state = AsyncValue.data(project);
      ref.invalidate(projectListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteProject(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(apiClientProvider).deleteProject(id);
      state = const AsyncValue.data(null);
      ref.invalidate(projectListProvider);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void clearCurrentProject() {
    state = const AsyncValue.data(null);
  }
}

/// Backward-compat alias.
final currentProjectProvider = currentProjectControllerProvider;
