import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/labeled_parameter_grid.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';

class SharedSimulatorSettingsCard extends ConsumerWidget {
  const SharedSimulatorSettingsCard({super.key, required this.backends});

  /// Backends this card applies to — the simulator ids Setup has selected,
  /// not necessarily all of [kSimulatorDeployBackends].
  final List<String> backends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(simulatorSharedSettingsProvider);
    final overridden = ref.watch(simulatorOverriddenBackendsProvider);
    final sharedCount = backends.where((b) => !overridden.contains(b)).length;

    // Pushes the shared value out to every backend that still tracks it.
    // Read fresh from the provider rather than trusting the closed-over
    // `shared` — each of the four setters below mutates it before this runs.
    void cascade() {
      final next = ref.read(simulatorSharedSettingsProvider);
      for (final backend in backends) {
        if (!overridden.contains(backend)) {
          ref.read(simulatorSettingsProvider(backend).notifier).setAll(next);
        }
      }
    }

    return NmtkSectionCard(
      title: 'Shared settings',
      subtitle: sharedCount == backends.length
          ? 'Applied to all ${backends.length} targets below'
          : 'Applied to $sharedCount of ${backends.length} '
                'targets — the rest have their own settings',
      child: LabeledParameterGrid(
        minCellWidth: 130,
        mainAxisSpacing: 4,
        mainAxisExtent: 48,
        children: [
          LabeledIntField(
            label: 'Timesteps',
            value: shared.timesteps,
            min: 1,
            max: 10000,
            labelWidth: 72,
            onChanged: (v) {
              ref
                  .read(simulatorSharedSettingsProvider.notifier)
                  .setTimesteps(v);
              cascade();
            },
          ),
          LabeledIntField(
            label: 'Seed',
            value: shared.seed,
            min: 0,
            max: 2147483647,
            labelWidth: 72,
            onChanged: (v) {
              ref.read(simulatorSharedSettingsProvider.notifier).setSeed(v);
              cascade();
            },
          ),
          LabeledFloatField(
            label: 'Firing Rate',
            value: shared.firingRate,
            min: 0.01,
            max: 1.0,
            decimals: 2,
            labelWidth: 72,
            onChanged: (v) {
              ref
                  .read(simulatorSharedSettingsProvider.notifier)
                  .setFiringRate(v);
              cascade();
            },
          ),
          LabeledFloatField(
            label: 'Raster time scale (ms/step)',
            value: shared.dtMs,
            min: 0.1,
            max: 100.0,
            decimals: 1,
            labelWidth: 72,
            onChanged: (v) {
              ref.read(simulatorSharedSettingsProvider.notifier).setDtMs(v);
              cascade();
            },
          ),
        ],
      ),
    );
  }
}
