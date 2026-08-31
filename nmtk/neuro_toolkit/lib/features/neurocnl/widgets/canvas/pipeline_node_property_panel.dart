import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/custom_node_source_editor.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_job_ids_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';
import 'package:neuro_toolkit/features/neurocnl/services/local_dataset_file_reader.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/labeled_parameter_grid.dart';

// ── Main panel ────────────────────────────────────────────────────────────────

class PipelineNodePropertyPanel extends ConsumerWidget {
  const PipelineNodePropertyPanel({
    super.key,
    required this.phase,
    this.showDockChrome = true,
  });

  final PipelinePhaseId phase;

  /// The desktop dock's own background fill + left border seam that
  /// separates it from the canvas. A host that already provides its own
  /// surface (e.g. the mobile bottom sheet) sets this false so the panel
  /// doesn't paint a stray border/background floating mid-sheet.
  final bool showDockChrome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedNodeIds = ref.watch(
      canvasProvider.select((s) => s.selectedNodeIds),
    );
    final nodeId = ref.watch(canvasProvider.select((s) => s.selectedNodeId));
    final dag = ref.watch(
      canvasProvider.select((s) => s.pipelinePhases.dagFor(phase)),
    );
    final tokens = NmtkShellTokens.of(context);
    final textStyles = Zeta.of(context).textStyles;

    if (selectedNodeIds.length > 1) {
      return _placeholderMessage(
        context,
        tokens,
        '${selectedNodeIds.length} nodes selected',
      );
    }
    final node = nodeId == null
        ? null
        : dag.nodes.cast<PipelineDagNode?>().firstWhere(
            (n) => n?.id == nodeId,
            orElse: () => null,
          );
    if (node == null) {
      return _placeholderMessage(
        context,
        tokens,
        'Select a node to inspect its parameters.',
      );
    }

    void update(Map<String, dynamic> params) {
      ref
          .read(canvasProvider.notifier)
          .updatePipelineDagNodeParams(phase, node.id, params);
    }

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(node.type.label, style: textStyles.labelLarge),
              ),
              IconButton(
                icon: Icon(
                  ZetaIcons.delete_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                tooltip: 'Delete node',
                onPressed: () => ref
                    .read(canvasProvider.notifier)
                    .removePipelineDagNode(phase, node.id),
              ),
              IconButton(
                icon: Icon(
                  ZetaIcons.close,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () =>
                    ref.read(canvasProvider.notifier).selectNode(null),
                tooltip: 'Close inspector',
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.chromeBorder),
        // Fields
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.code, size: 18),
                    label: Text(
                      node.customComponentId == null
                          ? 'View Python'
                          : 'Edit Python',
                    ),
                    onPressed: () async {
                      final outcome = await showPipelineNodeSourceEditor(
                        context: context,
                        node: node,
                        phase: phase,
                      );
                      if (!context.mounted || outcome == null) return;
                      final message = outcome.replacedSelectedNode
                          ? 'Custom node saved and selected on the canvas.'
                          : 'Custom node saved to the reusable component palette.';
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _NodeFields(node: node, phase: phase, onUpdate: update),
              ],
            ),
          ),
        ),
      ],
    );

    if (!showDockChrome) return content;

    return Container(
      decoration: BoxDecoration(
        color: tokens.utilityPanelBackground,
        border: Border(left: BorderSide(color: tokens.chromeBorder)),
      ),
      child: content,
    );
  }
}

Widget _placeholderMessage(
  BuildContext context,
  NmtkShellTokens tokens,
  String text,
) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: tokens.metadataForeground),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

// ── Fields dispatcher ─────────────────────────────────────────────────────────

class _NodeFields extends ConsumerWidget {
  const _NodeFields({
    required this.node,
    required this.phase,
    required this.onUpdate,
  });

