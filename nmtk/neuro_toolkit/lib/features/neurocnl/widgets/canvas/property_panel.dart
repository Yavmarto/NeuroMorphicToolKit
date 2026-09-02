import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/nir_types_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/labeled_parameter_grid.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/custom_node_source_editor.dart';

class PropertyPanel extends ConsumerWidget {
  const PropertyPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow subscriptions so this panel only rebuilds when the SELECTED
    // node's own data changes — not on unrelated canvas edits.
    final selectedEdgeId = ref.watch(
      canvasProvider.select((s) => s.selectedEdgeId),
    );
    final selectedNodeIds = ref.watch(
      canvasProvider.select((s) => s.selectedNodeIds),
    );
    final selectedNodeId = ref.watch(
      canvasProvider.select((s) => s.primarySelectedNodeId),
    );
    // Watch the selected node itself; identity preserved for un-edited nodes by
    // updateNodeParameters, so unrelated parameter changes don't trigger a
    // rebuild here.
    final node = ref.watch(
      canvasProvider.select((s) {
        if (s.primarySelectedNodeId == null) return null;
        final matches = s.graph.nodes.where(
          (n) => n.id == s.primarySelectedNodeId,
        );
        return matches.isEmpty ? null : matches.first;
      }),
    );
    // Only needed to annotate a Linear/Affine node's Rows/Cols fields with
    // the connected population's name — watched separately so edits to
    // unrelated nodes/edges don't rebuild this panel unnecessarily beyond
    // that same narrow purpose.
    final graph = ref.watch(canvasProvider.select((s) => s.graph));
    final tokens = NmtkShellTokens.of(context);

    if (selectedEdgeId != null) {
      return _EdgePropertyPanel(edgeId: selectedEdgeId);
    }

