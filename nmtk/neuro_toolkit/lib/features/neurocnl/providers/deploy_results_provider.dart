import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_akida_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_lava_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';

/// Simulator backends the Deploy step can run. Kept local to this file because
/// it is only used to sweep the `simulatorRunProvider` family for results.
const List<String> kSimulatorDeployBackends = <String>[
  'lava_sim',
  'snntorch_sim',
  'sc_neurocore_sim',
];

/// True when the currently selected deploy target has produced a result the
/// Review step can show.
final deployTargetHasResultProvider = Provider.family<bool, String>((
  ref,
  target,
) {
  if (kSimulatorDeployBackends.contains(target)) {
    return ref.watch(simulatorRunProvider(target)) is SimulatorRunSuccess;
  }
  return switch (target) {
    'akida' => ref.watch(
      studioAkidaDeployProvider.select(
        (state) =>
            state.sampleResult != null ||
            state.benchmarkResult != null ||
            state.visualizationResult != null,
      ),
    ),
    'lava' => ref.watch(
      studioLavaDeployProvider.select((state) => state.runResult != null),
    ),
    // A completed exportability check is not a result: it used to be, back when
    // PYNQ could only ever produce a verdict, which made Review claim a
    // hardware result for a network that had never left the backend. Now the
    // board can actually run, so a result means the board answered.
    'pynq' => ref.watch(
      studioPynqDeployProvider.select(
        (state) => state.runResult != null || state.verifyResult != null,
      ),
    ),
    // Codegen-preview and FPGA targets are verdict/preview only — they never
    // produce a run result, so Review has nothing to show for them.
    _ => false,
  };
});

/// True when *any* deploy target has a result. Gates the Review step: deploy
/// results live in memory only, so this goes back to false after a restart.
final deployResultsAvailableProvider = Provider<bool>((ref) {
  for (final target in <String>[
    'akida',
    'lava',
    'pynq',
    ...kSimulatorDeployBackends,
  ]) {
    if (ref.watch(deployTargetHasResultProvider(target))) return true;
  }
  return false;
});

/// The targets that currently hold a result, so Review can point at a target
/// other than the selected one instead of showing a bare empty state.
final deployTargetsWithResultsProvider = Provider<List<String>>((ref) {
  return <String>[
    for (final target in <String>[
      'akida',
      'lava',
      'pynq',
      ...kSimulatorDeployBackends,
    ])
      if (ref.watch(deployTargetHasResultProvider(target))) target,
  ];
});
