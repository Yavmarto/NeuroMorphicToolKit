import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Compact "Info" announcement strip on top of the e-learning page.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 343,
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: const Color(0xFF383942),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            NmtkShellTokens.of(context).radiusSm,
          ),
        ),
      ),
      child: Row(
        spacing: 12,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: ShapeDecoration(
              color: const Color(0xFFFFD88D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: const Text(
              'Info',
              style: TextStyle(
                color: Color(0xFF1D1D25),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                height: 1.43,
              ),
            ),
          ),
          const Text(
            'Schedule Seminar for D4 LJ PJJ',
            style: TextStyle(
              color: Colors.white,
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
