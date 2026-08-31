import 'package:flutter/widgets.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/presentation/studio_hardware_action_spec.dart';

/// Renders the available hardware-workflow actions.

class StudioHardwareActionWrap extends StatelessWidget {
  const StudioHardwareActionWrap({super.key, required this.actions});

  final List<StudioHardwareActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < actions.length; i++)
          if (actions[i].variant == StudioHardwareActionVariant.outlined)
            ZetaButton.outline(
              onPressed: actions[i].onPressed,
              leadingIcon: actions[i].icon,
              label: actions[i].label,
            )
          else
            ZetaButton(
              onPressed: actions[i].onPressed,
              label: actions[i].label,
              leadingIcon: actions[i].icon,
            ),
      ],
    );
  }
}
