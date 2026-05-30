import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

class NeatSearch extends StatelessWidget {
  const NeatSearch({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 832,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 44,
                child: Container(
                  width: 375,
                  height: 133,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(color: Color(0xFFF4F4F4)),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          width: 375,
                          padding: const EdgeInsets.only(
                            top: 24,
                            left: 20,
                            right: 20,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1D1D25),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 24,
                            children: [
                              Container(
                                width: 284,
                                height: 48,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFF1D1D25),
                                  shape: RoundedRectangleBorder(
                                    side: const BorderSide(
                                      width: 2,
                                      color: Color(0xFF2180FF),
                                    ),
                                    borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                                  ),
                                ),
                              ),
                              Container(
                                width: 24,
                                height: 24,
                                clipBehavior: Clip.antiAlias,
                                decoration: const BoxDecoration(),
                                child: const Stack(),
                              ),
                              const Text(
                                'report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                              Container(
                                transform: Matrix4.identity()
                                  
                                  ..rotateZ(1.57),
                                width: 24,
                                decoration: const ShapeDecoration(
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      width: 1,
                                      strokeAlign: BorderSide.strokeAlignCenter,
                                      color: Color(0xFF808D9E),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.center,
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
                              const Text(
                                'All',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                              const Text(
                                'Product',
                                style: TextStyle(
                                  color: Color(0xFF808D9E),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                              const Text(
                                'Sales',
                                style: TextStyle(
                                  color: Color(0xFF808D9E),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                              const Text(
                                'Customer',
                                style: TextStyle(
                                  color: Color(0xFF808D9E),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                              const Text(
                                'Finance',
                                style: TextStyle(
                                  color: Color(0xFF808D9E),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                              Container(
                                width: 30,
                                height: 18,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                ),
                                decoration: ShapeDecoration(
                                  color: const Color(0xFF444650),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      height: 12,
                                      child: Text(
                                        '99+',
                                        style: TextStyle(
                                          color: Color(0xFFE9ECF2),
                                          fontSize: 11,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w500,
                                          height: 1.82,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 72,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2180FF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 16,
                top: 201,
                child: Text(
                  'Related Topic',
                  style: TextStyle(
                    color: Color(0xFF808D9E),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.43,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 229,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: ShapeDecoration(
                    color: const Color(0xFFB0E5FC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 10,
                    children: [
                      Text(
                        'Overview',
                        style: TextStyle(
                          color: Color(0xFF1D1D25),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          height: 1.43,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 109,
                top: 229,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: ShapeDecoration(
                    color: const Color(0xFFB0E5FC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 10,
                    children: [
                      Text(
                        'Statstic',
                        style: TextStyle(
                          color: Color(0xFF1D1D25),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          height: 1.43,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 190,
                top: 229,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: ShapeDecoration(
                    color: const Color(0xFFB0E5FC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 10,
                    children: [
                      Text(
                        'Avg Total Sales',
                        style: TextStyle(
                          color: Color(0xFF1D1D25),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          height: 1.43,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 16,
                top: 285,
                child: Text(
                  'Search Result',
                  style: TextStyle(
                    color: Color(0xFF808D9E),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.43,
                  ),
                ),
              ),
              const Positioned(
                left: 42,
                top: 347,
                child: Text(
                  'Neat Sales Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.43,
                  ),
                ),
              ),
              Positioned(
                left: 335,
                top: 334,
                child: Container(
                  width: 24,
                  height: 24,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  child: const Stack(),
                ),
              ),
              const Positioned(
                left: 42,
                top: 323,
                child: SizedBox(
                  width: 79,
                  height: 20,
                  child: Text(
                    'Sales Report',
                    style: TextStyle(
                      color: Color(0xFF808D9E),
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      height: 1.57,
                      letterSpacing: -0.50,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 325,
                child: Container(
                  width: 10,
                  height: 42,
                  decoration: ShapeDecoration(
                    color: const Color(0xFFCABDFE),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 42,
                top: 419,
                child: Text(
                  'Montly Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.43,
                  ),
                ),
              ),
              const Positioned(
                left: 42,
                top: 395,
                child: SizedBox(
                  width: 79,
                  height: 20,
                  child: Text(
                    'Finance',
                    style: TextStyle(
                      color: Color(0xFF808D9E),
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      height: 1.57,
                      letterSpacing: -0.50,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 397,
                child: Container(
                  width: 10,
                  height: 42,
                  decoration: ShapeDecoration(
                    color: const Color(0xFFFFBC99),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 335,
                top: 406,
                child: Container(
                  width: 24,
                  height: 24,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  child: const Stack(),
                ),
              ),
              const Positioned(
                left: 74,
                top: 519,
                child: Text(
                  'Attendance Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.43,
                  ),
                ),
              ),
              Positioned(
                left: 335,
                top: 506,
                child: Container(
                  width: 24,
                  height: 24,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  child: const Stack(),
                ),
              ),
              const Positioned(
                left: 74,
                top: 495,
                child: SizedBox(
                  width: 79,
                  height: 20,
                  child: Text(
                    'Statistic',
                    style: TextStyle(
                      color: Color(0xFF808D9E),
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      height: 1.57,
                      letterSpacing: -0.50,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 497,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: ShapeDecoration(
                    color: const Color(0xFFE9ECF2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 25,
                top: 506,
                child: Container(
                  width: 24,
                  height: 24,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  child: const Stack(),
                ),
              ),
              const Positioned(
                left: 74,
                top: 591,
                child: Text(
                  'Avg Total Sales',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    height: 1.43,
                  ),
                ),
              ),
              const Positioned(
                left: 74,
                top: 567,
                child: SizedBox(
                  width: 79,
                  height: 20,
                  child: Text(
                    'Report',
                    style: TextStyle(
                      color: Color(0xFF808D9E),
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      height: 1.57,
                      letterSpacing: -0.50,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 569,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: ShapeDecoration(
                    color: const Color(0xFFE9ECF2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 25,
                top: 578,
                child: SizedBox(width: 24, height: 24, child: Stack()),
              ),
              Positioned(
                left: 335,
                top: 578,
                child: Container(
                  width: 24,
                  height: 24,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(),
                  child: const Stack(),
                ),
              ),
              Positioned(
                left: 16,
                top: 467,
                child: Container(
                  width: 343,
                  decoration: const ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        width: 1,
                        strokeAlign: BorderSide.strokeAlignCenter,
                        color: Color(0xFF4B4C57),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: 375,
                  height: 44,
                  decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
                  child: Stack(
                    children: [
                      const Positioned(
                        left: 0,
                        top: 0,
                        child: SizedBox(width: 375, height: 44),
                      ),
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
                      const Positioned(
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
                                  child: Text(
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
