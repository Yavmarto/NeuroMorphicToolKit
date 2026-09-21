import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/deploy_target_data.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/deploy_target_catalog/sensor_source_data.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/deploy_results_provider.dart';

const List<DeployTargetData> deployTargets = [
  // ── In-app simulators ─────────────────────────────────────────────────────
  DeployTargetData(
    id: 'lava_sim',
    label: 'Lava (Simulator)',
    icon: Icons.bolt_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    runtimeCapable: true,
  ),
  DeployTargetData(
    id: 'snntorch_sim',
    label: 'snnTorch',
    icon:
        Icons.auto_graph_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    trainable: true,
    runtimeCapable: true,
  ),
  DeployTargetData(
    id: 'sc_neurocore_sim',
    label: 'SC-NeuroCore (Simulation)',
    icon: ZetaIcons.memory_sharp,
    runtimeCapable: true,
  ),
  DeployTargetData(
    id: 'brian2_sim',
    label: 'Brian2',
    icon: Icons.science_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    runtimeCapable: true,
  ),
  DeployTargetData(
    id: 'sinabs_sim',
    label: 'Sinabs',
    icon: ZetaIcons.memory,
    runtimeCapable: true,
    trainable: true,
  ),
  DeployTargetData(
    id: 'nengo_sim',
    label: 'Nengo',
    icon: Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    runtimeCapable: true,
  ),

  // ── Notebook-backed framework runtimes ────────────────────────────────────
  DeployTargetData(
    id: 'rockpool',
    label: 'Rockpool',
    icon: Icons.waves_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    runtimeCapable: true,
  ),
  DeployTargetData(
    id: 'pynn',
    label: 'PyNN',
    icon:
        Icons.device_hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
  ),
  // ── Hardware targets ──────────────────────────────────────────────────────
  DeployTargetData(
    id: 'akida',
    label: 'Akida',
    icon: Icons.hub_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    deployCapable: true,
  ),
  DeployTargetData(
    id: 'speck',
    label: 'Speck 2',
    icon: Icons.sensors_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    deployCapable: true,
  ),
  DeployTargetData(
    id: 'pynq',
    label: 'PYNQ-Z2',
    icon: Icons
        .developer_board_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    deployCapable: true,
  ),
  DeployTargetData(
    id: 'lava',
    label: 'Lava / Loihi2',
    icon: Icons
        .settings_input_composite_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    runtimeCapable: true,
    deployCapable: true,
  ),
  DeployTargetData(
    id: 'sc_neurocore_fpga',
    label: 'SC-NeuroCore (FPGA RTL)',
    icon: Icons
        .developer_board_sharp, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    deployCapable: true,
  ),
  DeployTargetData(
    id: 'voyager_axelera',
    label: 'Axelera Voyager (YOLOv8n)',
    icon: Icons
        .memory_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    deployCapable: true,
  ),
];

/// Live data-acquisition sources offered in Setup alongside (never merged
/// into) [deployTargets] — see [SensorSourceData] for why they're kept out
/// of the compute-target capability model.
const List<SensorSourceData> liveSourceTargets = [
  SensorSourceData(
    id: 'neurosense',
    label: 'NeuroSense (live sensor)',
    icon: Icons.sensors_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
  ),
];

SensorSourceData? sensorSourceForId(String targetId) {
  for (final source in liveSourceTargets) {
    if (source.id == targetId) {
      return source;
    }
  }
  return null;
}

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

bool targetIsRuntimeCapable(String targetId) =>
    targetForId(targetId).runtimeCapable;

bool targetIsDeployCapable(String targetId) =>
    targetForId(targetId).deployCapable;

/// Export-only handoff targets (SpiNNaker via PyNN) — no in-app Run row.
bool targetIsExportOnly(String targetId) {
  final target = targetForId(targetId);
  return !target.runtimeCapable && !target.deployCapable;
}

/// Framework notebook runtimes that get a Run row but not `/simulators/run`.
List<String> frameworkRuntimeBackendIds() => deployTargets
    .where(
      (t) => t.runtimeCapable && !kSimulatorDeployBackends.contains(t.id),
    )
    .map((t) => t.id)
    .toList(growable: false);
