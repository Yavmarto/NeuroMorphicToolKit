import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// "Your Progress" header card on the tracker screen showing the monthly
/// percentage reached. Note: distinct from the public NMTK `ProgressCard`
/// widget; this one is internal to the neat/dark exploration tree.
class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      height: 120,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            Text('Your Progress', style: TextStyle(color: Colors.white, fontSize: 20, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.30)),
            Text('Monthly Percentage Reached', style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
          ]),
          Text('75%', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
        ],
      ),
    );
  }
}
