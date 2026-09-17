import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/simulator_preflight_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulator_panel.dart';

class RunAllSimulatorsButton extends ConsumerWidget {
  const RunAllSimulatorsButton({super.key, required this.backends});

  /// Backends to run — the simulator ids Setup has selected, not necessarily
  /// all of [kSimulatorDeployBackends].
  final List<String> backends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceName = ref.watch(
      workspaceProvider.select((s) => s.workspaceName),
    );
    final gate = SimulatorRunGate.resolve(
      preflight: ref.watch(simulatorPreflightProvider),
      trainedNir: ref.watch(simulatorTrainedNirProvider(workspaceName)),
    );
    final anyRunning = backends.any(
      (b) => ref.watch(simulatorRunProvider(b)) is SimulatorRunLoading,
    );

    return Tooltip(
      message: gate.message,
      child: ZetaButton(
        key: const Key('run-all-simulators-button'),
        onPressed: gate.blocked || anyRunning
            ? null
            : () {
                for (final backend in backends) {
                  runSimulatorBackend(ref, backend);
                }
              },
        leadingIcon: anyRunning ? null : ZetaIcons.play,
        label: anyRunning ? 'Running…' : 'Run all',
      ),
    );
  }
}
