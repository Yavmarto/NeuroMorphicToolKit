import 'package:flutter/material.dart';
import 'attendance_stat_row.dart';
import 'dark_card_header.dart';

/// Monthly attendance recap card with stats (Present / Paid Leave / Not present).
class AttendanceRecapCard extends StatelessWidget {
  const AttendanceRecapCard({super.key});

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 24,
        children: [
          const DarkCardHeader(
            title: 'Attendance Recap',
            iconColor: Color(0xFFCABDFE),
          ),
          // Month navigation
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 8,
            children: [
              const Text(
                'Jul',
                style: TextStyle(
                  color: Color(0xFF737A8B),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  height: 1.43,
                ),
              ),
              Container(
                transform: Matrix4.identity()..rotateZ(3.14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 10,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(),
                      child: const Stack(),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 97,
                height: 48,
                child: const Text(
                  'August',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    height: 1.30,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(),
                    child: const Stack(),
                  ),
                ],
              ),
              const Text(
                'Sep',
                style: TextStyle(
                  color: Color(0xFF737A8B),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  height: 1.43,
                ),
              ),
            ],
          ),
          // Stats rows
          AttendanceStatRow(
            color: const Color(0xFF2180FF),
            label: 'Present',
            value: '16 days',
          ),
          AttendanceStatRow(
            color: const Color(0xFFFFD88D),
            label: 'Paid Leave',
            value: '4 days',
          ),
          AttendanceStatRow(
            color: const Color(0xFFB0E5FC),
            label: 'Not present',
            value: '2 days',
          ),
        ],
      ),
    );
  }
}
