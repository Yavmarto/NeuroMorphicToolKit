import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

class NeatSearchEmpty extends StatelessWidget {
  const NeatSearchEmpty({super.key});

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
                  height: 96,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(color: Color(0xFFF4F4F4)),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          width: 375,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1D1D25),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
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
                                'Search something here',
                                style: TextStyle(
                                  color: Color(0xFF808D9E),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                  height: 1.57,
                                  letterSpacing: -0.50,
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
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 89,
                top: 518,
                child: Text(
                  'Search result will be here',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const Positioned(
                left: 82,
                top: 550,
                child: Text(
                  'Type something on the search bar',
                  textAlign: TextAlign.center,
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
