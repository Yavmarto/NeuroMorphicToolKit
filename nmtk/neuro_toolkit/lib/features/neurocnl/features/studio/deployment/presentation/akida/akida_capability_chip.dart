import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Readiness indicator for an Akida host capability.

class AkidaCapabilityChip extends StatelessWidget {
  const AkidaCapabilityChip({
    super.key,
    required this.label,
    required this.available,
  });

  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    return NmtkStatusBadge(
      label: '$label · ${available ? 'Ready' : 'Missing'}',
      tone: available ? NmtkTone.success : NmtkTone.warning,
      icon: available
          ? ZetaIcons.check_circle_outline
          : ZetaIcons.error_outline,
      semanticsLabel: available
          ? '$label is installed'
          : '$label is missing from the host runtime',
    );
  }
}
