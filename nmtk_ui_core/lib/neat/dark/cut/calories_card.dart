import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Tall "Calories Burnt" tile.
class CaloriesCard extends StatelessWidget {
  const CaloriesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 216,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 8,
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: Color(0xFFFFE6DF),
                shape: OvalBorder(),
              ),
            ),
          ),
          Text(
            '1,900',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              height: 1.17,
              letterSpacing: -0.36,
            ),
          ),
          Text(
            'Calories Burnt',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF808D9E),
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.33,
            ),
          ),
        ],
      ),
    );
  }
}
