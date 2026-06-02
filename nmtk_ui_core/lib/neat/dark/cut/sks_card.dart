import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Compact "SKS" credit-counter tile (used on the student dashboard).
class SksCard extends StatelessWidget {
  const SksCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 186,
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            'SKS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              height: 1.30,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '60',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          Text(
            'from 80 SKS',
            style: TextStyle(
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