    if (selectedNodeIds.length > 1) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${selectedNodeIds.length} nodes selected',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.metadataForeground),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (selectedNodeId == null || node == null) {
      return const _NetworkSettingsPanel();
    }

    final nirTypeMap = ref.watch(nirNodeTypeMapProvider);
    final nodeType = nirTypeMap[node.nirType ?? node.componentId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  resolveNodeDisplayName(node),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Tooltip(
                message: 'Delete node',
                child: ZetaIconButton.text(
                  icon: ZetaIcons.delete_outline,
                  size: ZetaWidgetSize.small,
                  semanticLabel: 'Delete node',
                  onPressed: () =>
                      ref.read(canvasProvider.notifier).deleteSelection(),
                ),
              ),
              Tooltip(
                message: 'Close inspector',
                child: ZetaIconButton.text(
                  icon: ZetaIcons.close,
                  size: ZetaWidgetSize.small,
                  semanticLabel: 'Close inspector',
                  onPressed: () =>
                      ref.read(canvasProvider.notifier).selectNode(null),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // centerLeft, not stretch: `Alignment.stretch` does not exist,
              // and this matches how the pipeline inspector places the same
              // button.
              Align(
                alignment: Alignment.centerLeft,
                child: NmtkOutlinedButton(
                  icon: Icons.code,
                  label: node.componentId.startsWith('custom_')
                      ? 'Edit Python'
                      : 'View Python',
                  onPressed: () async {
                    final outcome = await showCustomNodeSourceEditor(
                      context: context,
                      node: node,
                      nodeType: nodeType,
                    );
                    if (!context.mounted || outcome == null) return;
                    final message = outcome.replacedSelectedNode
                        ? 'Custom node saved and selected on the canvas.'
                        : 'Custom node saved to the reusable component palette.';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message), showCloseIcon: true),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              LabeledParameterGrid(
                children: [
                  if (node.nirType != null)
                    LabeledParameterRow(
                      label: 'NIR Type',
                      child: CanvasParameterTextField(
                        key: ValueKey('${node.id}__nirType'),
                        label: 'NIR Type',
                        showLabel: false,
                        value: node.nirType!,
                        onCommit: (_) {},
                        enabled: false,
                      ),
                    ),
                  if (nodeType != null)
                    for (final NirParameterDef parameter in nodeType.parameters)
                      _buildParameterField(context, ref, node, parameter, graph)
                  else
                    LabeledParameterRow(
                      label: 'Parameters',
                      child: CanvasParameterTextField(
                        key: ValueKey('${node.id}__params_fallback'),
                        label: 'Parameters',
                        showLabel: false,
                        value: node.parameters.toString(),
                        onCommit: (_) {},
                        enabled: false,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParameterField(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    NirParameterDef parameter,
    CanvasGraph graph,
  ) {
    final currentValue =
        node.parameters[parameter.name] ?? parameter.defaultValue;
    final TextInputType numericKeyboard = const TextInputType.numberWithOptions(
      decimal: true,
    );
    final label = _connectedParameterLabel(node, parameter, graph);

    if (parameter.type == 'float' ||
        parameter.type == 'int' ||
        parameter.type == 'text') {
      return LabeledParameterRow(
        label: label,
        child: CanvasParameterTextField(
          key: ValueKey('${node.id}__param__${parameter.name}'),
          label: label,
          showLabel: false,
          keyboardType: parameter.type == 'text'
              ? TextInputType.text
              : numericKeyboard,
          value: currentValue?.toString() ?? '',
          onCommit: (String value) {
            final Object nextValue;
            if (parameter.type == 'text') {
              final Object? normalized = _normalizeTextParameter(
                parameter.name,
                value,
              );
              if (normalized == null) {
                return;
              }
              nextValue = normalized;
            } else {
              num? parsed = parameter.type == 'int'
                  ? int.tryParse(value)
                  : double.tryParse(value);
              if (parsed == null) {
                return;
              }
              if (parameter.min != null && parsed < parameter.min!) {
                parsed = parameter.min!;
              }
              if (parameter.max != null && parsed > parameter.max!) {
                parsed = parameter.max!;
              }
              nextValue = parameter.type == 'int' ? parsed.round() : parsed;
            }
            ref.read(canvasProvider.notifier).updateNodeParameters(node.id, {
              parameter.name: nextValue,
            });
          },
        ),
      );
    }

    if (parameter.type == 'bool') {
      return LabeledParameterRow(
        label: parameter.label,
        child: Align(
          alignment: Alignment.centerLeft,
          child: ZetaSwitch(
            value: currentValue as bool? ?? false,
            onChanged: (bool? value) {
              ref.read(canvasProvider.notifier).updateNodeParameters(node.id, {
                parameter.name: value ?? false,
              });
            },
          ),
        ),
      );
    }

    if (parameter.type == 'enum' && parameter.enumValues != null) {
      return LabeledParameterRow(
        label: parameter.label,
        child: DropdownButtonFormField<String>(
          // Same reason as the pipeline inspector's _DropdownField: the label
          // column leaves this ~125px, and without isExpanded the dropdown's
          // internal Row sizes to its widest item and overflows.
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          initialValue: currentValue?.toString(),
          items: parameter.enumValues!
              .map(
                (String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            ref.read(canvasProvider.notifier).updateNodeParameters(node.id, {
              parameter.name: value,
            });
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Annotates a Linear/Affine node's `rows`/`cols` fields with the
  /// connected population's name — those fields are otherwise just bare
  /// dimension counts with no indication of which population feeds each one
  /// (NIR shape convention is `(rows, cols)` = `(out, in)`: `rows` is the
  /// size of the population this node feeds *into*, `cols` is the size of
  /// the population feeding *into* this node). Falls back to the plain
  /// label for every other parameter, and when the relevant side isn't
  /// wired up yet.
  String _connectedParameterLabel(
    CanvasNode node,
    NirParameterDef parameter,
    CanvasGraph graph,
  ) {
    final isShapeNode =
        node.nirType == 'nir.Linear' || node.nirType == 'nir.Affine';
    final isRows = parameter.name == 'rows';
    final isCols = parameter.name == 'cols';
    if (!isShapeNode || !(isRows || isCols)) {
      return parameter.label;
    }

    CanvasEdge? edge;
    for (final e in graph.edges) {
      if (isRows ? e.sourceNodeId == node.id : e.targetNodeId == node.id) {
        edge = e;
        break;
      }
    }
    if (edge == null) {
      return parameter.label;
    }

    final otherId = isRows ? edge.targetNodeId : edge.sourceNodeId;
    CanvasNode? other;
    for (final n in graph.nodes) {
      if (n.id == otherId) {
        other = n;
        break;
      }
    }
    if (other == null) {
      return parameter.label;
    }

    final name = resolveNodeDisplayName(other);
    return isRows ? '${parameter.label} → $name' : '${parameter.label} ← $name';
  }

  Object? _normalizeTextParameter(String name, String rawValue) {
    final String trimmed = rawValue.trim();
    if (trimmed.contains(',')) {
      return trimmed
          .split(',')
          .map((String part) => int.tryParse(part.trim()))
          .whereType<int>()
          .toList();
    }
    if (name == 'weight_shape') {
      final int? parsed = int.tryParse(trimmed);
      return parsed == null ? null : <int>[parsed];
    }
    return trimmed;
  }
}

class _NetworkSettingsPanel extends ConsumerWidget {
  const _NetworkSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = NmtkShellTokens.of(context);
    final dtRaw = ref.watch(
      canvasProvider.select((s) => s.graph.metadata['dt']),
    );
    final double? dt = (dtRaw as num?)?.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Text(
            'Network Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Select a node or connection to inspect its parameters.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.metadataForeground,
                ),
              ),
              const SizedBox(height: 16),
              LabeledParameterGrid(
                children: [
                  LabeledParameterRow(
                    label: 'Network Timestep (s)',
                    child: CanvasParameterTextField(
                      key: const ValueKey('network__dt'),
                      label: 'Network Timestep (s)',
                      showLabel: false,
                      value: dt == null ? '' : displayCanvasParameterValue(dt),
                      hintText: 'Unset — defaults to 1e-4 s',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onCommit: (String value) {
                        final trimmed = value.trim();
                        if (trimmed.isEmpty) {
                          ref
                              .read(canvasProvider.notifier)
                              .setNetworkTimestepSeconds(null);
                          return;
                        }
                        final parsed = double.tryParse(trimmed);
                        if (parsed == null || parsed <= 0) return;
                        ref
                            .read(canvasProvider.notifier)
                            .setNetworkTimestepSeconds(parsed);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EdgePropertyPanel extends ConsumerWidget {
  const _EdgePropertyPanel({required this.edgeId});

  final String edgeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CanvasEdge? edge = ref.watch(
      canvasProvider.select((s) {
        final matches = s.graph.edges.where((e) => e.id == edgeId);
        return matches.isEmpty ? null : matches.first;
      }),
    );
    final tokens = NmtkShellTokens.of(context);
    if (edge == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This connection no longer exists.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.metadataForeground),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Connection Inspector',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Tooltip(
                message: 'Delete connection',
                child: ZetaIconButton.text(
                  icon: ZetaIcons.delete_outline,
                  size: ZetaWidgetSize.small,
                  semanticLabel: 'Delete connection',
                  onPressed: () =>
                      ref.read(canvasProvider.notifier).removeEdge(edgeId),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LabeledParameterGrid(
                children: [
                  LabeledParameterRow(
                    label: 'From',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(edge.sourceNodeId),
                    ),
                  ),
                  LabeledParameterRow(
                    label: 'Port',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(edge.sourcePort),
                    ),
                  ),
                  LabeledParameterRow(
                    label: 'To',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(edge.targetNodeId),
                    ),
                  ),
                  LabeledParameterRow(
                    label: 'Port',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(edge.targetPort),
                    ),
                  ),
                  LabeledParameterRow(
                    label: 'Weight',
                    child: CanvasParameterTextField(
                      key: ValueKey('${edgeId}__weight'),
                      label: 'Weight',
                      showLabel: false,
                      value: (edge.parameters['weight'] ?? 1.0).toString(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onCommit: (String value) {
                        final double? parsed = double.tryParse(value);
                        if (parsed == null) {
                          return;
                        }
                        final Map<String, dynamic> nextParameters =
                            Map<String, dynamic>.from(edge.parameters)
                              ..['weight'] = parsed;
                        ref
                            .read(canvasProvider.notifier)
                            .updateEdgeParameters(edge.id, nextParameters);
                      },
                    ),
                  ),
                  LabeledParameterRow(
                    label: 'Delay',
                    child: CanvasParameterTextField(
                      key: ValueKey('${edgeId}__delay'),
                      label: 'Delay',
                      showLabel: false,
                      value: (edge.parameters['delay'] ?? 0.0).toString(),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onCommit: (String value) {
                        final double? parsed = double.tryParse(value);
                        if (parsed == null) {
                          return;
                        }
                        final Map<String, dynamic> nextParameters =
                            Map<String, dynamic>.from(edge.parameters)
                              ..['delay'] = parsed;
                        ref
                            .read(canvasProvider.notifier)
                            .updateEdgeParameters(edge.id, nextParameters);
                      },
                    ),
                  ),
                  LabeledParameterRow(
                    label: 'Polarity',
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('${edgeId}__polarity'),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      initialValue:
                          (edge.parameters['polarity'] ?? 'excitatory')
                              .toString(),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'excitatory',
                          child: Text('Excitatory'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'inhibitory',
                          child: Text('Inhibitory'),
                        ),
                      ],
                      onChanged: (String? value) {
                        if (value == null) {
                          return;
                        }
                        final Map<String, dynamic> nextParameters =
                            Map<String, dynamic>.from(edge.parameters)
                              ..['polarity'] = value;
                        ref
                            .read(canvasProvider.notifier)
                            .updateEdgeParameters(edge.id, nextParameters);
                      },
                    ),
                  ),
                  LabeledParameterRow(
                    label: 'Learning Rule',
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('${edgeId}__learning_rule'),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      initialValue: (edge.parameters['learning_rule'] ?? 'none')
                          .toString(),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'none',
                          child: Text('None'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'stdp',
                          child: Text('STDP'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'surrogate_gradient',
                          child: Text('Surrogate Gradient'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'hebbian',
                          child: Text('Hebbian'),
                        ),
                      ],
                      onChanged: (String? value) {
                        if (value == null) return;
                        final Map<String, dynamic> nextParameters =
                            Map<String, dynamic>.from(edge.parameters);
                        if (value == 'none') {
                          nextParameters.remove('learning_rule');
                          nextParameters.remove('stdp_a_plus');
                          nextParameters.remove('stdp_a_minus');
                          nextParameters.remove('stdp_tau_plus');
                          nextParameters.remove('stdp_tau_minus');
                        } else {
                          nextParameters['learning_rule'] = value;
                          if (value != 'stdp') {
                            nextParameters.remove('stdp_a_plus');
                            nextParameters.remove('stdp_a_minus');
                            nextParameters.remove('stdp_tau_plus');
                            nextParameters.remove('stdp_tau_minus');
                          }
                        }
                        ref
                            .read(canvasProvider.notifier)
                            .updateEdgeParameters(edge.id, nextParameters);
                      },
                    ),
                  ),
                  if ((edge.parameters['learning_rule'] ?? 'none') ==
                      'stdp') ...<Widget>[
                    LabeledParameterRow(
                      label: 'A+',
                      child: CanvasParameterTextField(
                        key: ValueKey('${edgeId}__stdp_a_plus'),
                        label: 'A+',
                        showLabel: false,
                        value: (edge.parameters['stdp_a_plus'] ?? 0.01)
                            .toString(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onCommit: (String v) {
                          final double? parsed = double.tryParse(v);
                          if (parsed == null) return;
                          ref
                              .read(canvasProvider.notifier)
                              .updateEdgeParameters(
                                edge.id,
                                Map<String, dynamic>.from(edge.parameters)
                                  ..['stdp_a_plus'] = parsed,
                              );
                        },
                      ),
                    ),
                    LabeledParameterRow(
                      label: 'A−',
                      child: CanvasParameterTextField(
                        key: ValueKey('${edgeId}__stdp_a_minus'),
                        label: 'A−',
                        showLabel: false,
                        value: (edge.parameters['stdp_a_minus'] ?? 0.01)
                            .toString(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onCommit: (String v) {
                          final double? parsed = double.tryParse(v);
                          if (parsed == null) return;
                          ref
                              .read(canvasProvider.notifier)
                              .updateEdgeParameters(
                                edge.id,
                                Map<String, dynamic>.from(edge.parameters)
                                  ..['stdp_a_minus'] = parsed,
                              );
                        },
                      ),
                    ),
                    LabeledParameterRow(
                      label: 'τ+',
                      child: CanvasParameterTextField(
                        key: ValueKey('${edgeId}__stdp_tau_plus'),
                        label: 'τ+',
                        showLabel: false,
                        value: (edge.parameters['stdp_tau_plus'] ?? 0.02)
                            .toString(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onCommit: (String v) {
                          final double? parsed = double.tryParse(v);
                          if (parsed == null) return;
                          ref
                              .read(canvasProvider.notifier)
                              .updateEdgeParameters(
                                edge.id,
                                Map<String, dynamic>.from(edge.parameters)
                                  ..['stdp_tau_plus'] = parsed,
                              );
                        },
                      ),
                    ),
                    LabeledParameterRow(
                      label: 'τ−',
                      child: CanvasParameterTextField(
                        key: ValueKey('${edgeId}__stdp_tau_minus'),
                        label: 'τ−',
                        showLabel: false,
                        value: (edge.parameters['stdp_tau_minus'] ?? 0.02)
                            .toString(),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onCommit: (String v) {
                          final double? parsed = double.tryParse(v);
                          if (parsed == null) return;
                          ref
                              .read(canvasProvider.notifier)
                              .updateEdgeParameters(
                                edge.id,
                                Map<String, dynamic>.from(edge.parameters)
                                  ..['stdp_tau_minus'] = parsed,
                              );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
