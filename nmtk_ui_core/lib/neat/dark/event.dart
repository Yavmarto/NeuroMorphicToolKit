import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'cut/dark_status_bar.dart';
import 'cut/dark_top_bar.dart';
import 'cut/event_widgets.dart';

class NeatEvent extends StatelessWidget {
  @Preview(name: 'Neat Dark – Event', group: 'Neat Dark Pages', size: Size(375, 1350))
  const NeatEvent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 375,
          height: 1350,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(color: Color(0xFF1D1D25)),
          child: Stack(
            children: [
              const Positioned(left: 0, top: 0, child: DarkStatusBar()),
              const Positioned(left: 0, top: 44, child: DarkTopBar()),
              const Positioned(left: 117, top: 172, child: Text('Neat Events', style: TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25))),
              const Positioned(
                left: 41, top: 214,
                child: SizedBox(width: 293, child: Text('Explore our tech events arround the world', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF808D9E), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50))),
              ),
              for (final top in [260, 466, 672, 878, 1084])
                Positioned(left: 16, top: top.toDouble(), child: const EventCard()),
              Positioned(
                left: 16, top: 1289,
                child: Container(
                  width: 343,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: ShapeDecoration(
                    color: const Color(0xFF1D1D25),
                    shape: RoundedRectangleBorder(side: const BorderSide(width: 2, color: Color(0xFF4B4C57)), borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Load more', style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
