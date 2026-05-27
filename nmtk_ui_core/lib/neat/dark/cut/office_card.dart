import 'package:flutter/material.dart';

/// Office detail card showing a hero image plus address and phone rows.
class OfficeCard extends StatelessWidget {
  const OfficeCard({super.key, required this.officeName, required this.location, required this.address, required this.phone});
  final String officeName, location, address, phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      height: 492,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 16, top: 16,
            child: Container(
              width: 311, height: 200,
              decoration: ShapeDecoration(color: const Color(0xFFE9ECF2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
              child: Stack(children: [
                Positioned(left: 192, top: 150, child: Opacity(opacity: 0.20, child: Container(width: 100, height: 100, decoration: const ShapeDecoration(color: Color(0xFFB5E4CA), shape: OvalBorder())))),
                Positioned(left: 212, top: 170, child: Container(width: 60, height: 60, decoration: const ShapeDecoration(color: Color(0xFF60D39C), shape: OvalBorder()))),
              ]),
            ),
          ),
          Positioned(
            left: 24, top: 240,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(officeName, style: const TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
              Text(location, style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
            ]),
          ),
          Positioned(left: 24, top: 320, child: Container(width: 287, height: 1, color: const Color(0xFF4B4C57))),
          Positioned(
            left: 38, top: 344,
            child: Row(spacing: 16, children: [
              Container(width: 48, height: 48, decoration: ShapeDecoration(color: const Color(0xFFB0E5FC), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(80)))),
              SizedBox(width: 184, child: Text(address, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w500, height: 1.50))),
            ]),
          ),
          Positioned(
            left: 38, top: 414,
            child: Row(spacing: 16, children: [
              Container(width: 48, height: 48, decoration: ShapeDecoration(color: const Color(0xFFFFBC99), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(80)))),
              Text(phone, style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w500, height: 1.50)),
            ]),
          ),
        ],
      ),
    );
  }
}
