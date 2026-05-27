import 'package:flutter/material.dart';

/// One value/label pair shown inside [OximeterCard] (e.g. "98 SpO2%").
class OximeterValue extends StatelessWidget {
  const OximeterValue({super.key, required this.value, required this.label});
  final String value, label;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontFamily: 'Inter', fontWeight: FontWeight.w700, height: 1.25)),
      Opacity(opacity: 0.50, child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400, height: 1.57, letterSpacing: -0.50))),
    ]);
  }
}
