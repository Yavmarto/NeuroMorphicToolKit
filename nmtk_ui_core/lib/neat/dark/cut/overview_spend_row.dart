import 'package:flutter/material.dart';

/// Single label/value/change row used at the bottom of [OverviewChartCard].
class OverviewSpendRow extends StatelessWidget {
  const OverviewSpendRow({super.key, required this.label, required this.value, required this.change, required this.positive});
  final String label, value, change;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.33)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
        Text(change, style: TextStyle(color: positive ? const Color(0xFF60D39C) : const Color(0xFFFF5555), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
      ],
    );
  }
}
