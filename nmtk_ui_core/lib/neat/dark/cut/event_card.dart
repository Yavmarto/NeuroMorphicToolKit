import 'package:flutter/material.dart';

/// Featured event tile (thumbnail + title + venue/date + CTA) used on the
/// Neat Events listing page.
class EventCard extends StatelessWidget {
  const EventCard({super.key});

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
      child: Row(
        spacing: 16,
        children: [
          Container(width: 100, height: 100, decoration: ShapeDecoration(color: const Color(0xFFE9ECF2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                const Text('Indonesian Designer Community', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
                Row(spacing: 8, children: [
                  Container(width: 6, height: 32, decoration: ShapeDecoration(color: const Color(0xFFB5E4CA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)))),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Bathoro Katong Stadium', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.67)),
                    Text('28-31 August, 2022', style: TextStyle(color: Color(0xFF808D9E), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.33)),
                  ]),
                ]),
                const Text('Get Access', style: TextStyle(color: Color(0xFF2A85FF), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, height: 1.43)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
