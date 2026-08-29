import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/sc_neurocore_synthesis_target.dart';

class ScNeuroCoreSetupPane extends StatelessWidget {
  const ScNeuroCoreSetupPane({super.key, required this.target});

  final ScNeuroCoreTarget? target;

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Synthesis setup',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (target == null) ...[
          const NmtkKeyValueRow(
            label: 'Artifact',
            value: 'SystemVerilog RTL + bitstream',
          ),
          const NmtkKeyValueRow(
            label: 'Supported families',
            value: 'iCE40 • ECP5 • Gowin • Xilinx • Intel',
          ),
        ] else ...[
          NmtkKeyValueRow(
            label: 'Synthesis target',
            value: target!.displayName,
          ),
          NmtkKeyValueRow(label: 'FPGA family', value: target!.family.label),
          if (target!.deviceSpec.isNotEmpty)
            NmtkKeyValueRow(label: 'Device spec', value: target!.deviceSpec),
          NmtkKeyValueRow(label: 'Toolchain', value: target!.toolchain.label),
          if (target!.toolchainBinPath.isNotEmpty)
            NmtkKeyValueRow(
              label: 'Toolchain path',
              value: target!.toolchainBinPath,
            ),
          if (target!.deploymentMode == ScNeuroCoreDeploymentMode.network) ...[
            const NmtkKeyValueRow(label: 'Deployment', value: 'Network (SSH)'),
            NmtkKeyValueRow(
              label: 'Host',
              value:
                  'ssh://${target!.username}@${target!.host}:${target!.sshPort}',
            ),
            if (target!.sshKeyPath.isNotEmpty)
              NmtkKeyValueRow(label: 'SSH Key', value: target!.sshKeyPath),
          ] else ...[
            if (target!.outputDirectory.isNotEmpty)
              NmtkKeyValueRow(
                label: 'Output directory',
                value: target!.outputDirectory,
              ),
          ],
        ],
      ],
    );
  }
}
