import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:nmtk_ui_core/neat/dark/cut/billing_toggle.dart';

/// Header card on the upgrade/pricing page (title + blurb + monthly/yearly toggle).
class PricingHeaderCard extends StatelessWidget {
  const PricingHeaderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          Text('Pricing Plans', style: TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
          SizedBox(
            width: 293,
            child: Text(
              'Neat Mobile Dashboard no credit card required.\nAll plans come with a free, 14 day trial of our Premium features.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50),
            ),
          ),
          BillingToggle(),
        ],
      ),
    );
  }
}
