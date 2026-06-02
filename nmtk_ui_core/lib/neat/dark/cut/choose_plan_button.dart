import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// "Choose plan" CTA shown at the bottom of every [PricingTierCard].
class ChoosePlanButton extends StatelessWidget {
  const ChoosePlanButton({super.key, required this.isHighlighted});
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      height: 48,
      decoration: ShapeDecoration(
        color: isHighlighted ? Colors.white : const Color(0xFFF2F3FB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: const Center(
        child: Text(
          'Choose plan',
          style: TextStyle(
            color: Color(0xFF2A85FF),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}
