import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notebook_meta_provider.g.dart';

/// Where/when a platform's notebook was last generated, on demand, from the
/// Run step's embedded JupyterLab view ("Open Notebook" action). Read by the
/// Run step to detect whether the notebook was edited since generation,
/// before deciding whether to silently regenerate it.
class NotebookGenerationMeta {
  const NotebookGenerationMeta({
    required this.workspaceFolder,
    required this.filename,
    required this.generatedAt,
    this.jupyterUrl = '',
  });

  final String workspaceFolder;
  final String filename;
  final double generatedAt;

  /// Absolute JupyterLab URL supplied by the backend at generation time.
  /// Empty when the backend couldn't resolve one, in which case callers
  /// derive a fallback URL from the client's own known-reachable host.
  final String jupyterUrl;
}

@riverpod
class NotebookMeta extends _$NotebookMeta {
  @override
  Map<String, NotebookGenerationMeta> build() => const {};

  void recordGeneration(String platform, NotebookGenerationMeta meta) {
    state = {...state, platform: meta};
  }

  NotebookGenerationMeta? forPlatform(String platform) => state[platform];
}
