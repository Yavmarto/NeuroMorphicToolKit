import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Monthly / Yearly two-segment switch shown above pricing tiers.
class BillingToggle extends StatelessWidget {
  const BillingToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 42,
      decoration: ShapeDecoration(
        color: const Color(0xFF383942),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 112,
            height: 42,
            decoration: const ShapeDecoration(
              color: Color(0xFF2A85FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            child: const Center(
              child: Text(
                'Monthly',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  height: 1.43,
                ),
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Yearly',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF808D9E),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  height: 1.43,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
