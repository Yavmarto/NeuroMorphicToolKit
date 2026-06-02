import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Squarish activity-type tile (icon area + label + sub-label).
class ActivityTypeCard extends StatelessWidget {
  const ActivityTypeCard({
    super.key,
    required this.label,
    required this.sublabel,
  });
  final String label, sublabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      height: 168,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          const SizedBox(width: 48, height: 48),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              height: 1.30,
            ),
          ),
          Text(
            sublabel,
            style: const TextStyle(
              color: Color(0xFF808D9E),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
              height: 1.57,
              letterSpacing: -0.50,
            ),
          ),
        ],
      ),
    );
  }
}
