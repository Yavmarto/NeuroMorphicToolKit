import 'package:flutter/material.dart';
import 'dark_card_header.dart';

/// "IPS Graph" placeholder card on the student dashboard.
class IpsGraphCard extends StatelessWidget {
  const IpsGraphCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF1D1D25),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFF4B4C57)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          DarkCardHeader(title: 'IPS Graph', iconColor: Color(0xFFB0E5FC)),
          SizedBox(height: 100),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('4th Semester', style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50)),
              Text('3.7', style: TextStyle(color: Colors.white, fontSize: 30, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.20, letterSpacing: -0.30)),
            ],
          ),
        ],
      ),
    );
  }
}
