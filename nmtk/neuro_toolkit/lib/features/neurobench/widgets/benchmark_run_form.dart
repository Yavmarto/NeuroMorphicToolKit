import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/providers/execution_provider.dart';

class BenchmarkRunForm extends ConsumerStatefulWidget {
  const BenchmarkRunForm({super.key, required this.benchmark});

  final BenchmarkDefinition benchmark;

  @override
  ConsumerState<BenchmarkRunForm> createState() => _BenchmarkRunFormState();
}

class _BenchmarkRunFormState extends ConsumerState<BenchmarkRunForm> {
  late final TextEditingController _networkController;
  late final TextEditingController _seedController;
  late final TextEditingController _paramsController;

  static const _targetOptions = <_TargetOptionData>[
    _TargetOptionData(
      value: 'simulation',
      label: 'Local Simulation',
      subtitle: 'CNL pipeline — no external backend required',
    ),
    _TargetOptionData(
      value: 'neurosim',
      label: 'Neurosim',
      subtitle: 'Remote simulation via CNL Studio backend',
    ),
    _TargetOptionData(
      value: 'neurochip',
      label: 'NeuroChip',
      subtitle: 'NeuroChip hardware deployment target',
    ),
    _TargetOptionData(
      value: 'spinnaker2',
      label: 'SpiNNaker2',
      subtitle: 'SpiNNaker2 neuromorphic hardware board',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final draft = ref.read(benchmarkExecutionProvider).draft;
    _networkController = TextEditingController(text: draft.networkPath);
    _seedController = TextEditingController(text: draft.seedText);
    _paramsController = TextEditingController(text: draft.paramsText);
  }

  @override
  void dispose() {
    _networkController.dispose();
    _seedController.dispose();
    _paramsController.dispose();
    super.dispose();
  }

  void _syncControllers(BenchmarkRunDraft draft) {
    if (_networkController.text != draft.networkPath) {
      _networkController.value = _networkController.value.copyWith(
        text: draft.networkPath,
        selection: TextSelection.collapsed(offset: draft.networkPath.length),
      );
    }
    if (_seedController.text != draft.seedText) {
      _seedController.value = _seedController.value.copyWith(
        text: draft.seedText,
        selection: TextSelection.collapsed(offset: draft.seedText.length),
      );
    }
    if (_paramsController.text != draft.paramsText) {
      _paramsController.value = _paramsController.value.copyWith(
        text: draft.paramsText,
        selection: TextSelection.collapsed(offset: draft.paramsText.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final executionState = ref.watch(benchmarkExecutionProvider);
    final controller = ref.read(benchmarkExecutionProvider.notifier);
    final draft = executionState.draft;
    final benchmark = widget.benchmark;

    _syncControllers(draft);

    return NmtkSection(
      title: 'Configure & Run',
      subtitle:
          'Set network path, target, seed, and params, then queue ${benchmark.name}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Primary: ${benchmark.scoring.primaryMetric}')),
              Chip(label: Text(benchmark.inputSpec.type)),
            ],
          ),
          const SizedBox(height: 16),
          NmtkTextInput(
            controller: _networkController,
            label: 'Network path',
            hintText: 'examples/reaction_latency.json',
            onChange: (v) => controller.updateNetworkPath(v ?? ''),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: draft.target,
            decoration: const InputDecoration(labelText: 'Target'),
            itemHeight: 72,
            selectedItemBuilder: (context) {
              return _targetOptions
                  .map(
                    (option) => Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false);
            },
            items: _targetOptions
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.value,
                    child: _TargetOption(
                      label: option.label,
                      subtitle: option.subtitle,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                controller.updateTarget(value);
              }
            },
          ),
          const SizedBox(height: 12),
          NmtkTextInput(
            controller: _seedController,
            label: 'Seed',
            hintText: 'Leave blank for service default',
            keyboardType: TextInputType.number,
            onChange: (v) => controller.updateSeedText(v ?? ''),
          ),
          const SizedBox(height: 12),
          NmtkTextInput(
            controller: _paramsController,
            label: 'Params JSON',
            onChange: (v) => controller.updateParamsText(v ?? ''),
          ),
          if (executionState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              executionState.errorMessage!,
              style: Zeta.of(context).textStyles.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
          const SizedBox(height: 20),
          ZetaButton.primary(
            onPressed: executionState.submitting ||
                    executionState.hasActiveBackgroundJob
                ? null
                : () => controller.submitRun(benchmark),
            leadingIcon: ZetaIcons.play,
            label:
                executionState.submitting ? 'Queueing run…' : 'Run Benchmark',
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: executionState.hasActiveBackgroundJob ? 1.0 : 0.38,
            child: ZetaButton.outline(
              onPressed: executionState.hasActiveBackgroundJob &&
                      !executionState.cancelling
                  ? () => controller.cancelActiveJob()
                  : null,
              label: executionState.cancelling
                  ? 'Cancelling job'
                  : 'Cancel active job',
              leadingIcon:
                  executionState.cancelling ? null : ZetaIcons.stop_circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetOptionData {
  const _TargetOptionData({
    required this.value,
    required this.label,
    required this.subtitle,
  });

  final String value;
  final String label;
  final String subtitle;
}

class _TargetOption extends StatelessWidget {
  const _TargetOption({required this.label, required this.subtitle});

  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
