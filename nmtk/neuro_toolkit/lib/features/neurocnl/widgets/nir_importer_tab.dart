import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart'
    show
        ZetaIcons,
        NmtkFontFamilies,
        NmtkShellTokens,
        NmtkStatusBanner,
        NmtkTone,
        ZetaAssistChip,
        ZetaButton;

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_hdf5_tree.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_ui_state_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_preflight_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/theme/app_theme.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/labeled_parameter_grid.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';

/// NIR tab for CNL Studio — bidirectional sync with CNL editor and Canvas.
class NirImporterTab extends ConsumerStatefulWidget {
  const NirImporterTab({super.key});

  @override
  ConsumerState<NirImporterTab> createState() => _NirImporterTabState();
}

class _NirImporterTabState extends ConsumerState<NirImporterTab> {
  static const _simulatorTargets = {'lava_sim', 'snntorch_sim'};

  @override
  void initState() {
    super.initState();
    ref.listenManual<NirImportState>(nirImportProvider, (previous, next) {
      if (next is NirImportLoaded &&
          next.source == NirSource.file &&
          !next.writeBackConsumed) {
        ref.read(nirImportProvider.notifier).markWriteBackConsumed();
        _applyWriteBack(next);
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nirImportProvider);

    final source = switch (state) {
      NirImportIdle() => NirSource.none,
      NirImportLoading(:final source) => source,
      NirImportError(:final source) => source,
      NirImportLoaded(:final source) => source,
    };

    return Material(
      color: AppTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NirHeader(source: source, onLoad: () => _pickAndInspect()),
          Expanded(child: _NirBody(state: state)),
        ],
      ),
    );
  }

  Future<void> _pickAndInspect() async {
    final files = await const FilePickerDialogGateway().pickFiles(
      allowMultiple: false,
      allowedExtensions: const ['nir'],
    );
    if (files == null || files.isEmpty) return;
    final f = files.first;
    await ref.read(nirImportProvider.notifier).inspectFile(f.name, f.bytes);
    // Publish the canonical doc only after the raw NIR has been inspected and
    // registered, so notebook generation keeps the import_id for real weights.
    unawaited(
      ref.read(canonicalDocProvider.notifier).updateFromNirFile(f.bytes),
    );
  }

  void _applyWriteBack(NirImportLoaded state) {
    final selectedTarget = ref.read(
      workspaceProvider.select((w) => w.selectedDeployTarget),
    );
    if (_simulatorTargets.contains(selectedTarget)) {
      final nirBytes = state.rawBytes;
      if (nirBytes != null) {
        ref
            .read(simulatorPreflightProvider.notifier)
            .runPreflightNir(nirBytes, selectedTarget);
      }
    }
  }
}

class _NirHeader extends StatelessWidget {
  const _NirHeader({required this.source, required this.onLoad})
    : onClear = null;

  final NirSource source;
  final VoidCallback onLoad;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons
                .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
            size: 16,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text(
              'NIR Inspector',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _SourceBadge(source: source),
          const Spacer(),
          if (onClear != null) ...[
            ZetaButton.text(onPressed: onClear, label: 'Clear'),
            const SizedBox(width: 6),
          ],
          ZetaButton(
            onPressed: onLoad,
            label: 'Load .nir',
            leadingIcon: ZetaIcons.file,
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final NirSource source;

  @override
  Widget build(BuildContext context) {
    final label = switch (source) {
      NirSource.none => 'idle',
      NirSource.file => 'from file',
      NirSource.canvas => 'from canvas',
      NirSource.pipeline => 'from pipeline',
    };

    final icon = switch (source) {
      NirSource.none => ZetaIcons.radio_button_unchecked,
      NirSource.file => ZetaIcons.upload_file,
      NirSource.canvas =>
        Icons.schema_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      NirSource.pipeline =>
        Icons
            .auto_awesome_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    };

    return ZetaAssistChip(label: label, leading: Icon(icon, size: 16));
  }
}

class _NirBody extends StatelessWidget {
  const _NirBody({required this.state});

  final NirImportState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      NirImportIdle() => const _IdlePlaceholder(),
      NirImportLoading() => const Center(child: CircularProgressIndicator()),
      NirImportError(:final error) => _ErrorView(message: error),
      NirImportLoaded(:final result, :final source) => _LoadedView(
        result: result,
        source: source,
        hadWriteBack: source == NirSource.file,
      ),
    };
  }
}

