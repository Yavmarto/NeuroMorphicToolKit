import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/target_availability_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub_popup.dart';
import 'package:neuro_toolkit/features/neurocnl/services/dataset_error_formatter.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/workflow_feature.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/dataset_folder_section.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/platform_role_badge.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/reachability_dot.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/server_workspace_picker_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/setup_step/support.dart';

class SetupStep extends ConsumerStatefulWidget {
  const SetupStep({
    super.key,
    required this.showWorkspaceActions,
    this.onManageHardwareTarget,
  });

  final Future<void> Function(String targetId)? onManageHardwareTarget;
  final bool showWorkspaceActions;

  @override
  ConsumerState<SetupStep> createState() => SetupStepState();
}

class SetupStepState extends ConsumerState<SetupStep> {
  String? _downloadError;
  String? _workspaceError;
  bool _isImportingDataset = false;

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final selectedDataset = workspace.selectedDataset;
    final catalogAsync = ref.watch(datasetCatalogProvider);

    final selectedEntry = catalogAsync.value?.findEntryById(selectedDataset);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.sizeOf(context).width < 840) {
          return _buildMobileLayout(
            context: context,
            workspace: workspace,
            selectedDataset: selectedDataset,
            selectedEntry: selectedEntry,
            catalogAsync: catalogAsync,
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.showWorkspaceActions) ...[
                        Text(
                          'Workspace',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            NmtkOutlinedButton(
                              label: 'Load from hub',
                              icon: ZetaIcons.cloud_download,
                              onPressed: openWorkspaceFromHub,
                            ),
                            NmtkOutlinedButton(
                              label: 'Load from disc',
                              icon: ZetaIcons.upload_file,
                              onPressed: loadWorkspaceFromDevice,
                            ),
                            NmtkOutlinedButton(
                              label: 'Load from server',
                              icon: ZetaIcons.server,
                              onPressed: openWorkspaceFromServer,
                            ),
                          ],
                        ),
                        ..._errorBanner(
                          _workspaceError,
                          () => setState(() => _workspaceError = null),
                        ),
                        const SizedBox(height: 24),
                      ] else
                        ..._errorBanner(
                          _workspaceError,
                          () => setState(() => _workspaceError = null),
                        ),

                      // ── 1. Benchmark (optional) ─────────────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'Benchmark',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'optional',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildScratchBenchmarkPicker(),

                      const SizedBox(height: 24),

                      // ── 2. Target platform ──────────────────────────────────
                      Text(
                        'Target platform',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _buildTargetMultiSelectDropdown(),
                      _buildSelectedPlatformsList(),

                      const SizedBox(height: 24),

                      // ── 3. Dataset ──────────────────────────────────────────
                      Text(
                        'Dataset',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          NmtkOutlinedButton(
                            label: 'Load from examples',
                            icon: ZetaIcons.list,
                            onPressed: () => _showExamplesDialog(context),
                          ),
                          NmtkOutlinedButton(
                            key: const Key('setup-import-dataset-button'),
                            label: 'Load from disk',
                            icon: ZetaIcons.upload_file,
                            onPressed: _isImportingDataset
                                ? null
                                : _importDatasetFromDevice,
                          ),
                          if (_isImportingDataset)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      ..._errorBanner(
                        _downloadError,
                        () => setState(() => _downloadError = null),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 32),
              const Expanded(child: WorkspaceCanvasPreview()),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Shared dismissible error banner for [_workspaceError]/[_downloadError],
  /// used by both the desktop and mobile layouts. Returns `[]` when
  /// [message] is null so callers can always spread it (`..._errorBanner(...)`)
  /// without a separate `if` guard.
  List<Widget> _errorBanner(String? message, VoidCallback onDismiss) {
    if (message == null) return const [];
    return [
      const SizedBox(height: 12),
      MaterialBanner(
        content: Text(message),
        actions: [
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
        ],
      ),
    ];
  }

  Widget _buildTargetMultiSelectDropdown() {
    final selectedPlatforms = ref.watch(workspaceProvider).selectedPlatforms;
    return OutlinedButton.icon(
      icon: const Icon(
        Icons.arrow_drop_down,
        size: 20,
      ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      label: Text(
        selectedPlatforms.isEmpty
            ? 'Select targets…'
            : '${selectedPlatforms.length} target${selectedPlatforms.length == 1 ? '' : 's'} selected',
      ),
      onPressed: () => _showTargetPickerDialog(context),
    );
  }

  Widget _buildSelectedPlatformsList() {
    final selectedPlatforms = ref.watch(workspaceProvider).selectedPlatforms;
    if (selectedPlatforms.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        for (final id in selectedPlatforms)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(targetForId(id).icon, size: 18),
                const SizedBox(width: 4),
                ReachabilityDot(key: Key('reachability-dot-$id'), targetId: id),
              ],
            ),
            title: Row(
              children: [
                // Flexible, not bare: "SC-NeuroCore (FPGA RTL)" plus the badge
                // overflows a 390px-wide tile otherwise.
                Flexible(
                  child: Text(targetLabel(id), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                PlatformRoleBadge(targetId: id),
                const SizedBox(width: 4),
                NeurocnlInfoButton(
                  title: targetLabel(id),
                  message: platformRoleDescription(id),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isHardwareTargetWithManageFlow(id) &&
                    widget.onManageHardwareTarget != null)
                  IconButton(
                    icon: const Icon(
                      Icons
                          .settings_ethernet_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                      size: 16,
                    ),
                    tooltip: 'Manage Targets',
                    onPressed: () => widget.onManageHardwareTarget!(id),
                  ),
                IconButton(
                  icon: const Icon(ZetaIcons.close, size: 16),
                  onPressed: () =>
                      ref.read(workspaceProvider.notifier).togglePlatform(id),
                ),
              ],
            ),
          ),
      ],
    );
  }

  bool _isHardwareTargetWithManageFlow(String id) =>
      isHardwareTargetWithManageFlowId(id);

  void _showTargetPickerDialog(BuildContext context) {
    final availability =
        ref.read(targetAvailabilityProvider).value ?? const <String, bool>{};
    final localSelected = List<String>.from(
      ref.read(workspaceProvider).selectedPlatforms,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          final warningColor = Zeta.of(context).colors.mainWarning;
          return AlertDialog(
            title: const Text('Select targets'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final target in deployTargets)
                      CheckboxListTile(
                        dense: true,
                        secondary: Icon(
                          (availability[target.id] ?? true)
                              ? target.icon
                              : Icons
                                    .download, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                          size: 18,
                          color: (availability[target.id] ?? true)
                              ? null
                              : warningColor,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                target.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            PlatformRoleBadge(targetId: target.id),
                            const SizedBox(width: 4),
                            NeurocnlInfoButton(
                              title: target.label,
                              message: platformRoleDescription(target.id),
                            ),
                          ],
                        ),
                        value: localSelected.contains(target.id),
                        onChanged: (_) {
                          setDialogState(() {
                            if (localSelected.contains(target.id)) {
                              localSelected.remove(target.id);
                            } else {
                              localSelected.add(target.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              ZetaButton.text(
                onPressed: () => Navigator.of(ctx).pop(),
                label: 'Cancel',
              ),
              FilledButton(
                onPressed: () {
                  final original = ref
                      .read(workspaceProvider)
                      .selectedPlatforms;
                  for (final id in localSelected) {
                    if (!original.contains(id)) {
                      ref.read(workspaceProvider.notifier).togglePlatform(id);
                    }
                  }
                  for (final id in original) {
                    if (!localSelected.contains(id)) {
                      ref.read(workspaceProvider.notifier).togglePlatform(id);
                    }
                  }
                  Navigator.of(ctx).pop();
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showExamplesDialog(BuildContext context) {
    final catalogAsync = ref.read(datasetCatalogProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Example datasets'),
        content: SizedBox(
          width: 640,
          height: 500,
          child: catalogAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Could not load datasets: ${e.toString()}')),
            data: (catalog) {
              if (catalog.folders.isEmpty) {
                return const Center(
                  child: Text('No example datasets available.'),
                );
              }
              final selectedId = ref.read(workspaceProvider).selectedDataset;
              return ListView(
                children: [
                  for (final folder in catalog.folders)
                    DatasetFolderSection(
                      folder: folder,
                      selectedDatasetId: selectedId,
                      onFileTapped: (entry) {
                        _onDatasetTapped(entry);
                        Navigator.of(ctx).pop();
                      },
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(ctx).pop(),
            label: 'Close',
          ),
        ],
      ),
    );
  }

  // ── Mobile layout ────────────────────────────────────────────────────────

  Widget _buildMobileLayout({
    required BuildContext context,
    required WorkspaceState workspace,
    required String? selectedDataset,
    required DatasetEntry? selectedEntry,
    required AsyncValue<DatasetCatalogList> catalogAsync,
  }) {
    final zetaColors = Zeta.of(context).colors;
    final sectionLabelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: zetaColors.mainSubtle,
    );

    Widget sectionHeader(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: sectionLabelStyle),
    );

    // ── Benchmark row ─────────────────────────────────────────────────────
    final selectedBenchmark = workspace.selectedBenchmarkId == null
        ? 'None'
        : (scratchBenchmarks
                  .where((b) => b.id == workspace.selectedBenchmarkId)
                  .isNotEmpty
              ? scratchBenchmarks
                    .firstWhere((b) => b.id == workspace.selectedBenchmarkId)
                    .label
              : 'None');

    // ── Frameworks row ────────────────────────────────────────────────────
    final selectedCount = workspace.selectedPlatforms.length;
    final frameworksTrailing = selectedCount == 0
        ? 'None'
        : '$selectedCount selected';

    // ── Dataset row ───────────────────────────────────────────────────────
    final datasetSubtitle = selectedEntry?.label ?? 'None selected';

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              // ── Section 1: Workspace ──────────────────────────────────
              sectionHeader('Workspace'),
              ZetaListItem(
                leading: Icon(
                  ZetaIcons.upload_file,
                  size: 20,
                  color: zetaColors.mainDefault,
                ),
                title: const Text('Load Workspace'),
                trailing: const Icon(ZetaIcons.chevron_right, size: 18),
                onTap: loadWorkspaceFromDevice,
              ),
              ZetaListItem(
                leading: Icon(
                  ZetaIcons.cloud_download,
                  size: 20,
                  color: zetaColors.mainDefault,
                ),
                title: const Text('Load from Hub'),
                trailing: const Icon(ZetaIcons.chevron_right, size: 18),
                onTap: openWorkspaceFromHub,
              ),
              ZetaListItem(
                leading: Icon(
                  ZetaIcons.server,
                  size: 20,
                  color: zetaColors.mainDefault,
                ),
                title: const Text('Load from server'),
                trailing: const Icon(ZetaIcons.chevron_right, size: 18),
                onTap: openWorkspaceFromServer,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: _errorBanner(
                    _workspaceError,
                    () => setState(() => _workspaceError = null),
                  ),
                ),
              ),

              // ── Section 2: Benchmark ──────────────────────────────────
              // No separate header — the row below already says "Benchmark";
              // repeating it as a header above is redundant on a phone-width
              // settings list.
              ZetaListItem(
                title: const Text('Benchmark'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selectedBenchmark,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: zetaColors.mainSubtle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(ZetaIcons.chevron_right, size: 18),
                  ],
                ),
                onTap: () => _showMobileBenchmarkSheet(context),
              ),

              // ── Section 3: Target platform ────────────────────────────
              // No separate header — see the "Benchmark" section above.
              ZetaListItem(
                title: const Text('Target platform'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      frameworksTrailing,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: zetaColors.mainSubtle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(ZetaIcons.chevron_right, size: 18),
                  ],
                ),
                onTap: () => _showMobileFrameworksSheet(context),
              ),
              // Summary of selected targets — same widget desktop uses, so
              // "Manage Targets" (akida / sc_neurocore_fpga), the per-target
              // reachability dot, and quick single-target removal are all
              // reachable here too, instead of only via the bulk checkbox
              // sheet above. Self-hides via SizedBox.shrink() when nothing
              // is selected.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSelectedPlatformsList(),
              ),

              // ── Section 4: Dataset ─────────────────────────────────────
              sectionHeader('Dataset'),
              ZetaListItem(
                leading: Icon(
                  ZetaIcons.download,
                  size: 20,
                  color: zetaColors.mainDefault,
                ),
                primaryText: 'Download dataset',
                secondaryText: datasetSubtitle,
                trailing: const Icon(ZetaIcons.chevron_right, size: 18),
                onTap: () => _showMobileDatasetSheet(context, catalogAsync),
              ),
              ZetaListItem(
                leading: Icon(
                  ZetaIcons.upload_file,
                  size: 20,
                  color: zetaColors.mainDefault,
                ),
                title: const Text('Import from device'),
                trailing: _isImportingDataset
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _isImportingDataset ? null : _importDatasetFromDevice,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: _errorBanner(
                    _downloadError,
                    () => setState(() => _downloadError = null),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> loadWorkspaceFromDevice() async {
    setState(() => _workspaceError = null);
    try {
      final workspaceFile = await ref
          .read(nativeFileAdapterProvider)
          .openWorkspaceFile();
      if (workspaceFile == null || !mounted) return;
      ref
          .read(workspaceProvider.notifier)
          .replaceFromWorkspacePayload(
            workspaceFile.payload,
            sourceFileName: workspaceFile.name,
            sourceFilePath: workspaceFile.path,
          );
      final restoreFailed = restoreCanvasSectionFromPayload(
        ref,
        workspaceFile.payload,
      );
      if (!mounted) return;
      if (restoreFailed) {
        setState(() {
          _workspaceError =
              'Opened ${workspaceFile.name}, but part of its canvas state '
              '(pipeline, simulation, or layout) could not be restored. '
              'Check the logs and re-save to repair the file.';
        });
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        NmtkSnackBars.success(context, 'Opened ${workspaceFile.name}.'),
      );
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _workspaceError =
            'Workspace file must contain a valid workspace JSON object.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _workspaceError =
            'Workspace open failed. Check the file and try again.';
      });
    }
  }

  void _showMobileBenchmarkSheet(BuildContext context) {
    final currentId = ref.read(workspaceProvider).selectedBenchmarkId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        // DraggableScrollableSheet + a scroll-controlled ListView keeps this
        // bounded no matter how many benchmarks exist — an unbounded Column
        // here previously overflowed once the list got long enough (same bug
        // class fixed in _showMobileFrameworksSheet below).
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Select Benchmark',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        ZetaListItem(
                          title: const Text('No benchmark'),
                          trailing: currentId == null
                              ? Icon(
                                  ZetaIcons.check_circle,
                                  size: 18,
                                  color: Zeta.of(context).colors.mainPrimary,
                                )
                              : null,
                          onTap: () {
                            ref
                                .read(workspaceProvider.notifier)
                                .setBenchmarkSelection(
                                  benchmarkId: null,
                                  benchmarkName: null,
                                  sourceKind: null,
                                );
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                        for (final benchmark in scratchBenchmarks)
                          ZetaListItem(
                            primaryText: benchmark.label,
                            secondaryText: benchmark.subtitle,
                            trailing: currentId == benchmark.id
                                ? Icon(
                                    ZetaIcons.check_circle,
                                    size: 18,
                                    color: Zeta.of(context).colors.mainPrimary,
                                  )
                                : null,
                            onTap: () {
                              ref
                                  .read(workspaceProvider.notifier)
                                  .setBenchmarkSelection(
                                    benchmarkId: benchmark.id,
                                    benchmarkName: benchmark.label,
                                    sourceKind: 'scratch',
                                  );
                              Navigator.of(sheetContext).pop();
                            },
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMobileFrameworksSheet(BuildContext context) {
    final availability =
        ref.read(targetAvailabilityProvider).value ?? const <String, bool>{};
    // Capture current selection into local mutable list so the sheet tracks
    // its own state without needing Riverpod inside the modal builder.
    // Pending changes are flushed to the provider only when Done is tapped.
    final localSelected = List<String>.from(
      ref.read(workspaceProvider).selectedPlatforms,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (builderContext, setSheetState) {
            final warningColor = Zeta.of(sheetContext).colors.mainWarning;
            // DraggableScrollableSheet + a scroll-controlled ListView keeps
            // this bounded regardless of how many deploy targets exist — a
            // plain unbounded Column here previously overflowed and made the
            // checkboxes and "Done" button unreachable.
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Select targets',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            for (final target in deployTargets)
                              ZetaListItem(
                                leading: Icon(
                                  (availability[target.id] ?? true)
                                      ? target.icon
                                      : ZetaIcons.download,
                                  size: 20,
                                  color: (availability[target.id] ?? true)
                                      ? null
                                      : warningColor,
                                ),
                                // ZetaListItem has no subtitle slot, so the
                                // role line rides inside the title column.
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            target.label,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        PlatformRoleBadge(targetId: target.id),
                                        const SizedBox(width: 4),
                                        NeurocnlInfoButton(
                                          title: target.label,
                                          message: platformRoleDescription(
                                            target.id,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Checkbox(
                                  value: localSelected.contains(target.id),
                                  onChanged: (_) {
                                    setSheetState(() {
                                      if (localSelected.contains(target.id)) {
                                        localSelected.remove(target.id);
                                      } else {
                                        localSelected.add(target.id);
                                      }
                                    });
                                  },
                                ),
                                onTap: () {
                                  setSheetState(() {
                                    if (localSelected.contains(target.id)) {
                                      localSelected.remove(target.id);
                                    } else {
                                      localSelected.add(target.id);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              // Apply diff between original and local selection.
                              final original = ref
                                  .read(workspaceProvider)
                                  .selectedPlatforms;
                              for (final id in localSelected) {
                                if (!original.contains(id)) {
                                  ref
                                      .read(workspaceProvider.notifier)
                                      .togglePlatform(id);
                                }
                              }
                              for (final id in original) {
                                if (!localSelected.contains(id)) {
                                  ref
                                      .read(workspaceProvider.notifier)
                                      .togglePlatform(id);
                                }
                              }
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text('Done'),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showMobileDatasetSheet(
    BuildContext context,
    AsyncValue<DatasetCatalogList> catalogAsync,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Select Dataset',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: catalogAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load dataset catalog. Please retry from the main screen.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      data: (catalog) {
                        if (catalog.folders.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No datasets available.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          );
                        }
                        final selectedId = ref
                            .read(workspaceProvider)
                            .selectedDataset;
                        return ListView(
                          controller: scrollController,
                          children: [
                            for (final folder in catalog.folders)
                              DatasetFolderSection(
                                folder: folder,
                                selectedDatasetId: selectedId,
                                onFileTapped: (entry) {
                                  _onDatasetTapped(entry);
                                  Navigator.of(sheetContext).pop();
                                },
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _importDatasetFromDevice() async {
    setState(() {
      _downloadError = null;
      _isImportingDataset = true;
    });
    try {
      final picked = await ref
          .read(nativeFileAdapterProvider)
          .openDatasetImport();
      if (picked == null || !mounted) {
        return;
      }
      final entry = await ref
          .read(datasetCatalogProvider.notifier)
          .importFromDevice(picked);
      if (!mounted) return;
      ref
          .read(workspaceProvider.notifier)
          .selectDataset(entry.id, serverPath: entry.localPath);
      final formatLabel = entry.format?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            formatLabel == null || formatLabel.isEmpty
                ? 'Imported ${entry.label}'
                : 'Imported ${entry.label} ($formatLabel)',
          ),
          showCloseIcon: true,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadError = describeDatasetActionError(e, action: 'Import');
      });
    } finally {
      if (mounted) {
        setState(() => _isImportingDataset = false);
      }
    }
  }

  Future<void> _onDatasetTapped(DatasetEntry entry) async {
    setState(() => _downloadError = null);

    // Already on server — select immediately with its local path, no download.
    if (entry.isReady) {
      ref
          .read(workspaceProvider.notifier)
          .selectDataset(entry.id, serverPath: entry.localPath);
      return;
    }

    // Download in progress — let the existing job finish, don't re-trigger.
    if (entry.isDownloading) {
      return;
    }

    // Not yet downloaded — optimistically mark as selected (no path yet) then
    // trigger the download.  selectDataset is called again with the real path
    // once the download completes.
    ref.read(workspaceProvider.notifier).selectDataset(entry.id);

    try {
      final path = await ref
          .read(datasetCatalogProvider.notifier)
          .downloadToServer(entry.id);
      if (!mounted) return;
      ref
          .read(workspaceProvider.notifier)
          .selectDataset(entry.id, serverPath: path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadError = describeDatasetActionError(e, action: 'Download');
      });
    }
  }

  Widget _buildScratchBenchmarkPicker() {
    final workspace = ref.watch(workspaceProvider);
    final selectedBenchmarkId = workspace.selectedBenchmarkId;
    final selectedValue =
        scratchBenchmarks.any((item) => item.id == selectedBenchmarkId)
        ? selectedBenchmarkId
        : null;
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: selectedValue,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('No benchmark'),
        ),
        ...scratchBenchmarks.map(
          (benchmark) => DropdownMenuItem<String?>(
            value: benchmark.id,
            child: Text(benchmark.label, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) {
        if (value == null) {
          ref
              .read(workspaceProvider.notifier)
              .setBenchmarkSelection(
                benchmarkId: null,
                benchmarkName: null,
                sourceKind: null,
              );
        } else {
          final benchmark = scratchBenchmarks.firstWhere(
            (item) => item.id == value,
          );
          ref
              .read(workspaceProvider.notifier)
              .setBenchmarkSelection(
                benchmarkId: benchmark.id,
                benchmarkName: benchmark.label,
                sourceKind: 'scratch',
              );
        }
      },
    );
  }

  Future<void> openWorkspaceFromHub() async {
    setState(() => _workspaceError = null);
    await showHubPopup(context, intent: HubPopupIntent.workspaces);
  }

  Future<void> openWorkspaceFromServer() async {
    setState(() => _workspaceError = null);
    try {
      final choice = await showDialog<ServerWorkspaceChoice>(
        context: context,
        builder: (dialogContext) => const ServerWorkspacePickerDialog(),
      );
      if (choice == null || !mounted) {
        return;
      }

      final config = await ref
          .read(apiClientProvider)
          .getServerWorkspace(choice.slug);

      ref
          .read(workspaceProvider.notifier)
          .replaceFromWorkspacePayload(
            config,
            sourceFileName: choice.name,
            // A server workspace has no local file of its own — explicitly
            // clear any path left over from a previously-opened local file,
            // same reasoning as the Hub open path above.
            sourceFilePath: null,
          );
      final restoreFailed = restoreCanvasSectionFromPayload(ref, config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        restoreFailed
            ? NmtkSnackBars.error(
                context,
                'Opened ${choice.name} from server, but part of its canvas '
                'state (pipeline, simulation, or layout) could not be '
                'restored.',
              )
            : NmtkSnackBars.success(
                context,
                'Opened ${choice.name} from server.',
              ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _workspaceError = error is FormatException
            ? error.message
            : 'Server workspace open failed. Check the server connection and try again.';
      });
    }
  }
}
