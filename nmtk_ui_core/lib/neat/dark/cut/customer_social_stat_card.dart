import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Compact social platform stat row (followers count + delta + platform label).
class CustomerSocialStatCard extends StatelessWidget {
  const CustomerSocialStatCard({super.key, required this.value, required this.change, required this.label});
  final String value, change, label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      height: 97,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      child: Row(
        spacing: 16,
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.50)),
          Text(change, style: const TextStyle(color: Color(0xFF60D39C), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
          Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
          Container(
            width: 48, height: 48,
            decoration: const ShapeDecoration(color: Color(0xFF1D1D25), shape: OvalBorder(side: BorderSide(width: 2, color: Color(0xFF4B4C57)))),
          ),
        ],
      ),
    );
  }
}