class _IdlePlaceholder extends StatelessWidget {
  const _IdlePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ZetaIcons.folder_outline,
            size: 52,
            color: AppTheme.textSecondary.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 14),
          const Text(
            'No NIR graph loaded.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Press "Load .nir" to import a NIR file, or run Generate in the pipeline\n'
            'to auto-populate this view from the current CNL spec.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = NmtkShellTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ZetaIcons.error_outline, size: 40, color: tokens.errorColor),
            const SizedBox(height: 12),
            const Text(
              'Failed to parse NIR file',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(
                  NmtkShellTokens.of(context).radiusSm,
                ),
                border: Border.all(
                  color: tokens.errorColor.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: tokens.errorColor,
                  fontSize: 11,
                  fontFamily: NmtkFontFamilies.monospace,
                  package: NmtkFontFamilies.package,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedView extends ConsumerWidget {
  const _LoadedView({
    required this.result,
    required this.source,
    required this.hadWriteBack,
  });

  final NirInspectResult result;
  final NirSource source;
  final bool hadWriteBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hadWriteBack && source == NirSource.file)
          const _WriteBackBanner(hasCnl: true, hasCanvas: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MetaChip(icon: ZetaIcons.file, label: result.fileName),
              _MetaChip(
                icon: Icons.storage_outlined,
                label: result.sizeLabel,
              ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              _MetaChip(
                icon: Icons
                    .hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: '${_countNodes(result.root)} items',
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppTheme.border),
        const Expanded(child: _NirGraphEditorPanel()),
      ],
    );
  }

  int _countNodes(NirHdf5Group group) {
    var count = group.children.length;
    for (final child in group.children) {
      if (child is NirHdf5Group) count += _countNodes(child);
    }
    return count;
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ZetaAssistChip(label: label, leading: Icon(icon));
  }
}

class _NirGraphEditorPanel extends ConsumerWidget {
  const _NirGraphEditorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeIds = ref.watch(
      canvasProvider.select((s) => s.graph.nodes.map((n) => n.id).join('\x00')),
    );
    if (nodeIds.isEmpty) return const _EmptyGraphEditor();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      children: [
        for (final id in nodeIds.split('\x00'))
          _NirNodeCard(key: ValueKey(id), nodeId: id),
        const _NirEdgeList(),
      ],
    );
  }
}

class _EmptyGraphEditor extends StatelessWidget {
  const _EmptyGraphEditor();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No editable NIR graph nodes.',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _NirNodeCard extends ConsumerStatefulWidget {
  const _NirNodeCard({super.key, required this.nodeId});

  final String nodeId;

  @override
  ConsumerState<_NirNodeCard> createState() => _NirNodeCardState();
}

class _NirNodeCardState extends ConsumerState<_NirNodeCard> {
  late final ExpansibleController _expansionController;
  ProviderSubscription<bool>? _expansionSubscription;

