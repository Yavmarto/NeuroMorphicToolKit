import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/deploy_target_data.dart';

const List<DeployTargetData> deployTargets = [
  // ── Software simulators ───────────────────────────────────────────────────
  DeployTargetData(
    id: 'lava_sim',
    label: 'Lava (Simulator)',
    icon: Icons.bolt_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'simulator',
  ),
  DeployTargetData(
    id: 'snntorch_sim',
    label: 'snnTorch',
    icon:
        Icons.auto_graph_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'simulator',
    trainable: true,
  ),
  DeployTargetData(
    id: 'sc_neurocore_sim',
    label: 'SC-NeuroCore (Simulation)',
    icon: ZetaIcons.memory_sharp,
    kind: 'simulator',
  ),

  // ── NIR-native simulation frameworks ─────────────────────────────────────
  DeployTargetData(
    id: 'brian2',
    label: 'Brian2',
    icon: Icons.science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'codegen',
  ),
  DeployTargetData(
    id: 'sinabs',
    label: 'Sinabs',
    icon: ZetaIcons.memory,
    kind: 'codegen',
  ),
  DeployTargetData(
    id: 'rockpool',
    label: 'Rockpool',
    icon: Icons.waves_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'codegen',
  ),
  DeployTargetData(
    id: 'pynn',
    label: 'PyNN',
    icon:
        Icons.device_hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'codegen',
  ),
  DeployTargetData(
    id: 'nengo',
    label: 'Nengo',
    icon: Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'codegen',
  ),
  // ── Hardware targets ──────────────────────────────────────────────────────
  DeployTargetData(
    id: 'akida',
    label: 'Akida',
    icon: Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'hardware',
  ),
  DeployTargetData(
    id: 'pynq',
    label: 'PYNQ-Z2',
    icon: Icons
        .developer_board_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'hardware',
  ),
  DeployTargetData(
    id: 'lava',
    label: 'Lava / Loihi2',
    icon: Icons
        .settings_input_composite_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'hardware',
  ),
  DeployTargetData(
    id: 'sc_neurocore_fpga',
    label: 'SC-NeuroCore (FPGA RTL)',
    icon: Icons
        .developer_board_sharp, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    kind: 'hardware',
  ),
];

DeployTargetData targetForId(String targetId) {
  for (final target in deployTargets) {
    if (target.id == targetId) {
      return target;
    }
  }
  return deployTargets.first;
}

String targetLabel(String targetId) => targetForId(targetId).label;

/// Whether Play trains [targetId]. See [DeployTargetData.trainable] — this is
/// for labelling only; the run/skip decision comes from the backend.
bool targetIsTrainable(String targetId) => targetForId(targetId).trainable;
