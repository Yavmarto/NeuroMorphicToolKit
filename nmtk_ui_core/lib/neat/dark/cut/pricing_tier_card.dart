import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/choose_plan_button.dart';

/// One pricing tier card on the upgrade page (price + feature list + CTA).
class PricingTierCard extends StatelessWidget {
  const PricingTierCard({
    super.key,
    required this.tier,
    required this.price,
    required this.isHighlighted,
  });
  final String tier, price;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      height: isHighlighted ? 532 : 483,
      decoration: ShapeDecoration(
        color: isHighlighted
            ? const Color(0xFF2A85FF)
            : const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: isHighlighted
              ? BorderSide.none
              : const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          Opacity(
            opacity: 0.50,
            child: Text(
              tier,
              style: TextStyle(
                color: isHighlighted ? Colors.white : const Color(0xFF808D9E),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                height: 1.43,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: [
              Text(
                price,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  height: 1.08,
                  letterSpacing: -0.48,
                ),
              ),
              Text(
                '/month',
                style: TextStyle(
                  color: isHighlighted ? Colors.white : const Color(0xFF1D1D25),
                  fontSize: 16,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  height: 1.50,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF4B4C57), thickness: 1),
          ..._featureItems(isHighlighted),
          ChoosePlanButton(isHighlighted: isHighlighted),
        ],
      ),
    );
  }

  List<Widget> _featureItems(bool highlighted) {
    const labels = [
      'Basic Support',
      'Design Style',
      'Component Library',
      'All limited links',
      'Unlimited users',
    ];
    return labels
        .map(
          (l) => Row(
            spacing: 12,
            children: [
              const SizedBox(width: 20, height: 20),
              Text(
                l,
                style: TextStyle(
                  color: highlighted ? Colors.white : Colors.white,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  height: 1.57,
                  letterSpacing: -0.50,
                ),
              ),
            ],
          ),
        )
        .toList();
  }
}
