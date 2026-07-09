import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/models/shell_models.dart';
import 'package:nmtk_ui_core/widgets/status_badge.dart';

class NmtkShellStatusBadge extends StatelessWidget {
  final NmtkShellStatusSpec status;

  const NmtkShellStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    // ZETA-MIGRATION-EXEMPT: ZetaTooltip takes a `child: Widget` (an
    // always-visible styled bubble) with no message/hover-trigger API —
    // it is not a drop-in for this hover-triggered help text. Replacing it
    // would require building custom show/hide overlay logic, a behavior
    // change beyond a widget swap.
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
