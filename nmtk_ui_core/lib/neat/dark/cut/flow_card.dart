import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Compact in/out cash-flow row (icon + title + amount + change caption).
class FlowCard extends StatelessWidget {
  const FlowCard({super.key, required this.title, required this.amount, required this.change, required this.iconBg});
  final String title, amount, change;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      height: 80,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(spacing: 12, children: [
            Container(width: 42, height: 42, decoration: ShapeDecoration(color: iconBg, shape: const OvalBorder())),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, spacing: 4, children: [
            Row(spacing: 4, children: [
              const Text('\$', style: TextStyle(color: Color(0xFF7E8BA0), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
              Text(amount, style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
            ]),
            Text(change, style: const TextStyle(color: Color(0xFF7E8BA0), fontSize: 10, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.80)),
          ]),
        ],
      ),
    );
  }
}