  final PipelineDagNode node;
  final PipelinePhaseId phase;
  final void Function(Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = {...node.type.defaultParameters, ...node.parameters};

    switch (node.type) {
      case PipelineDagNodeType.dataLoader:
      case PipelineDagNodeType.testLoader:
        return _DataLoaderFields(node: node, phase: phase, onUpdate: onUpdate);

      case PipelineDagNodeType.spikeGenerator:
        return _SpikeGeneratorFields(node: node, onUpdate: onUpdate);

      case PipelineDagNodeType.timeLoop:
        return _IntField(
          key: ValueKey('${node.id}__param__num_steps'),
          label: 'Time Steps',
          value: (p['num_steps'] as int?) ?? 25,
          onChanged: (v) => onUpdate({'num_steps': v}),
          hint: 'Braille reference: 256',
        );

      case PipelineDagNodeType.validationLoop:
        final saveBestCheckpoint = (p['save_best_checkpoint'] as bool?) ?? true;
        return Column(
          children: [
            _IntField(
              key: ValueKey('${node.id}__param__every_n_epochs'),
              label: 'Validate Every N Epochs',
              value: (p['every_n_epochs'] as int?) ?? 1,
              onChanged: (v) => onUpdate({'every_n_epochs': v}),
            ),
            const SizedBox(height: 12),
            _SwitchField(
              key: ValueKey('${node.id}__param__save_best_checkpoint'),
              label: 'Save Best Checkpoint',
              value: saveBestCheckpoint,
              onChanged: (v) => onUpdate({'save_best_checkpoint': v}),
            ),
            if (saveBestCheckpoint) ...[
              const SizedBox(height: 12),
              _DropdownField<String>(
                key: ValueKey('${node.id}__param__checkpoint_metric'),
                label: 'Checkpoint Metric',
                value: (p['checkpoint_metric'] as String?) ?? 'val_accuracy',
                options: const ['val_accuracy', 'val_loss'],
                onChanged: (v) => onUpdate({'checkpoint_metric': v}),
              ),
              const SizedBox(height: 12),
              _DropdownField<String>(
                key: ValueKey('${node.id}__param__checkpoint_mode'),
                label: 'Checkpoint Mode',
                value: (p['checkpoint_mode'] as String?) ?? 'max',
                options: const ['max', 'min'],
                onChanged: (v) => onUpdate({'checkpoint_mode': v}),
              ),
            ],
          ],
        );

      case PipelineDagNodeType.mseCountLoss:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__correct_rate'),
              label: 'Correct Rate',
              value: (p['correct_rate'] as num?)?.toDouble() ?? 0.8,
              onChanged: (v) => onUpdate({'correct_rate': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__incorrect_rate'),
              label: 'Incorrect Rate',
              value: (p['incorrect_rate'] as num?)?.toDouble() ?? 0.2,
              onChanged: (v) => onUpdate({'incorrect_rate': v}),
            ),
          ],
        );

      case PipelineDagNodeType.crossEntropyLoss:
        return _DoubleField(
          key: ValueKey('${node.id}__param__label_smoothing'),
          label: 'Label Smoothing',
          value: (p['label_smoothing'] as num?)?.toDouble() ?? 0.0,
          onChanged: (v) => onUpdate({'label_smoothing': v}),
        );

      case PipelineDagNodeType.adamOptimiser:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__lr'),
              label: 'Learning Rate',
              value: (p['lr'] as num?)?.toDouble() ?? 0.001,
              onChanged: (v) => onUpdate({'lr': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__weight_decay'),
              label: 'Weight Decay',
              value: (p['weight_decay'] as num?)?.toDouble() ?? 0.0,
              onChanged: (v) => onUpdate({'weight_decay': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__beta1'),
              label: 'Beta 1',
              value: (p['beta1'] as num?)?.toDouble() ?? 0.9,
              onChanged: (v) => onUpdate({'beta1': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__beta2'),
              label: 'Beta 2',
              value: (p['beta2'] as num?)?.toDouble() ?? 0.999,
              onChanged: (v) => onUpdate({'beta2': v}),
            ),
          ],
        );

      case PipelineDagNodeType.sgdOptimiser:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__lr'),
              label: 'Learning Rate',
              value: (p['lr'] as num?)?.toDouble() ?? 0.01,
              onChanged: (v) => onUpdate({'lr': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__momentum'),
              label: 'Momentum',
              value: (p['momentum'] as num?)?.toDouble() ?? 0.9,
              onChanged: (v) => onUpdate({'momentum': v}),
            ),
            const SizedBox(height: 12),
            _SwitchField(
              key: ValueKey('${node.id}__param__nesterov'),
              label: 'Nesterov',
              value: (p['nesterov'] as bool?) ?? false,
              onChanged: (v) => onUpdate({'nesterov': v}),
            ),
          ],
        );

      case PipelineDagNodeType.adamwOptimiser:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__lr'),
              label: 'Learning Rate',
              value: (p['lr'] as num?)?.toDouble() ?? 0.001,
              onChanged: (v) => onUpdate({'lr': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__weight_decay'),
              label: 'Weight Decay',
              value: (p['weight_decay'] as num?)?.toDouble() ?? 0.01,
              onChanged: (v) => onUpdate({'weight_decay': v}),
            ),
          ],
        );

      case PipelineDagNodeType.rmspropOptimiser:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__lr'),
              label: 'Learning Rate',
              value: (p['lr'] as num?)?.toDouble() ?? 0.01,
              onChanged: (v) => onUpdate({'lr': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__alpha'),
              label: 'Alpha',
              value: (p['alpha'] as num?)?.toDouble() ?? 0.99,
              onChanged: (v) => onUpdate({'alpha': v}),
            ),
          ],
        );

      case PipelineDagNodeType.stepLR:
        return Column(
          children: [
            _IntField(
              key: ValueKey('${node.id}__param__step_size'),
              label: 'Step Size (epochs)',
              value: (p['step_size'] as int?) ?? 10,
              onChanged: (v) => onUpdate({'step_size': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__gamma'),
              label: 'Gamma',
              value: (p['gamma'] as num?)?.toDouble() ?? 0.1,
              onChanged: (v) => onUpdate({'gamma': v}),
            ),
          ],
        );

      case PipelineDagNodeType.cosineAnnealingLR:
        return Column(
          children: [
            _IntField(
              key: ValueKey('${node.id}__param__T_max'),
              label: 'T_max',
              value: (p['T_max'] as int?) ?? 50,
              onChanged: (v) => onUpdate({'T_max': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__eta_min'),
              label: 'Eta Min',
              value: (p['eta_min'] as num?)?.toDouble() ?? 0.0,
              onChanged: (v) => onUpdate({'eta_min': v}),
            ),
          ],
        );

      case PipelineDagNodeType.exponentialLR:
        return _DoubleField(
          key: ValueKey('${node.id}__param__gamma'),
          label: 'Gamma',
          value: (p['gamma'] as num?)?.toDouble() ?? 0.95,
          onChanged: (v) => onUpdate({'gamma': v}),
        );

      case PipelineDagNodeType.accuracyMetric:
        return _IntField(
          key: ValueKey('${node.id}__param__top_k'),
          label: 'Top-K',
          value: (p['top_k'] as int?) ?? 1,
          onChanged: (v) => onUpdate({'top_k': v}),
        );

      case PipelineDagNodeType.f1Score:
        return _DropdownField<String>(
          key: ValueKey('${node.id}__param__average'),
          label: 'Average',
          value: (p['average'] as String?) ?? 'macro',
          options: const ['macro', 'micro', 'weighted'],
          onChanged: (v) => onUpdate({'average': v}),
        );

      case PipelineDagNodeType.spikeEncoder:
        return Column(
          children: [
            _DropdownField<String>(
              key: ValueKey('${node.id}__param__encoding'),
              label: 'Encoding',
              value: (p['encoding'] as String?) ?? 'rate',
              options: const ['rate', 'temporal', 'population'],
              onChanged: (v) => onUpdate({'encoding': v}),
            ),
            const SizedBox(height: 12),
            _IntField(
              key: ValueKey('${node.id}__param__time_window'),
              label: 'Time Window',
              value: (p['time_window'] as int?) ?? 25,
              onChanged: (v) => onUpdate({'time_window': v}),
            ),
          ],
        );

      case PipelineDagNodeType.lavaSim:
        return Column(
          children: [
            _IntField(
              key: ValueKey('${node.id}__param__num_steps'),
              label: 'Num Steps',
              value: (p['num_steps'] as int?) ?? 25,
              onChanged: (v) => onUpdate({'num_steps': v}),
            ),
            const SizedBox(height: 12),
            _DropdownField<String>(
              key: ValueKey('${node.id}__param__backend'),
              label: 'Backend',
              value: (p['backend'] as String?) ?? 'loihi2sim',
              options: const ['loihi2sim', 'loihi1'],
              onChanged: (v) => onUpdate({'backend': v}),
            ),
          ],
        );

      case PipelineDagNodeType.lavaProcessGraph:
        return _IntField(
          key: ValueKey('${node.id}__param__num_steps'),
          label: 'Num Steps',
          value: (p['num_steps'] as int?) ?? 25,
          onChanged: (v) => onUpdate({'num_steps': v}),
        );

      case PipelineDagNodeType.nirExporter:
        return _StringField(
          key: ValueKey('${node.id}__param__filename'),
          label: 'Filename',
          value: (p['filename'] as String?) ?? 'model.nir',
          onChanged: (v) => onUpdate({'filename': v}),
        );

      case PipelineDagNodeType.akidaExporter:
        return Column(
          children: [
            _StringField(
              key: ValueKey('${node.id}__param__filename'),
              label: 'Filename',
              value: (p['filename'] as String?) ?? 'model.fbz',
              onChanged: (v) => onUpdate({'filename': v}),
            ),
            const SizedBox(height: 12),
            // Akida rejects any other width; a free-text field here would only
            // produce a runtime error deep inside the conversion.
            _DropdownField<int>(
              key: ValueKey('${node.id}__param__weight_bits'),
              label: 'Weight bits',
              value: (p['weight_bits'] as num?)?.toInt() ?? 4,
              options: const [1, 2, 4, 8],
              onChanged: (v) => onUpdate({'weight_bits': v}),
            ),
            const SizedBox(height: 12),
            // Off leaves the .fbz in the workspace with nothing able to pick it
            // up — every deploy control looks for the bundle, not the model.
            _SwitchField(
              key: ValueKey('${node.id}__param__deploy_bundle'),
              label: 'Deploy bundle',
              value: p['deploy_bundle'] != false,
              onChanged: (v) => onUpdate({'deploy_bundle': v}),
            ),
            const SizedBox(height: 12),
            _IntField(
              key: ValueKey('${node.id}__param__eval_samples'),
              label: 'Eval samples',
              value: (p['eval_samples'] as num?)?.toInt() ?? 2000,
              onChanged: (v) => onUpdate({'eval_samples': v}),
            ),
          ],
        );

      case PipelineDagNodeType.pyExporter:
        return _StringField(
          key: ValueKey('${node.id}__param__filename'),
          label: 'Filename',
          value: (p['filename'] as String?) ?? 'model.py',
          onChanged: (v) => onUpdate({'filename': v}),
        );

      case PipelineDagNodeType.l1SpikeReg:
      case PipelineDagNodeType.l2SpikeReg:
        final rawTarget = p['target_layer'] as String?;
        // Only 'spk_out' and '' are ever honored by the backend
        // (_resolve_spike_reg_target) — any other saved value (e.g. a stale
        // free-text node name from before this dropdown existed) already
        // silently falls back to the hidden-layer aggregate, so it's
        // normalized to '' here too rather than passed as an out-of-list
        // dropdown value.
        final target = rawTarget == 'spk_out' ? 'spk_out' : '';
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__weight'),
              label: 'Regularization Weight',
              value: (p['weight'] as num?)?.toDouble() ?? 1e-5,
              onChanged: (v) => onUpdate({'weight': v}),
            ),
            const SizedBox(height: 12),
            _DropdownField<String>(
              key: ValueKey('${node.id}__param__target_layer'),
              label: 'Target Layer',
              value: target,
              options: const ['', 'spk_out'],
              labelBuilder: (v) =>
                  v == 'spk_out' ? 'Output layer' : 'All hidden layers',
              onChanged: (v) => onUpdate({'target_layer': v}),
            ),
          ],
        );

      case PipelineDagNodeType.surrogateBackward:
        return Column(
          children: [
            _DropdownField<String>(
              key: ValueKey('${node.id}__param__function'),
              label: 'Function',
              value: (p['function'] as String?) ?? 'fast_sigmoid',
              options: const [
                'fast_sigmoid',
                'sigmoid',
                'atan',
                'straight_through_estimator',
              ],
              onChanged: (v) => onUpdate({'function': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__slope'),
              label: 'Slope',
              value: (p['slope'] as num?)?.toDouble() ?? 25.0,
              onChanged: (v) => onUpdate({'slope': v}),
            ),
          ],
        );

      case PipelineDagNodeType.gradientClip:
        return _DoubleField(
          key: ValueKey('${node.id}__param__max_norm'),
          label: 'Max Norm',
          value: (p['max_norm'] as num?)?.toDouble() ?? 1.0,
          onChanged: (v) => onUpdate({'max_norm': v}),
        );

      case PipelineDagNodeType.weightClip:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__min_weight'),
              label: 'Min Weight',
              value: (p['min_weight'] as num?)?.toDouble() ?? -1.0,
              onChanged: (v) => onUpdate({'min_weight': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__max_weight'),
              label: 'Max Weight',
              value: (p['max_weight'] as num?)?.toDouble() ?? 1.0,
              onChanged: (v) => onUpdate({'max_weight': v}),
            ),
          ],
        );

      case PipelineDagNodeType.reduceLROnPlateau:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__factor'),
              label: 'Factor',
              value: (p['factor'] as num?)?.toDouble() ?? 0.1,
              onChanged: (v) => onUpdate({'factor': v}),
            ),
            const SizedBox(height: 12),
            _IntField(
              key: ValueKey('${node.id}__param__patience'),
              label: 'Patience (epochs)',
              value: (p['patience'] as int?) ?? 10,
              onChanged: (v) => onUpdate({'patience': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__min_lr'),
              label: 'Min LR',
              value: (p['min_lr'] as num?)?.toDouble() ?? 0.0,
              onChanged: (v) => onUpdate({'min_lr': v}),
            ),
          ],
        );

      case PipelineDagNodeType.earlyStopping:
        return Column(
          children: [
            _IntField(
              key: ValueKey('${node.id}__param__patience'),
              label: 'Patience (epochs)',
              value: (p['patience'] as int?) ?? 10,
              onChanged: (v) => onUpdate({'patience': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__min_delta'),
              label: 'Min Delta',
              value: (p['min_delta'] as num?)?.toDouble() ?? 0.0,
              onChanged: (v) => onUpdate({'min_delta': v}),
            ),
          ],
        );

      case PipelineDagNodeType.latencyMetric:
        return _IntField(
          key: ValueKey('${node.id}__param__default_latency'),
          label: 'Default Latency (no-spike sentinel)',
          value: (p['default_latency'] as int?) ?? -1,
          onChanged: (v) => onUpdate({'default_latency': v}),
        );

      case PipelineDagNodeType.lbiOptimizer:
        return Column(
          children: [
            _DoubleField(
              key: ValueKey('${node.id}__param__lr'),
              label: 'Learning Rate',
              value: (p['lr'] as num?)?.toDouble() ?? 0.001,
              onChanged: (v) => onUpdate({'lr': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__lambda_reg'),
              label: 'Lambda (Regularization)',
              value: (p['lambda_reg'] as num?)?.toDouble() ?? 0.01,
              onChanged: (v) => onUpdate({'lambda_reg': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__kappa'),
              label: 'Kappa',
              value: (p['kappa'] as num?)?.toDouble() ?? 10.0,
              onChanged: (v) => onUpdate({'kappa': v}),
            ),
          ],
        );

      case PipelineDagNodeType.customGradientStep:
        return Column(
          children: [
            _StringField(
              key: ValueKey('${node.id}__param__expression'),
              label: 'Expression',
              value: (p['expression'] as String?) ?? '',
              onChanged: (v) => onUpdate({'expression': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__clip_value'),
              label: 'Clip Value',
              value: (p['clip_value'] as num?)?.toDouble() ?? 0.0,
              onChanged: (v) => onUpdate({'clip_value': v}),
            ),
          ],
        );

      case PipelineDagNodeType.spikeDomainFilter:
        return Column(
          children: [
            _DropdownField<String>(
              key: ValueKey('${node.id}__param__filter_type'),
              label: 'Filter Type',
              value: (p['filter_type'] as String?) ?? 'threshold',
              options: const ['threshold', 'moving_average', 'refractory'],
              onChanged: (v) => onUpdate({'filter_type': v}),
            ),
            const SizedBox(height: 12),
            _IntField(
              key: ValueKey('${node.id}__param__window'),
              label: 'Window',
              value: (p['window'] as int?) ?? 5,
              onChanged: (v) => onUpdate({'window': v}),
            ),
            const SizedBox(height: 12),
            _DoubleField(
              key: ValueKey('${node.id}__param__threshold'),
              label: 'Threshold',
              value: (p['threshold'] as num?)?.toDouble() ?? 0.5,
              onChanged: (v) => onUpdate({'threshold': v}),
            ),
          ],
        );

      case PipelineDagNodeType.forwardPass:
        // Read-only, phase-derived: a node's phase membership
        // (`state.pipelinePhases.eval.nodes` vs `.train.nodes`) already
        // unambiguously determines eval-mode. An editable per-node boolean
        // here would just be a second, desyncable copy of the same fact.
        return LabeledParameterRow(
          label: 'Eval Mode',
          child: Text(
            phase == PipelinePhaseId.eval
                ? 'Confirmed (eval phase)'
                : 'Off (train phase)',
            style: const TextStyle(fontSize: 13),
          ),
        );

      default:
        return Text(
          'No configurable parameters.',
          style: Theme.of(context).textTheme.bodySmall,
        );
    }
  }
}

// ── DataLoader fields ─────────────────────────────────────────────────────────

class _DataLoaderFields extends ConsumerWidget {
  const _DataLoaderFields({
    required this.node,
    required this.phase,
    required this.onUpdate,
  });

  final PipelineDagNode node;
  final PipelinePhaseId phase;
  final void Function(Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataset = ref.watch(
      workspaceProvider.select((s) => s.selectedDataset),
    );
    final p = {...node.type.defaultParameters, ...node.parameters};
    final fmt = (p['format'] as String?) ?? 'auto';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (dataset != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons
                      .dataset_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                  size: 14,
                  color: Color(0xFF1E88E5),
                ),
                const SizedBox(width: 6),
                Text(
                  dataset.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E88E5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Text(
                  'from setup',
                  style: TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _DropdownField<String>(
          key: ValueKey('${node.id}__param__format'),
          label: 'Format',
          value: fmt,
          options: const [
            'auto',
            'tonic_nmnist',
            'tonic_shd',
            'tonic_ntidigits',
            'npy',
            'pt',
            'hdf5',
          ],
          onChanged: (v) => onUpdate({'format': v}),
        ),
        if (fmt.startsWith('tonic_')) ...[
          const SizedBox(height: 12),
          _IntField(
            key: ValueKey('${node.id}__param__time_window_ms'),
            label: 'Time Window (ms)',
            value: (p['time_window_ms'] as int?) ?? 1,
            onChanged: (v) => onUpdate({'time_window_ms': v}),
          ),
          const SizedBox(height: 12),
          _SwitchField(
            key: ValueKey('${node.id}__param__auto_download'),
            label: 'Auto-download dataset',
            value: (p['auto_download'] as bool?) ?? true,
            onChanged: (v) => onUpdate({'auto_download': v}),
          ),
        ],
        if (fmt == 'pt' || fmt == 'npy') ...[
          const SizedBox(height: 12),
          DatasetPathField(
            key: ValueKey('${node.id}__param__dataset_path'),
            value: (p['dataset_path'] as String?) ?? '',
            format: fmt,
            pathScope:
                (p[kDatasetPathScopeKey] as String?) ?? kServerDatasetPathScope,
            fileName: (p[kDatasetFileNameKey] as String?) ?? '',
            onChanged: (v) => onUpdate({
              'dataset_path': v,
              kDatasetPathScopeKey: kServerDatasetPathScope,
              kDatasetFileNameKey: '',
            }),
            onFileSelected: (file) => onUpdate({
              'dataset_path': file.path!,
              kDatasetPathScopeKey: kClientDatasetPathScope,
              kDatasetFileNameKey: file.name,
            }),
          ),
        ],
        const SizedBox(height: 12),
        _IntField(
          key: ValueKey('${node.id}__param__batch_size'),
          label: 'Batch Size',
          value: (p['batch_size'] as int?) ?? 32,
          onChanged: (v) => onUpdate({'batch_size': v}),
        ),
        const SizedBox(height: 12),
        _SwitchField(
          key: ValueKey('${node.id}__param__shuffle'),
          label: 'Shuffle',
          value: (p['shuffle'] as bool?) ?? true,
          onChanged: (v) => onUpdate({'shuffle': v}),
        ),
        if (node.type == PipelineDagNodeType.testLoader ||
            phase == PipelinePhaseId.eval) ...[
          const SizedBox(height: 12),
          _SwitchField(
            key: ValueKey('${node.id}__param__load_best_checkpoint'),
            label: 'Load Best Checkpoint',
            value: (p['load_best_checkpoint'] as bool?) ?? true,
            onChanged: (v) => onUpdate({'load_best_checkpoint': v}),
          ),
          const SizedBox(height: 12),
          const _TrainedOnIndicator(),
        ],
      ],
    );
  }
}

// ── TestLoader "Trained on" indicator ─────────────────────────────────────────

/// Read-only indicator showing which training run's checkpoint would be
/// loaded by `load_best_checkpoint`. Sourced from [trainingJobIdsProvider],
/// the only existing in-app state that tracks a training job per platform
/// for the current session (populated in `run_step.dart` when a notebook
/// run starts). There is no persisted "last completed training job" concept
/// today — this shows the current run's job ids (if any) rather than
/// inventing new state or asking the user to type an id.
class _TrainedOnIndicator extends ConsumerWidget {
  const _TrainedOnIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobRefs = ref.watch(trainingJobIdsProvider);
    final label = jobRefs.isEmpty
        ? 'Not yet trained'
        : jobRefs.entries.map((e) => '${e.key}: ${e.value.jobId}').join(', ');
    return LabeledParameterRow(
      label: 'Last submitted run',
      child: Text(
        label,
        style: const TextStyle(fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── SpikeGenerator fields ─────────────────────────────────────────────────────

class _SpikeGeneratorFields extends ConsumerWidget {
  const _SpikeGeneratorFields({required this.node, required this.onUpdate});

  final PipelineDagNode node;
  final void Function(Map<String, dynamic>) onUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = {...node.type.defaultParameters, ...node.parameters};
    final pattern = (p['pattern'] as String?) ?? 'isi_regular';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IntField(
          key: ValueKey('${node.id}__param__n_neurons'),
          label: 'Neurons',
          value: (p['n_neurons'] as int?) ?? 1,
          onChanged: (v) => onUpdate({'n_neurons': v}),
        ),
        const SizedBox(height: 12),
        _IntField(
          key: ValueKey('${node.id}__param__n_timesteps'),
          label: 'Timesteps',
          value: (p['n_timesteps'] as int?) ?? 100,
          onChanged: (v) => onUpdate({'n_timesteps': v}),
        ),
        const SizedBox(height: 12),
        _DropdownField<String>(
          key: ValueKey('${node.id}__param__pattern'),
          label: 'Pattern',
          value: pattern,
          options: const ['isi_regular', 'poisson', 'constant_rate'],
          onChanged: (v) => onUpdate({'pattern': v}),
        ),
        if (pattern == 'isi_regular') ...[
          const SizedBox(height: 12),
          _IntField(
            key: ValueKey('${node.id}__param__isi_period'),
            label: 'ISI Period (steps)',
            value: (p['isi_period'] as int?) ?? 10,
            onChanged: (v) => onUpdate({'isi_period': v}),
          ),
        ],
        if (pattern == 'poisson' || pattern == 'constant_rate') ...[
          const SizedBox(height: 12),
          _DoubleField(
            key: ValueKey('${node.id}__param__rate_hz'),
            label: 'Rate (Hz)',
            value: (p['rate_hz'] as num?)?.toDouble() ?? 10.0,
            onChanged: (v) => onUpdate({'rate_hz': v}),
          ),
        ],
        const SizedBox(height: 12),
        _IntField(
          key: ValueKey('${node.id}__param__seed'),
          label: 'Seed',
          value: (p['seed'] as int?) ?? 42,
          onChanged: (v) => onUpdate({'seed': v}),
        ),
      ],
    );
  }
}

// ── Helper field widgets ──────────────────────────────────────────────────────

class _IntField extends StatelessWidget {
  const _IntField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final int value;
  final void Function(int) onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return CanvasParameterTextField(
      label: label,
      value: value.toString(),
      keyboardType: TextInputType.number,
      hintText: hint,
      onCommit: (s) {
        final v = int.tryParse(s);
        if (v != null) onChanged(v);
      },
    );
  }
}

class _DoubleField extends StatelessWidget {
  const _DoubleField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    return CanvasParameterTextField(
      label: label,
      value: value.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onCommit: (s) {
        final v = double.tryParse(s);
        if (v != null) onChanged(v);
      },
    );
  }
}

class _StringField extends StatelessWidget {
  const _StringField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return CanvasParameterTextField(
      label: label,
      value: value,
      onCommit: onChanged,
    );
  }
}

/// Dataset Path field with a Browse button alongside the manual text entry.
///
/// The backend consumes `dataset_path` as a raw filesystem path on whichever
/// host runs the notebook — which is not necessarily the client machine.
/// Browse therefore stores the client-local path and notebook generation
/// uploads its current bytes immediately before sending the generation
/// request. On web the Browse button is hidden and manual paths retain their
/// legacy server-path meaning.
class DatasetPathField extends ConsumerStatefulWidget {
  const DatasetPathField({
    super.key,
    required this.value,
    required this.format,
    this.pathScope = kServerDatasetPathScope,
    this.fileName = '',
    required this.onChanged,
    required this.onFileSelected,
    this.gateway,
    this.localPathExists,
  });

  final String value;
  final String format;
  final String pathScope;
  final String fileName;
  final void Function(String) onChanged;
  final void Function(PickedFileData) onFileSelected;
  final NativeFileDialogGateway? gateway;
  final LocalDatasetExists? localPathExists;

  @override
  ConsumerState<DatasetPathField> createState() => _DatasetPathFieldState();
}

class _DatasetPathFieldState extends ConsumerState<DatasetPathField> {
  // `null` = not checked yet (or path empty); `true`/`false` = last known
  // reachability of `widget.value`, from a fire-and-forget backend probe.
  bool? _pathMissing;

  @override
  void initState() {
    super.initState();
    _checkReachability(widget.value);
  }

  @override
  void didUpdateWidget(DatasetPathField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.pathScope != widget.pathScope) {
      _checkReachability(widget.value);
    }
  }

  void _checkReachability(String path) {
    if (path.trim().isEmpty) {
      setState(() => _pathMissing = null);
      return;
    }
    final check = widget.pathScope == kClientDatasetPathScope
        ? (widget.localPathExists ?? localDatasetFileExists)(path)
        : ref.read(apiClientProvider).checkDatasetPathExists(path);
    unawaited(
      check
          .then((exists) {
            if (!mounted || path != widget.value) return;
            setState(() => _pathMissing = !exists);
          })
          .catchError((_) {
            // Reachability is a best-effort hint — a failed check (e.g. the
            // backend doesn't support this endpoint yet) must not block or
            // misreport the field, so it just stays unresolved.
            if (!mounted || path != widget.value) return;
            setState(() => _pathMissing = null);
          }),
    );
  }

  Future<void> _browse(BuildContext context, WidgetRef ref) async {
    try {
      final files =
          await (widget.gateway ?? createDefaultNativeFileDialogGateway())
              .pickFiles(
                allowMultiple: false,
                allowedExtensions: [widget.format],
                loadBytes: false,
              );
      final file = files?.firstOrNull;
      if (file == null) return;
      if (file.path == null || file.path!.trim().isEmpty) {
        throw StateError(
          'The selected file did not provide a local path. '
          'Choose it from the desktop app and try again.',
        );
      }
      widget.onFileSelected(file);
    } catch (e) {
      if (!context.mounted) return;
      debugPrint('Dataset file selection failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not select the dataset file. '
            'Check its permissions and try Browse again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientPath = widget.pathScope == kClientDatasetPathScope;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_pathMissing == true) ...[
              Tooltip(
                message: clientPath
                    ? 'Local file not found — Browse to select it again.'
                    : 'File not found on the server — Browse to re-select it '
                          'from this machine.',
                child: Icon(
                  ZetaIcons.warning_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: CanvasParameterTextField(
                label: 'Dataset Path',
                value: widget.value,
                onCommit: widget.onChanged,
                hintText: 'e.g. data/ds_train.pt',
                suffix: kIsWeb
                    ? null
                    : IconButton(
                        icon: Icon(
                          ZetaIcons.folder_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: 'Browse for dataset file',
                        onPressed: () => _browse(context, ref),
                      ),
              ),
            ),
          ],
        ),
        if (clientPath && widget.value.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ZetaIcons.cloud_upload,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                widget.fileName.isEmpty
                    ? 'Uploads on Generate'
                    : '${widget.fileName} uploads on Generate',
                style: Zeta.of(context).textStyles.bodyXSmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SwitchField extends StatelessWidget {
  const _SwitchField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              color: NmtkNeurocnlTokens.textSecondary,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelBuilder,
  });

  final String label;
  final T value;
  final List<T> options;
  final void Function(T) onChanged;
  final String Function(T)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(
              color: NmtkNeurocnlTokens.textSecondary,
              fontSize: 11,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<T>(
            initialValue: value,
            // Without this the dropdown's internal Row sizes to its widest
            // item and overflows the cell the label leaves it (125px in a
            // two-column grid), which surfaces as "RenderFlex overflowed by
            // N pixels on the right" rather than as a clipped label.
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: options
                .map(
                  (o) => DropdownMenuItem<T>(
                    value: o,
                    child: Text(
                      labelBuilder != null ? labelBuilder!(o) : o.toString(),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}
