import 'package:flutter/material.dart';

/// Top status bar used across all dark Neat screens.
/// Displays time "11:20" and a battery indicator at position (0, 0) size 375×44.
class DarkStatusBar extends StatelessWidget {
  const DarkStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 375,
      height: 44,
      decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
      child: Stack(
        children: [
          Positioned(left: 0, top: 0, child: Container(width: 375, height: 44)),
          Positioned(
            left: 336,
            top: 17.33,
            child: Opacity(
              opacity: 0.35,
              child: Container(
                width: 22,
                height: 11.33,
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Colors.white),
                    borderRadius: BorderRadius.circular(2.67),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 338,
            top: 19.33,
            child: Container(
              width: 18,
              height: 7.33,
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(1.33),
                ),
              ),
            ),
          ),
          Positioned(
            left: 21,
            top: 13,
            child: SizedBox(
              width: 54,
              height: 21,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 2,
                    child: SizedBox(
                      width: 54,
                      child: const Text(
                        '11:20',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          height: 1.14,
                          letterSpacing: -0.28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