  @override
  void initState() {
    super.initState();
    _expansionController = ExpansibleController();
    _expansionSubscription = ref.listenManual<bool>(
      nirNodeExpandedProvider(widget.nodeId),
      (_, bool next) {
        if (!mounted || next == _expansionController.isExpanded) {
          return;
        }
        if (next) {
          _expansionController.expand();
        } else {
          _expansionController.collapse();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (ref.read(nirNodeExpandedProvider(widget.nodeId))) {
        _expansionController.expand();
      }
    });
  }

  @override
  void dispose() {
    _expansionSubscription?.close();
    _expansionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = ref.watch(
      canvasProvider.select(
        (s) => s.graph.nodes.firstWhere(
          (n) => n.id == widget.nodeId,
          orElse: () => CanvasNode(
            id: widget.nodeId,
            componentId: '',
            parameters: const {},
            position: const [0, 0],
            metadata: const {},
          ),
        ),
      ),
    );
    final typeMap = ref.watch(nirNodeTypeMapProvider);
    final nodeType = typeMap[node.nirType ?? node.componentId];
    final params = node.parameters;
    final title = resolveNodeDisplayName(node);
    ref.watch(nirNodeExpandedProvider(widget.nodeId));
    final parameterNames = <String>{
      if (nodeType != null) ...nodeType.parameters.map((p) => p.name),
      ...params.keys.where((key) => key != 'name' && key != 'nir_type'),
    }.toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        controller: _expansionController,
        initiallyExpanded: false,
        maintainState: true,
        onExpansionChanged: (bool expanded) {
          ref
              .read(nirUiStateProvider.notifier)
              .setNodeExpanded(widget.nodeId, expanded);
        },
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          node.nirType ?? node.componentId,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        trailing: IconButton(
          tooltip: 'Delete node',
          icon: const Icon(ZetaIcons.delete_outline, size: 18),
          onPressed: () {
            ref.read(canvasProvider.notifier).removeNode(node.id);
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: LabeledParameterGrid(
              children: [
                for (final name in parameterNames)
                  _NirParameterField(
                    key: ValueKey('${node.id}__$name'),
                    node: node,
                    parameterName: name,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NirParameterField extends ConsumerWidget {
  const _NirParameterField({
    super.key,
    required this.node,
    required this.parameterName,
  });

  final CanvasNode node;
  final String parameterName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LabeledParameterRow(
      label: parameterName,
      child: CanvasParameterTextField(
        key: ValueKey('${node.id}__$parameterName'),
        label: parameterName,
        showLabel: false,
        value: _displayValue(node.parameters[parameterName]),
        onCommit: (value) {
          ref.read(canvasProvider.notifier).updateNodeParameters(node.id, {
            parameterName: _coerceValue(value, node.parameters[parameterName]),
          });
        },
      ),
    );
  }

  String _displayValue(Object? value) {
    if (value is double) {
      return value
          .toStringAsFixed(value.truncateToDouble() == value ? 1 : 6)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '.0');
    }
    return value?.toString() ?? '';
  }

  Object _coerceValue(String value, Object? previous) {
    if (previous is int) return int.tryParse(value) ?? previous;
    if (previous is double || previous is num) {
      return double.tryParse(value) ?? previous ?? value;
    }
    return value;
  }
}

class _NirEdgeList extends ConsumerWidget {
  const _NirEdgeList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(
      canvasProvider.select((s) => s.graph.edges.map((e) => e.id).join('\x00')),
    );
    final graph = ref.read(canvasProvider).graph;
    final canConnect = graph.nodes.length >= 2;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          NmtkShellTokens.of(context).radiusSm,
        ),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Connections',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add connection',
                  onPressed: canConnect
                      ? () {
                          final source = graph.nodes.first;
                          final target = graph.nodes.firstWhere(
                            (node) => node.id != source.id,
                            orElse: () => source,
                          );
                          if (source.id == target.id) return;
                          final edge = CanvasEdge(
                            id: 'edge_${source.id}_to_${target.id}_${graph.edges.length}',
                            sourceNodeId: source.id,
                            sourcePort: 'out',
                            targetNodeId: target.id,
                            targetPort: 'in',
                            parameters: const <String, dynamic>{
                              'synapse_type': 'static_synapse',
                              'weight': 1.0,
                              'delay': 0.001,
                            },
                          );
                          ref.read(canvasProvider.notifier).addEdge(edge);
                        }
                      : null,
                  icon: const Icon(
                    Icons.add_link,
                    size: 18,
                  ), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                ),
              ],
            ),
            for (final edge in graph.edges) _NirEdgeRow(edge: edge),
          ],
        ),
      ),
    );
  }
}

class _NirEdgeRow extends ConsumerWidget {
  const _NirEdgeRow({required this.edge});

  final CanvasEdge edge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${edge.sourceNodeId} -> ${edge.targetNodeId}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Delete connection',
            icon: const Icon(ZetaIcons.delete_outline, size: 18),
            onPressed: () {
              ref.read(canvasProvider.notifier).removeEdge(edge.id);
            },
          ),
        ],
      ),
    );
  }
}

class _WriteBackBanner extends StatelessWidget {
  const _WriteBackBanner({required this.hasCnl, required this.hasCanvas});

  final bool hasCnl;
  final bool hasCanvas;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[if (hasCnl) 'CNL editor', if (hasCanvas) 'Canvas'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: NmtkStatusBanner(
        title: 'Synced to ${parts.join(' & ')}',
        tone: NmtkTone.success,
        icon: ZetaIcons.sync,
      ),
    );
  }
}
