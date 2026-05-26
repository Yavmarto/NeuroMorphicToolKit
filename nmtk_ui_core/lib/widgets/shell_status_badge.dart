import 'package:flutter/material.dart';
import 'package:zeta_flutter/zeta_flutter.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/widgets/status_badge.dart';

class NmtkShellStatusBadge extends StatelessWidget {
  final NmtkShellStatusSpec status;

  const NmtkShellStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: status.detailText ?? status.label,
      child: NmtkStatusBadge(
        label: status.label,
        tone: status.tone,
        icon: status.icon,
        semanticsLabel: status.semanticsLabel,
      ),
    );
  }
}
