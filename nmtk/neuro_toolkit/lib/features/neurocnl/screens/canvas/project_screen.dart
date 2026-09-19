import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/project.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/project_provider.dart';

class ProjectScreen extends ConsumerStatefulWidget {
  const ProjectScreen({
    super.key,
    this.selectedProjectId,
    this.onProjectSelected,
    this.onLoadIntoCanvas,
    this.onProjectDeleted,
  });

  final String? selectedProjectId;
  final ValueChanged<String>? onProjectSelected;
  final ValueChanged<Project>? onLoadIntoCanvas;
  final ValueChanged<String>? onProjectDeleted;

  @override
  ConsumerState<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends ConsumerState<ProjectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSelectedProject();
    });
  }

  @override
  void didUpdateWidget(covariant ProjectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProjectId != widget.selectedProjectId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSelectedProject();
      });
    }
  }

  Future<void> _loadSelectedProject() async {
    final selectedProjectId = widget.selectedProjectId;
    if (selectedProjectId == null) {
      return;
    }
    try {
      await ref
          .read(currentProjectProvider.notifier)
          .loadProject(selectedProjectId);
    } catch (e) {
      if (mounted) {
        NmtkSnackBars.error(context, 'Failed to load project: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectListProvider);
    final currentProject = ref.watch(currentProjectProvider);

    return Material(
      // ZETA-MIGRATION-EXEMPT: transparent (no fill) — Zeta has no transparent token
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved Projects',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                ZetaButton.outline(
                  onPressed: () => ref.refresh(projectListProvider),
                  leadingIcon: ZetaIcons.refresh,
                  label: 'Refresh',
                ),
                const SizedBox(width: 12),
                ZetaButton(
                  onPressed: () => _showSaveDialog(context, ref),
                  leadingIcon: ZetaIcons.save,
                  label: 'Save Current Design',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    // Allowed: single-topic surface
                    child: NmtkSurfaceCard(
                      expandChild: true,
                      child: projects.when(
                        data: (list) => ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final project = list[index];
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                title: Text(project.name),
                                subtitle: Text(project.description),
                                onTap: () {
                                  widget.onProjectSelected?.call(project.id);
                                  ref
                                      .read(currentProjectProvider.notifier)
                                      .loadProject(project.id);
                                },
                                selected: currentProject.maybeWhen(
                                  data: (p) => p?.id == project.id,
                                  orElse: () => false,
                                ),
                              ),
                            );
                          },
                        ),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, st) => Center(child: Text('Error: $err')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    // Allowed: single-topic surface
                    child: NmtkSurfaceCard(
                      expandChild: true,
                      child: currentProject.when(
                        data: (project) {
                          if (project == null) {
                            return const Center(
                              child: Text('Select a project to see details.'),
                            );
                          }
                          return _buildProjectDetail(context, project, ref);
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (err, st) => Center(child: Text('Error: $err')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectDetail(
    BuildContext context,
    Project project,
    WidgetRef ref,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(project.name, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Last updated: ${project.updatedAt}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          Text('Description', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(project.description),
          const SizedBox(height: 24),
          Text('Network Graph', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Nodes: ${project.graph.nodes.length}, Edges: ${project.graph.edges.length}',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              ZetaButton.outline(
                onPressed: () =>
                    _showSaveDialog(context, ref, project: project),
                leadingIcon: ZetaIcons.edit,
                label: 'Update Metadata',
              ),
              const SizedBox(width: 16),
              ZetaButton.negative(
                onPressed: () => _showDeleteConfirm(context, ref, project),
                leadingIcon: ZetaIcons.delete_outline,
                label: 'Delete Project',
              ),
            ],
          ),
          const Spacer(),
          ZetaButton(
            onPressed: () {
              ref.read(canvasProvider.notifier).setGraph(project.graph);
              widget.onLoadIntoCanvas?.call(project);
            },
            leadingIcon: ZetaIcons.open_in_new_window,
            label: 'Load into Canvas',
          ),
        ],
      ),
    );
  }

  void _showSaveDialog(
    BuildContext context,
    WidgetRef ref, {
    Project? project,
  }) {
    final nameController = TextEditingController(text: project?.name);
    final descController = TextEditingController(text: project?.description);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          project == null ? 'Save Current Design' : 'Update Project Metadata',
        ),
        content: NmtkDialogSurface.wrapScrollable(
          context,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NmtkTextInput(controller: nameController, label: 'Project Name'),
              const SizedBox(height: 12),
              NmtkTextInput(controller: descController, label: 'Description'),
            ],
          ),
        ),
        actions: [
          ZetaButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
          ),
          ZetaButton(
            onPressed: () {
              final canvasState = ref.read(canvasProvider);
              final request = CreateProjectRequest(
                name: nameController.text,
                description: descController.text,
                // graphForPersistence, not graph: the camera lives on
                // CanvasState.viewport now and has to be folded back into
                // metadata for the project to store it.
                graph: project?.graph ?? canvasState.graphForPersistence,
              );
              if (project == null) {
                ref.read(currentProjectProvider.notifier).saveProject(request);
              } else {
                ref
                    .read(currentProjectProvider.notifier)
                    .updateProject(project.id, request);
              }
              Navigator.of(context).pop();
            },
            label: 'Save',
          ),
        ],
      ),
    ).whenComplete(() {
      // Defer disposal a frame: the dialog's exit transition is still
      // rebuilding widgets that reference these controllers when this
      // future resolves, so disposing synchronously here throws.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
        descController.dispose();
      });
    });
  }

  void _showDeleteConfirm(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text(
          'Are you sure you want to delete "${project.name}"? This action cannot be undone.',
        ),
        actions: [
          ZetaButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
          ),
          ZetaButton.negative(
            onPressed: () {
              ref
                  .read(currentProjectProvider.notifier)
                  .deleteProject(project.id);
              widget.onProjectDeleted?.call(project.id);
              Navigator.of(context).pop();
            },
            label: 'Delete',
          ),
        ],
      ),
    );
  }
}
