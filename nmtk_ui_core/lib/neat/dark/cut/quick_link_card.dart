import 'package:flutter/material.dart';

/// Quick-link tile (icon + label + sub-label) used in the e-learning grid.
class QuickLinkCard extends StatelessWidget {
  const QuickLinkCard({super.key, required this.label, required this.sublabel});
  final String label, sublabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 132,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Container(width: 42, height: 42, decoration: const ShapeDecoration(color: Color(0xFF1D1D25), shape: OvalBorder(side: BorderSide(width: 2, color: Color(0xFF4B4C57))))),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
          Text(sublabel, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
        ],
      ),
    );
  }
}
