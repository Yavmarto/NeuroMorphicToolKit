import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/studio_pynq_deploy_service.dart';

/// The one place the hardware claim is worded for PYNQ.
///
/// A deploy that fell back to the board's software simulator is rejected by
/// [StudioPynqDeployService.deploy], so a present ack always means silicon — but
/// the badge still reads `runtime_mode` rather than assuming, because that field
/// is the only thing that ever distinguished the two.
Widget pynqProvenanceBadge(PynqDeployAck ack) => NmtkStatusBadge(
  label: ack.isHardware ? 'Loaded on PYNQ-Z2 FPGA' : 'Simulator result',
  tone: ack.isHardware ? NmtkTone.success : NmtkTone.warning,
  icon: ack.isHardware ? ZetaIcons.check_circle_outline : ZetaIcons.warning,
);

/// Deploy workspace for a PYNQ-Z2 board.
///
/// Execution on the left (deploy → run → verify), setup on the right (pair →
/// provision → overlay → readiness), matching the Akida workspace. The order
/// is not cosmetic: each step is refused by the board until the one before it
/// has happened, so the pane shows exactly which one is outstanding.
