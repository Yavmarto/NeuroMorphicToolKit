import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_parameter_text_field.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deployment_feature.dart';

class AkidaExecutionControls extends ConsumerStatefulWidget {
  const AkidaExecutionControls({
    super.key,
    required this.provider,
    required this.isCompact,
  });

  final StudioAkidaDeployState provider;
  final bool isCompact;

  @override
  ConsumerState<AkidaExecutionControls> createState() =>
      _AkidaExecutionControlsState();
}

class _AkidaExecutionControlsState
    extends ConsumerState<AkidaExecutionControls> {
  /// Set when a typed index was outside the bundled evaluation set. The old
  /// field rewrote the value silently, so a benchmark could run on a different
  /// sample than the one the user asked for without saying so.
  String? _sampleIndexNote;

  void _commitSampleIndex(String value) {
    final job = widget.provider.deploymentJob;
    final notifier = ref.read(studioAkidaDeployProvider.notifier);
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      setState(() => _sampleIndexNote = 'Enter a whole number.');
      return;
    }
    final total = job?.totalSamples;
    final maximum = total != null && total > 0 ? total - 1 : null;
    if (parsed < 0) {
      setState(
        () => _sampleIndexNote = 'Using 0 — the index cannot be negative.',
      );
      notifier.setSampleIndex(0);
      return;
    }
    if (maximum != null && parsed > maximum) {
      setState(
        () => _sampleIndexNote =
            'Using $maximum — this model was bundled with $total samples.',
      );
      notifier.setSampleIndex(maximum);
      return;
    }
    if (_sampleIndexNote != null) setState(() => _sampleIndexNote = null);
    notifier.setSampleIndex(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final notifier = ref.read(studioAkidaDeployProvider.notifier);
    final job = provider.deploymentJob;
    final colors = Zeta.of(context).colors;
    final textStyles = Zeta.of(context).textStyles;
    if (job == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusLg,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(widget.isCompact ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ZetaIcons.memory, size: 28, color: colors.mainSubtle),
              SizedBox(height: widget.isCompact ? 8 : 12),
              Text(
                widget.isCompact
                    ? 'Deploy a trained bundle to unlock inference and benchmarks.'
                    : 'Deploy a trained bundle to enable hardware inference and '
                          'benchmark reporting.',
                textAlign: TextAlign.center,
                style: textStyles.bodyMedium.copyWith(color: colors.mainSubtle),
              ),
            ],
          ),
        ),
      );
    }

    final canRunSample =
        job.modelId != null && job.hardwareVerified && !provider.isBusy;
    final canBenchmark = job.modelId != null && !provider.isBusy;
    final maximumIndex = job.totalSamples == null || job.totalSamples! <= 0
        ? null
        : job.totalSamples! - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Akida inference',
                style: textStyles.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            akidaProvenanceBadge(job.hardwareVerified),
          ],
        ),
        const SizedBox(height: 16),
        // The index and the action it feeds read as one control, at a width
        // that matches what it holds — four digits, not a paragraph.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    maximumIndex == null
                        ? 'Sample index'
                        : 'Sample index (0–$maximumIndex)',
                    style: textStyles.labelSmall.copyWith(
                      color: colors.mainSubtle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  CanvasParameterTextField(
                    key: const Key('akida-model-sample-index'),
                    label: 'Sample index',
                    showLabel: false,
                    value: '${provider.sampleIndex}',
                    onCommit: _commitSampleIndex,
                    onSubmitted: canRunSample ? notifier.runModelSample : null,
                    keyboardType: TextInputType.number,
                    placeholder: '0',
                    errorText: _sampleIndexNote,
                    enabled: !provider.isBusy,
                  ),
                ],
              ),
            ),
            NmtkPrimaryButton(
              key: const Key('akida-run-model-sample'),
              onPressed: canRunSample ? notifier.runModelSample : null,
              icon: ZetaIcons.play,
              label: 'Run sample',
            ),
            NmtkOutlinedButton(
              key: const Key('akida-run-benchmark'),
              onPressed: canBenchmark ? notifier.runBenchmark : null,
              icon: ZetaIcons.analytics,
              label: 'Run benchmark',
            ),
          ],
        ),
        if (!job.hardwareVerified) ...[
          const SizedBox(height: 8),
          Text(
            'Sample inference requires physical hardware. Benchmark data is '
            'still valid when the runtime target is the Akida simulator.',
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          ),
        ],
        // Progress for a run belongs under the button that started it. Deploy
        // progress stays in the setup pane, next to its own button.
        if (provider.isRunning) ...[
          const SizedBox(height: 16),
          AkidaRunActivity(provider: provider),
        ] else if (provider.errorMessage != null) ...[
          const SizedBox(height: 16),
          StudioStatusLine(
            message: provider.errorMessage!,
            tone: NmtkTone.danger,
          ),
        ] else if (provider.latestResultKind != null) ...[
          const SizedBox(height: 16),
          AkidaRunComplete(kind: provider.latestResultKind!),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            'Charts and per-class accuracy appear in the Review step once a '
            'run finishes.',
            style: textStyles.bodySmall.copyWith(color: colors.mainSubtle),
          ),
        ],
      ],
    );
  }
}
