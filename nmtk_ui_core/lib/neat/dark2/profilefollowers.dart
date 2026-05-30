import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

class NeatProfileFollowers extends StatelessWidget {
  const NeatProfileFollowers({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1312,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: Stack(
            children: [
              Positioned(
                left: 16,
                top: 716,
                child: Container(
                  width: 343,
                  padding: const EdgeInsets.all(20),
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: const Color(0xFF1D1D25),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: 24,
                    children: [
                      SizedBox(
                        width: 319,
                        height: 52,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              child: Container(
                                width: 319,
                                height: 52,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFF373841),
                                  shape: RoundedRectangleBorder(
                                    side: const BorderSide(
                                      width: 1,
                                      color: Color(0xFF4B4C57),
                                    ),
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 4.92,
                              top: 5,
                              child: Container(
                                width: 96,
                                height: 42,
                                padding: const EdgeInsets.all(8),
                                clipBehavior: Clip.antiAlias,
                                decoration: ShapeDecoration(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    Text(
                                      'Products',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF808D9E),
                                        fontSize: 14,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w400,
                                        height: 1.29,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 104,
                              top: 5,
                              child: Container(
                                width: 99,
                                height: 42,
                                padding: const EdgeInsets.all(8),
                                clipBehavior: Clip.antiAlias,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFF1D1D25),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    Text(
                                      'Followers',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600,
                                        height: 1.29,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 206.92,
                              top: 5,
                              child: Container(
                                width: 107.60,
                                height: 42,
                                padding: const EdgeInsets.all(8),
                                clipBehavior: Clip.antiAlias,
                                decoration: ShapeDecoration(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    Text(
                                      'Comments',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF808D9E),
                                        fontSize: 14,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w400,
                                        height: 1.29,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 303,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 16,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 8,
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: 12,
                                      children: [
                                        SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left: 0,
                                                top: 0,
                                                child: Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: const ShapeDecoration(
                                                    color: Color(
                                                      0xFFE9ECF2,
                                                    ),
                                                    shape: OvalBorder(),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 243,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            spacing: 8,
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  spacing: 12,
                                                  children: [
                                                    const Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      spacing: 4,
                                                      children: [
                                                        Text(
                                                          'Gatot Sabhara',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                        Text(
                                                          '@gatot',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFF808D9E,
                                                            ),
                                                            fontSize: 14,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w400,
                                                            height: 1.57,
                                                            letterSpacing:
                                                                -0.50,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Container(
                                                      width: 45,
                                                      height: 22,
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 4,
                                                            left: 4,
                                                            bottom: 4,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                width: double.infinity,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  spacing: 12,
                                                  children: [
                                                    const Text(
                                                      '24k followers',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF808D9E,
                                                        ),
                                                        fontSize: 14,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.43,
                                                      ),
                                                    ),
                                                    Container(
                                                      width: 93,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 2,
                                                            vertical: 6,
                                                          ),
                                                      decoration: ShapeDecoration(
                                                        color: const Color(
                                                          0xFF1D1D25,
                                                        ),
                                                        shape: RoundedRectangleBorder(
                                                          side: const BorderSide(
                                                            width: 2,
                                                            color: Color(
                                                              0xFF4B4C57,
                                                            ),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        spacing: 8,
                                                        children: [
                                                          Container(
                                                            width: 24,
                                                            height: 24,
                                                            clipBehavior:
                                                                Clip.antiAlias,
                                                            decoration:
                                                                const BoxDecoration(),
                                                            child: const Stack(),
                                                          ),
                                                          const Text(
                                                            'Chat',
                                                            style: TextStyle(
                                                              color:
                                                                  Color(
                                                                    0xFF2180FF,
                                                                  ),
                                                              fontSize: 14,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              height: 1.43,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Container(
                                                      width: 100,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 2,
                                                            vertical: 8,
                                                          ),
                                                      decoration: ShapeDecoration(
                                                        color: const Color(
                                                          0xFF1D1D25,
                                                        ),
                                                        shape: RoundedRectangleBorder(
                                                          side: const BorderSide(
                                                            width: 2,
                                                            color: Color(
                                                              0xFF4B4C57,
                                                            ),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        spacing: 8,
                                                        children: [
                                                          Text(
                                                            'Following',
                                                            style: TextStyle(
                                                              color:
                                                                  Color(
                                                                    0xFF808D9E,
                                                                  ),
                                                              fontSize: 14,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              height: 1.43,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 303,
                              height: 1,
                              clipBehavior: Clip.antiAlias,
                              decoration: ShapeDecoration(
                                color: const Color(0xFF4B4C57),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 303,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 16,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 8,
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: 12,
                                      children: [
                                        SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left: 0,
                                                top: 0,
                                                child: Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: const ShapeDecoration(
                                                    color: Color(
                                                      0xFFE9ECF2,
                                                    ),
                                                    shape: OvalBorder(),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 243,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            spacing: 8,
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  spacing: 12,
                                                  children: [
                                                    const Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      spacing: 4,
                                                      children: [
                                                        Text(
                                                          'Beby Jovanca',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                        Text(
                                                          '@jova',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFF808D9E,
                                                            ),
                                                            fontSize: 14,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w400,
                                                            height: 1.57,
                                                            letterSpacing:
                                                                -0.50,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Container(
                                                      width: 45,
                                                      height: 22,
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 4,
                                                            left: 4,
                                                            bottom: 4,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                width: double.infinity,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  spacing: 12,
                                                  children: [
                                                    const Text(
                                                      '24k followers',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF808D9E,
                                                        ),
                                                        fontSize: 14,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.43,
                                                      ),
                                                    ),
                                                    Container(
                                                      width: 85,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 2,
                                                            vertical: 8,
                                                          ),
                                                      decoration: ShapeDecoration(
                                                        color: const Color(
                                                          0xFF1D1D25,
                                                        ),
                                                        shape: RoundedRectangleBorder(
                                                          side: const BorderSide(
                                                            width: 2,
                                                            color: Color(
                                                              0xFF4B4C57,
                                                            ),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        spacing: 8,
                                                        children: [
                                                          Text(
                                                            'Follow',
                                                            style: TextStyle(
                                                              color:
                                                                  Color(
                                                                    0xFF2180FF,
                                                                  ),
                                                              fontSize: 14,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              height: 1.43,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 303,
                              height: 1,
                              clipBehavior: Clip.antiAlias,
                              decoration: ShapeDecoration(
                                color: const Color(0xFF4B4C57),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 303,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 16,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 8,
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      spacing: 12,
                                      children: [
                                        SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left: 0,
                                                top: 0,
                                                child: Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: const ShapeDecoration(
                                                    color: Color(
                                                      0xFFE9ECF2,
                                                    ),
                                                    shape: OvalBorder(),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 243,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            spacing: 8,
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  spacing: 12,
                                                  children: [
                                                    const Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .start,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      spacing: 4,
                                                      children: [
                                                        Text(
                                                          'Renata Aduhai',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                        Text(
                                                          '@renata',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFF808D9E,
                                                            ),
                                                            fontSize: 14,
                                                            fontFamily: 'Inter',
                                                            fontWeight:
                                                                FontWeight.w400,
                                                            height: 1.57,
                                                            letterSpacing:
                                                                -0.50,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    Container(
                                                      width: 45,
                                                      height: 22,
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 4,
                                                            left: 4,
                                                            bottom: 4,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                width: double.infinity,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  spacing: 12,
                                                  children: [
                                                    const Text(
                                                      '24k followers',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFF808D9E,
                                                        ),
                                                        fontSize: 14,
                                                        fontFamily: 'Inter',
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.43,
                                                      ),
                                                    ),
                                                    Container(
                                                      width: 85,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 2,
                                                            vertical: 8,
                                                          ),
                                                      decoration: ShapeDecoration(
                                                        color: const Color(
                                                          0xFF1D1D25,
                                                        ),
                                                        shape: RoundedRectangleBorder(
                                                          side: const BorderSide(
                                                            width: 2,
                                                            color: Color(
                                                              0xFF4B4C57,
                                                            ),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                      ),
                                                      child: const Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        spacing: 8,
                                                        children: [
                                                          Text(
                                                            'Follow',
                                                            style: TextStyle(
                                                              color:
                                                                  Color(
                                                                    0xFF2180FF,
                                                                  ),
                                                              fontSize: 14,
                                                              fontFamily:
                                                                  'Inter',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              height: 1.43,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 303,
                              height: 1,
                              clipBehavior: Clip.antiAlias,
                              decoration: ShapeDecoration(
                                color: const Color(0xFF4B4C57),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF1D1D25),
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(
                              width: 2,
                              color: Color(0xFF4B4C57),
                            ),
                            borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 8,
                          children: [
                            Text(
                              'Load more',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                          padding: const EdgeInsets.all(24),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1D1D25),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            spacing: 448,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: const ShapeDecoration(
                                  color: Colors.white,
                                  shape: OvalBorder(),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                width: 48,
                                height: 48,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: 12,
                                      top: 12,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        clipBehavior: Clip.antiAlias,
                                        decoration: const BoxDecoration(),
                                        child: const Stack(),
                                      ),
                                    ),
                                    Positioned(
                                      left: 26,
                                      top: 12,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        clipBehavior: Clip.antiAlias,
                                        decoration: ShapeDecoration(
                                          color: const Color(0xFFFF5555),
                                          shape: RoundedRectangleBorder(
                                            side: const BorderSide(
                                              width: 2,
                                              strokeAlign:
                                                  BorderSide.strokeAlignOutside,
                                              color: Color(0xFF1D1D25),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
              Positioned(
                left: 16,
                top: 156,
                child: Container(
                  width: 343,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 32,
                  ),
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: const Color(0xFF1D1D25),
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(
                        width: 1,
                        color: Color(0xFF4B4C57),
                      ),
                      borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 32,
                    children: [
                      const SizedBox(
                        width: 117,
                        child: Text(
                          'Beby Jovanca',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const Text(
                        '@bebyjovanca',
                        style: TextStyle(
                          color: Color(0xFF808D9E),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          height: 1.57,
                          letterSpacing: -0.50,
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: const ShapeDecoration(
                                  color: Color(0xFFE9ECF2),
                                  shape: OvalBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const ShapeDecoration(
                          color: Colors.white,
                          shape: OvalBorder(),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: ShapeDecoration(
                          color: const Color(0xFF808D9E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const Text(
                        '2.9 M',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          height: 1.56,
                          letterSpacing: -0.50,
                        ),
                      ),
                      const Text(
                        'Followers',
                        style: TextStyle(
                          color: Color(0xFF808D9E),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          height: 1.57,
                          letterSpacing: -0.50,
                        ),
                      ),
                      const Text(
                        '1,902',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                          height: 1.56,
                          letterSpacing: -0.50,
                        ),
                      ),
                      const Text(
                        'Post',
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
                        width: 143.73,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF1D1D25),
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(
                              width: 2,
                              color: Color(0xFF4B4C57),
                            ),
                            borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 8,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              clipBehavior: Clip.antiAlias,
                              decoration: const BoxDecoration(),
                              child: const Stack(),
                            ),
                            const Text(
                              'Follow',
                              style: TextStyle(
                                color: Color(0xFF2180FF),
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 143.73,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF1D1D25),
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(
                              width: 2,
                              color: Color(0xFF4B4C57),
                            ),
                            borderRadius: BorderRadius.circular(NmtkShellTokens.of(context).radiusSm),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 8,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              clipBehavior: Clip.antiAlias,
                              decoration: const BoxDecoration(),
                              child: const Stack(),
                            ),
                            const Text(
                              'Chat',
                              style: TextStyle(
                                color: Color(0xFF2180FF),
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 303,
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
                      Container(
                        width: 303,
                        height: 45,
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(),
                        child: const Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 24,
                              child: SizedBox(
                                width: 303,
                                child: Text(
                                  '081-291893-139',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: 0,
                              child: SizedBox(
                                width: 151.50,
                                child: Text(
                                  'MOBILE',
                                  style: TextStyle(
                                    color: Color(0xFF808D9E),
                                    fontSize: 14,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    height: 1.43,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 303,
                        height: 53,
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(),
                        child: Stack(
                          children: [
                            const Positioned(
                              left: -0.50,
                              top: 0,
                              child: Text(
                                'SKILL',
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
                              left: 0,
                              top: 27,
                              child: Container(
                                width: 84,
                                height: 26,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFB0E5FC),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 6.50,
                              top: 31,
                              child: Text(
                                'UI DESIGN',
                                style: TextStyle(
                                  color: Color(0xFF1D1D25),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 96,
                              top: 27,
                              child: Container(
                                width: 57,
                                height: 26,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFFFD88D),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 102.50,
                              top: 31,
                              child: Text(
                                'ICONS',
                                style: TextStyle(
                                  color: Color(0xFF1D1D25),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 165,
                              top: 27,
                              child: Container(
                                width: 108,
                                height: 26,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFB5E4CA),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 171.50,
                              top: 31,
                              child: Text(
                                'INTERACTION',
                                style: TextStyle(
                                  color: Color(0xFF1D1D25),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  height: 1.43,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
