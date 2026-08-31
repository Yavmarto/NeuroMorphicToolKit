import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/sweep.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sweep_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/backend_support_banner.dart';

class SweepScreen extends ConsumerStatefulWidget {
  const SweepScreen({super.key});

  @override
  ConsumerState<SweepScreen> createState() => _SweepScreenState();
}

class _SweepScreenState extends ConsumerState<SweepScreen> {
  final _formKey = GlobalKey<FormState>();
  String _parameterPath = '';
  double _start = 0.0;
  double _end = 1.0;
  int _steps = 5;

  @override
  Widget build(BuildContext context) {
    final sweepState = ref.watch(sweepProvider);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            SizedBox(
              width: 320,
              child: Card(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Sweep Configuration',
                              style: Zeta.of(context).textStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Reset configuration',
                            icon: const Icon(ZetaIcons.refresh),
                            onPressed: () =>
                                ref.read(sweepProvider.notifier).reset(),
                          ),
                        ],
                      ),
                      if (sweepState.backendSupport != null) ...[
                        const SizedBox(height: 16),
                        NmtkBackendSupportBanner(
                          verdict: sweepState.backendSupport!.verdict,
                          backend: sweepState.backendSupport!.backend,
                          warnings: sweepState.backendSupport!.warnings,
                          title: 'Sweep Backend',
                          compact: true,
                        ),
                      ],
                      const SizedBox(height: 16),
                      NmtkTextInput(
                        key: const Key('sweep-parameter-path-field'),
                        label: 'Parameter Path',
                        placeholder: 'e.g., nodes.N1.tau',
                        initialValue: _parameterPath,
                        onChange: (value) => _parameterPath = value ?? '',
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      NmtkTextInput(
                        key: const Key('sweep-start-field'),
                        label: 'Start Value',
                        initialValue: _start.toString(),
                        keyboardType: TextInputType.number,
                        onChange: (value) =>
                            _start = double.tryParse(value ?? '') ?? 0.0,
                        validator: (v) => double.tryParse(v ?? '') == null
                            ? 'Invalid number'
                            : null,
                      ),
                      NmtkTextInput(
                        key: const Key('sweep-end-field'),
                        label: 'End Value',
                        initialValue: _end.toString(),
                        keyboardType: TextInputType.number,
                        onChange: (value) =>
                            _end = double.tryParse(value ?? '') ?? 1.0,
                        validator: (v) => double.tryParse(v ?? '') == null
                            ? 'Invalid number'
                            : null,
                      ),
                      NmtkTextInput(
                        key: const Key('sweep-steps-field'),
                        label: 'Steps (max 20)',
                        initialValue: _steps.toString(),
                        keyboardType: TextInputType.number,
                        onChange: (value) =>
                            _steps = int.tryParse(value ?? '') ?? 5,
                        validator: (v) {
                          final val = int.tryParse(v ?? '');
                          if (val == null) {
                            return 'Invalid number';
                          }
                          if (val <= 0 || val > 20) {
                            return 'Must be between 1 and 20';
                          }
                          return null;
                        },
                      ),
                      const Spacer(),
                      ZetaButton(
                        key: const Key('sweep-run-button'),
                        onPressed: sweepState.isLoading
                            ? null
                            : _handleRunSweep,
                        label: sweepState.isLoading ? 'Running…' : 'Run Sweep',
                        leadingIcon: sweepState.isLoading
                            ? null
                            : ZetaIcons.play,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(child: Card(child: _buildResultsView(sweepState))),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsView(SweepState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Text(
          'Error: ${state.error}',
          style: Zeta.of(context).textStyles.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    }
    if (state.results == null) {
      return const Center(
        child: Text('Configure and run a sweep to see results.'),
      );
    }

    final results = state.results!;
    final steps = results.steps ?? const [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Sweep Results for: ${results.parameterPath}',
            key: const Key('sweep-results-title'),
            style: Zeta.of(context).textStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: steps.length,
            itemBuilder: (context, index) {
              final step = steps[index];
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Value: ${step.parameterValue}',
                      style: Zeta.of(context).textStyles.labelMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          step.result.status == 'success' ||
                                  step.result.status == 'completed'
                              ? 'Success: ${step.result.results.length} nodes'
                              : 'Error: ${step.result.error ?? "Unknown"}',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleRunSweep() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();
      final canvasState = ref.read(canvasProvider);
      final request = SweepRequest(
        graph: canvasState.graph,
        parameterPath: _parameterPath,
        start: _start,
        end: _end,
        steps: _steps,
      );
      ref.read(sweepProvider.notifier).runSweep(request);
    }
  }
}
