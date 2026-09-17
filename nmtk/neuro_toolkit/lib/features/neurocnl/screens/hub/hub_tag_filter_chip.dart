import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

class HubTagFilterChip extends StatelessWidget {
  const HubTagFilterChip({
    super.key,
    required this.tag,
    required this.selected,
    required this.onChanged,
  });

  final String tag;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Filter by tag $tag',
    selected: selected,
    button: true,
    child: selected
        ? NmtkPrimaryButton(
            label: tag,
            tone: NmtkTone.info,
            onPressed: () => onChanged(false),
          )
        : NmtkOutlinedButton(label: tag, onPressed: () => onChanged(true)),
  );
}
