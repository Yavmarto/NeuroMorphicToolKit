import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/studio_pynq_deploy_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/pynq_support_state_card.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_results_view/pynq_run_result_body.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/pynq_results_view/pynq_verify_result_body.dart';

class PynqResultsView extends ConsumerWidget {
  const PynqResultsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studioPynqDeployProvider);
    final export = state.exportResult;
    final run = state.runResult;
    final verify = state.verifyResult;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (export != null)
          NmtkSectionCard(
            title: 'PYNQ-Z2 Deployability',
            child: PynqSupportStateCard(
              supportState: export.supportState,
              warnings: export.warnings,
              rejections: export.rejectionReasons,
              networkSummary: export.networkSummary,
            ),
          ),
        if (run != null) ...[
          const SizedBox(height: 16),
          NmtkSectionCard(
            title: 'Board run',
            child: PynqRunResultBody(
              result: run,
              hasTrainedWeights: state.hasTrainedWeights,
              expectedLabel: state.usingDatasetSample
                  ? state.datasetSample?.label
                  : null,
            ),
          ),
        ],
        if (verify != null) ...[
          const SizedBox(height: 16),
          NmtkSectionCard(
            title: 'Verification',
            child: PynqVerifyResultBody(result: verify),
          ),
        ],
      ],
    );
  }
}
