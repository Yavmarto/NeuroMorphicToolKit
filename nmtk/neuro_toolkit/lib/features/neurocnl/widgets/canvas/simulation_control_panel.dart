import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/validation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/backend_support_banner.dart';

class SimulationControlPanel extends ConsumerWidget {
  const SimulationControlPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final simState = ref.watch(simulationProvider);
    final notifier = ref.read(simulationProvider.notifier);
    final validationState = ref.watch(validationProvider);
    final validation = validationState.asData?.value;
    final previewSupport = validation?.backendSupport;
    final previewUnsupported = previewSupport?.verdict == 'unsupported';
    final isFetching = simState.isFetching;
    final canPlay = simState.hasPreview && !isFetching;
    final isPlaying = simState.isPlayingBack;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Zeta.of(context).colors.surfacePrimary,
        border: Border(
          bottom: BorderSide(color: Zeta.of(context).colors.borderSubtle),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrowLayout = constraints.maxWidth < 700;
          final controls = [
            ZetaButton(
              key: const Key('simulation-run-button'),
              onPressed: isFetching || previewUnsupported
                  ? null
                  : () => notifier.runPreview(),
              label: isFetching ? 'Running…' : 'Run',
              leadingIcon: isFetching ? null : ZetaIcons.play,
            ),
            const SizedBox(width: 8),
            ZetaButton.outline(
              onPressed: canPlay
                  ? () => isPlaying ? notifier.pause() : notifier.play()
                  : null,
              leadingIcon: isPlaying ? ZetaIcons.pause : ZetaIcons.play_circle,
              label: isPlaying ? 'Pause' : 'Resume',
            ),
            const SizedBox(width: 8),
            ZetaButton.outline(
              onPressed: simState.canStep ? notifier.stepForward : null,
              leadingIcon: ZetaIcons.skip_next,
              label: 'Step',
            ),
            const SizedBox(width: 16),
            _StatusText(simState: simState),
            const SizedBox(width: 8),
            for (final speed in const <double>[0.5, 1.0, 2.0, 4.0]) ...[
              ZetaButton.text(
                onPressed: () => notifier.setSpeed(speed),
                label: speed == 0.5 ? '0.5x' : '${speed.toStringAsFixed(0)}x',
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              icon: Icon(
                ZetaIcons.refresh,
                color: Zeta.of(context).colors.mainSubtle,
              ),
              onPressed: notifier.reset,
              tooltip: 'Reset Visual Simulation State',
            ),
          ];

          if (narrowLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: controls),
                ),
                if (previewSupport != null) ...[
                  const SizedBox(height: 8),
                  NmtkBackendSupportBanner(
                    verdict: previewSupport.verdict,
                    backend: previewSupport.backend,
                    warnings: previewSupport.warnings,
                    title: 'Preview',
                    compact: true,
                  ),
                ],
              ],
            );
          }

          return Row(
            children: [
              ...controls,
              if (previewSupport != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: NmtkBackendSupportBanner(
                    verdict: previewSupport.verdict,
                    backend: previewSupport.backend,
                    warnings: previewSupport.warnings,
                    title: 'Preview',
                    compact: true,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  final SimulationState simState;

  const _StatusText({required this.simState});

  @override
  Widget build(BuildContext context) {
    if (simState.status == SimulationStatus.connecting) {
      return Text(
        'Status: Streaming preview...',
        style: Zeta.of(context).textStyles.bodySmall.copyWith(
          color: Zeta.of(context).colors.mainPrimary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    if (simState.status == SimulationStatus.completed) {
      return Text(
        'Status: Completed',
        style: Zeta.of(context).textStyles.bodySmall.copyWith(
          color: Zeta.of(context).colors.mainPrimary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    if (simState.status == SimulationStatus.error) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          'Error: ${simState.error}',
          style: Zeta.of(context).textStyles.bodySmall.copyWith(
            color: Zeta.of(context).colors.mainNegative,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (simState.status == SimulationStatus.running) {
      return Text(
        'Status: Playing preview...',
        style: Zeta.of(context).textStyles.bodySmall.copyWith(
          color: Zeta.of(context).colors.mainPrimary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    if (simState.status == SimulationStatus.paused) {
      return Text(
        'Status: Paused',
        style: Zeta.of(context).textStyles.bodySmall.copyWith(
          color: Zeta.of(context).colors.mainPrimary,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
