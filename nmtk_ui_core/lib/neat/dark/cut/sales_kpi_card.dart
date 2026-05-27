import 'package:flutter/material.dart';

/// Compact KPI tile (label + change pill + value) used on the sales page.
class SalesKpiCard extends StatelessWidget {
  const SalesKpiCard({super.key, required this.label, required this.value, required this.change, required this.positive});
  final String label, value, change;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 163,
      height: 145,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.67, letterSpacing: 0.10)),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: ShapeDecoration(
              color: positive ? const Color(0xFFEAFAE4) : const Color(0x33FFBC99),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: Text(change, style: TextStyle(color: positive ? const Color(0xFF60D39C) : const Color(0xFFFF5555), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.33, letterSpacing: -0.12)),
          ),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
        ],
      ),
    );
  }
}
