import 'package:flutter/material.dart';

/// Temperature log row (day + reading + time + level pill).
class TempLogRow extends StatelessWidget {
  const TempLogRow({super.key, required this.level, required this.levelColor, required this.levelBg});
  final String level;
  final Color levelColor, levelBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Monday', style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
          const Text('36.1 °C', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
          const Text('12:01 PM', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: ShapeDecoration(color: levelBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
            child: Text(level, style: TextStyle(color: levelColor, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
          ),
        ],
      ),
    );
  }
}
