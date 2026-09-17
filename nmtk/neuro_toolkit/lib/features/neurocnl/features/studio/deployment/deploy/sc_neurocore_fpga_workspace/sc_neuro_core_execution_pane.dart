import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_workspace_panel/support.dart';

class ScNeuroCoreExecutionPane extends StatelessWidget {
  const ScNeuroCoreExecutionPane({super.key, required this.hasTarget});

  final bool hasTarget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasTarget)
          const NmtkStatusBanner(
            title:
                'No synthesis target selected. '
                'Click "Manage Targets" to add an FPGA target.',
            tone: NmtkTone.warning,
            icon: Icons
                .developer_board_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          )
        else
          const NmtkStatusBanner(
            title:
                'Export the NIR artifact, then run the SC-NeuroCore RTL '
                'compiler (sc-neurocore deploy) to emit RTL + bitstream.',
            tone: NmtkTone.info,
            icon: Icons
                .developer_board_sharp, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          ),
        const SizedBox(height: 16),
        ZetaButton.outline(
          onPressed: () => showCompiledArtifactsDialog(context),
          leadingIcon: Icons
              .account_tree_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          label: 'View NIR Artifact',
        ),
      ],
    );
  }
}
